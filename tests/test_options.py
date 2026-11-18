"""KAIROS options sleeve: which contract it picks, how much it buys, when it sells, and the rule
that nothing sold is ever uncovered. Alpaca is a stand-in server; no network and no real keys."""

import json
from datetime import date

import httpx
import pytest
from sqlalchemy import select

from spectre.compliance.engine import pre_trade_check
from spectre.db import init_db, make_engine, make_session_factory
from spectre.execution import alpaca
from spectre.execution.alpaca import OptionQuote, parse_occ
from spectre.execution.brokers import PaperBroker
from spectre.execution.guard import TradingLimits, execute
from spectre.execution.models import OptionMark
from spectre.marketdata.universe import seed_universe
from spectre.models import CashFlow, ComplianceRule, Order, OrderType, Portfolio, Price, Security, Side
from spectre.portfolio.positions import value_portfolio
from spectre.portfolio.whatif import ProposedTrade
from spectre.signals.options_strategy import OptionRules, pick_contract, run_options_once
from spectre.signals.pipeline import Pipeline
from spectre.trading import oms
from tests.conftest import D1
from tests.test_alpaca import FakeAlpaca, client_for
from tests.test_strategy import T0, crowd_posts

TODAY = date(2026, 11, 18)
RULES = OptionRules(min_authors=4)
LIMITS = TradingLimits(max_order_notional=10_000, max_daily_notional=100_000, max_orders_per_day=50, max_position_weight=0.25)
NVDA_CALL, TSLA_PUT, TSLA_CALL = "NVDA261224C00155000", "TSLA261218P00400000", "TSLA261218C00400000"


def snap(bid, ask, delta=None):
    s = {"latestQuote": {"bp": bid, "ap": ask}, "latestTrade": {"p": (bid + ask) / 2}}
    if delta is not None:
        s.update(greeks={"delta": delta, "gamma": 0.02, "theta": -0.08, "vega": 0.17, "rho": 0.05}, impliedVolatility=0.4)
    return s


def chain():
    return {
        "NVDA261127C00150000": snap(3.0, 3.1, 0.52),  # 9 days out: too close
        "NVDA261218C00155000": snap(4.9, 5.1, 0.44),  # 30 days
        "NVDA261224C00140000": snap(13.0, 13.4, 0.68),  # 36 days: nearest the middle of the 21-50 day window
        "NVDA261224C00150000": snap(8.0, 8.2, 0.55),
        NVDA_CALL: snap(5.4, 5.6, 0.45),  # ... and nearest the 0.45 target delta
        "NVDA261224C00157500": snap(3.0, 5.0, 0.45),  # right delta, but a spread nobody should pay
        "NVDA261224C00160000": snap(3.2, 3.3, 0.35),
        "NVDA270115C00155000": snap(7.0, 7.2, 0.46),  # 58 days out: too far
        "TSLA261218P00380000": snap(9.0, 9.3, -0.33),
        TSLA_PUT: snap(17.8, 18.2, -0.48),
        "TSLA261218P00420000": snap(29.0, 29.6, -0.62),
        TSLA_CALL: snap(16.0, 16.4, 0.52),
    }


class FakeOptions(FakeAlpaca):
    """FakeAlpaca plus option prices; orders fill at their limit price."""

    def __init__(self, **kw):
        super().__init__(**kw)
        self.chain = chain()

    def __call__(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if path.startswith("/v1beta1/options/snapshots"):
            self.requests.append(request)
            if path.endswith("/snapshots"):
                found = {s: self.chain[s] for s in request.url.params["symbols"].split(",") if s in self.chain}
            else:
                under, kind = path.rsplit("/", 1)[1], request.url.params.get("type")
                found = {s: q for s, q in self.chain.items() if parse_occ(s)[0] == under and kind in (None, parse_occ(s)[2])}
            return httpx.Response(200, json={"snapshots": found, "next_page_token": None})
        if path == "/v2/orders" and request.method == "POST":
            self.fill_price = json.loads(request.content).get("limit_price", self.fill_price)
        return super().__call__(request)


def quotes(symbols=None) -> list[OptionQuote]:
    return [alpaca.quote_from_snapshot(s, q) for s, q in chain().items() if symbols is None or s in symbols]


@pytest.fixture
def book():
    e = make_engine("sqlite://")
    init_db(e)
    factory = make_session_factory(e)
    with factory() as s:
        seed_universe(s)
        pf = Portfolio(name="Options", base_currency="USD")
        s.add(pf)
        s.flush()
        s.add(CashFlow(portfolio_id=pf.id, date=T0.date(), amount=100_000))
        for name, kind in (("No overdraft", "no_negative_cash"), ("No shorts", "no_short_positions"),
                           ("No naked options", "no_naked_options")):
            s.add(ComplianceRule(portfolio_id=pf.id, name=name, rule_type=kind, params={}))
        s.commit()
        pid = pf.id
    Pipeline(factory).process_posts(crowd_posts())  # NVDA bullish (+1.49), TSLA bearish (-1.08)
    return factory, pid


def cycle(s, pid, fake, rules=RULES, today=TODAY, **kw):
    return run_options_once(s, pid, client_for(fake), PaperBroker(), LIMITS, rules, today=today, **kw)


def held(s, pid) -> dict[str, float]:
    v = value_portfolio(s, pid)
    return {r.ticker: float(r.quantity) for r in v.positions.itertuples() if abs(r.quantity) > 1e-9}


# --------------------------------------------------------------------------- choosing a contract


def test_pick_contract_wants_a_tight_market_the_middle_expiry_and_the_target_delta():
    calls = [q for q in quotes() if q.underlying == "NVDA"]
    assert pick_contract(calls, 150.0, OptionRules(), TODAY).symbol == NVDA_CALL
    assert pick_contract(calls, 150.0, OptionRules(target_delta=0.70), TODAY).symbol == "NVDA261224C00140000"
    # Later in the month the nearer expiries have dropped out of the window and January is in it.
    assert pick_contract(calls, 150.0, OptionRules(), date(2026, 12, 10)).symbol == "NVDA270115C00155000"
    assert pick_contract(quotes({"NVDA261224C00157500"}), 150.0, OptionRules(), TODAY) is None, "only a wide market: no trade"
    assert pick_contract([], 150.0, OptionRules(), TODAY) is None


def test_without_greeks_it_takes_the_first_strike_out_of_the_money():
    def bare(symbol, bid, ask):
        return alpaca.quote_from_snapshot(symbol, snap(bid, ask))

    calls = [bare("NVDA261224C00140000", 13.0, 13.4), bare("NVDA261224C00155000", 5.4, 5.6), bare("NVDA261224C00160000", 3.2, 3.3)]
    puts = [bare("NVDA261224P00140000", 3.0, 3.1), bare("NVDA261224P00145000", 4.4, 4.6), bare("NVDA261224P00160000", 12.0, 12.4)]
    assert pick_contract(calls, 150.0, OptionRules(), TODAY).strike == 155
    assert pick_contract(puts, 150.0, OptionRules(), TODAY).strike == 145
    assert pick_contract(calls, 170.0, OptionRules(), TODAY).strike == 160, "nothing out of the money: the nearest strike"


# --------------------------------------------------------------------------- one cycle


def test_cycle_buys_a_call_on_the_bullish_name_and_a_put_on_the_bearish_one(book):
    factory, pid = book
    fake = FakeOptions()
    with factory() as s:
        r = cycle(s, pid, fake)
        done = {a["ticker"]: a for a in r.actions}
        assert set(done) == {NVDA_CALL, TSLA_PUT} and r.targets == ["NVDA", "TSLA"], "strongest read first"
        assert all(a["side"] == "BUY" and a["outcome"] == "executed" for a in done.values())
        # 3% of 100,000 = 3,000 per position. The limit is the ask plus 3%: 5.77 for the NVDA call
        # (five contracts), 18.75 for the TSLA put (one).
        assert done[NVDA_CALL]["quantity"] == 5 and done[NVDA_CALL]["price"] == 5.77, "limit a little through the ask"
        assert done[TSLA_PUT]["quantity"] == 1 and done[TSLA_PUT]["price"] == 18.75
        assert "bullish" in done[NVDA_CALL]["why"] and "bearish" in done[TSLA_PUT]["why"]

        asked = {q.url.path.rsplit("/", 1)[1]: q.url.params for q in fake.requests if "/options/snapshots/" in q.url.path}
        assert asked["NVDA"]["type"] == "call" and asked["TSLA"]["type"] == "put"
        assert asked["NVDA"]["expiration_date_gte"] == "2026-12-09" and asked["NVDA"]["expiration_date_lte"] == "2027-01-07"
        assert float(asked["NVDA"]["strike_price_gte"]) == 127.5 and float(asked["NVDA"]["strike_price_lte"]) == 172.5

        assert held(s, pid) == {NVDA_CALL: 5, TSLA_PUT: 1}
        v = value_portfolio(s, pid)
        # The built-in paper broker fills at the mark (the bid/ask midpoint): 5.50 and 18.00.
        assert v.cash == pytest.approx(100_000 - 5 * 5.5 * 100 - 18.0 * 100)
        assert v.total_value == pytest.approx(100_000), "one contract is worth 100 x its price"
        sec = s.execute(select(Security).where(Security.ticker == NVDA_CALL)).scalar_one()
        assert sec.asset_class == "Option" and sec.multiplier == 100 and sec.maturity_date == date(2026, 12, 24)
        assert sec.name == "NVDA 2026-12-24 155 call" and sec.issuer == "NVIDIA Corporation"
        mark = s.get(OptionMark, sec.id)
        assert mark.delta == 0.45 and mark.mark == pytest.approx(5.5) and mark.underlying_price == 150.0
        orders = s.execute(select(Order)).scalars().all()
        assert all(o.order_type == OrderType.LIMIT.value and o.created_by == "kairos" for o in orders)

        assert cycle(s, pid, fake).actions == [], "both names are already covered"


def test_holdings_are_sold_at_the_stop_and_the_profit_target_and_not_bought_back_that_day(book):
    factory, pid = book
    fake = FakeOptions()
    with factory() as s:
        cycle(s, pid, fake)
        fake.chain[NVDA_CALL] = snap(2.6, 2.8, 0.25)  # bought at 5.50: the bid is 53% lower
        fake.chain[TSLA_PUT] = snap(37.0, 38.0, -0.80)  # bought at 18.00: the bid is 106% higher
        r = cycle(s, pid, fake)
        sold = {a["ticker"]: a for a in r.actions}
        assert set(sold) == {NVDA_CALL, TSLA_PUT} and all(a["side"] == "SELL" and a["outcome"] == "executed" for a in sold.values())
        assert "stop" in sold[NVDA_CALL]["why"] and sold[NVDA_CALL]["price"] == 2.52, "limit a little under the 2.60 bid"
        assert "profit target" in sold[TSLA_PUT]["why"] and sold[TSLA_PUT]["quantity"] == 1
        assert held(s, pid) == {}
        assert value_portfolio(s, pid).cash == pytest.approx(100_000 - 2750 - 1800 + 5 * 2.7 * 100 + 37.5 * 100)
        assert cycle(s, pid, fake).actions == [], "the crowd still likes NVDA, but a stopped-out call is not rebought today"


def test_nothing_is_held_into_expiry_week(book):
    factory, pid = book
    fake = FakeOptions()
    with factory() as s:
        cycle(s, pid, fake)
        r = cycle(s, pid, fake, today=date(2026, 12, 14))  # TSLA put expires in 4 days, NVDA call in 10
        (sell,) = r.actions
        assert sell["ticker"] == TSLA_PUT and sell["side"] == "SELL" and sell["why"] == "4 days to expiry"
        assert held(s, pid) == {NVDA_CALL: 5}


def test_without_a_bid_it_waits_unless_expiry_is_on_top_of_it(book):
    factory, pid = book
    fake = FakeOptions()
    with factory() as s:
        cycle(s, pid, fake)
        del fake.chain[TSLA_PUT]  # the feed has nothing for this contract
        r = cycle(s, pid, fake, today=date(2026, 12, 14))
        (note,) = r.actions
        assert note["outcome"] == "skipped" and "no bid" in note["why"] and held(s, pid)[TSLA_PUT] == 1
        r = cycle(s, pid, fake, today=date(2026, 12, 17))  # one day left: get out at whatever the bid is
        sell = next(a for a in r.actions if a["ticker"] == TSLA_PUT)
        assert sell["outcome"] == "executed" and sell["price"] == 0.01 and TSLA_PUT not in held(s, pid)


def test_a_call_is_sold_when_the_crowd_turns_bearish_and_a_put_replaces_it(book):
    factory, pid = book
    fake = FakeOptions()
    with factory() as s:
        (q,) = quotes({TSLA_CALL})
        sec = alpaca.ensure_option_security(s, q)
        alpaca.store_option_mark(s, sec, q, 400.0)
        s.commit()
        o = oms.create_order(s, portfolio_id=pid, security_id=sec.id, side=Side.BUY, quantity=1,
                             order_type=OrderType.LIMIT, limit_price=16.4)
        assert execute(s, o.id, PaperBroker(), LIMITS).outcome == "executed"
        r = cycle(s, pid, fake)
        tsla = {a["ticker"]: a for a in r.actions if a["ticker"].startswith("TSLA")}
        assert tsla[TSLA_CALL]["side"] == "SELL" and "crowd has turned" in tsla[TSLA_CALL]["why"]
        assert tsla[TSLA_PUT]["side"] == "BUY" and tsla[TSLA_PUT]["outcome"] == "executed"
        assert held(s, pid) == {NVDA_CALL: 5, TSLA_PUT: 1}


def test_total_premium_stays_inside_the_budget(book):
    factory, pid = book
    with factory() as s:
        r = cycle(s, pid, FakeOptions(), rules=OptionRules(min_authors=4, budget=0.04, per_trade=0.03))
        nvda, tsla = r.actions
        assert nvda["ticker"] == NVDA_CALL and nvda["outcome"] == "executed" and nvda["quantity"] == 5
        # 4,000 budget less the 2,750 just spent leaves 1,250: not enough for one TSLA put at up to 1,875.
        assert tsla["outcome"] == "skipped" and "1,875" in tsla["why"] and "1,250" in tsla["why"]
        assert held(s, pid) == {NVDA_CALL: 5}

        strict = cycle(s, pid, FakeOptions(), rules=OptionRules(min_authors=4, enter=5.0))
        assert strict.actions == [] and strict.targets == [], "no read is strong enough"


def test_dry_run_touches_nothing(book):
    factory, pid = book
    with factory() as s:
        r = cycle(s, pid, FakeOptions(), dry_run=True)
        assert [(a["ticker"], a["quantity"], a["outcome"]) for a in r.actions] == [(NVDA_CALL, 5, "dry run"), (TSLA_PUT, 1, "dry run")]
        assert s.execute(select(Order)).first() is None
        assert s.execute(select(Security).where(Security.asset_class == "Option")).first() is None


def test_option_orders_reach_alpaca_as_whole_contract_limit_orders(book):
    factory, pid = book
    fake = FakeOptions()
    client = client_for(fake)
    with factory() as s:
        r = run_options_once(s, pid, client, alpaca.AlpacaPaperBroker(client, sleep=lambda _: None), LIMITS, RULES, today=TODAY)
        assert [a["outcome"] for a in r.actions] == ["executed", "executed"]
        first, second = (json.loads(q.content) for q in fake.requests if q.url.path == "/v2/orders" and q.method == "POST")
        assert first["symbol"] == NVDA_CALL and first["qty"] == "5" and first["side"] == "buy"
        assert first["type"] == "limit" and first["limit_price"] == "5.77" and first["time_in_force"] == "day"
        assert second["symbol"] == TSLA_PUT and second["qty"] == "1" and second["limit_price"] == "18.75"
        assert value_portfolio(s, pid).cash == pytest.approx(100_000 - 5 * 5.77 * 100 - 18.75 * 100)


def test_marks_of_held_contracts_are_refreshed(book):
    factory, pid = book
    fake = FakeOptions()
    with factory() as s:
        cycle(s, pid, fake)
        fake.chain[NVDA_CALL] = snap(6.0, 6.4, 0.50)
        assert alpaca.sync_option_marks(s, client_for(fake)) == 2
        sec = s.execute(select(Security).where(Security.ticker == NVDA_CALL)).scalar_one()
        mark = s.get(OptionMark, sec.id)
        assert mark.mark == pytest.approx(6.2) and mark.delta == 0.50 and mark.underlying_price == 150.0
        v = value_portfolio(s, pid)
        assert v.positions.at[sec.id, "market_value"] == pytest.approx(5 * 6.2 * 100)


# --------------------------------------------------------------------------- never naked


def test_sold_options_must_be_covered(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    s.add(ComplianceRule(portfolio_id=pf.id, name="No naked options", rule_type="no_naked_options", params={}))
    call = Security(ticker="AAA261218C00120000", name="AAA call", asset_class="Option", currency="USD", multiplier=100.0)
    put = Security(ticker="AAA261218P00100000", name="AAA put", asset_class="Option", currency="USD", multiplier=100.0)
    odd = Security(ticker="AAA-WEEKLY-CALL", name="unparseable", asset_class="Option", currency="USD", multiplier=100.0)
    s.add_all([call, put, odd])
    s.flush()
    s.add_all([Price(security_id=x.id, date=D1, close=3.0) for x in (call, put, odd)])
    s.commit()
    v = value_portfolio(s, pf.id, D1)
    shares, cash = float(v.positions.at[aaa.id, "quantity"]), v.cash
    lots = int(shares // 100)
    assert lots >= 2 and cash > 50_000

    def check(security, side, qty):
        return pre_trade_check(s, pf.id, [ProposedTrade(security.id, side, qty)], D1, record=False)

    assert not check(call, Side.BUY, 10).blocked and not check(put, Side.BUY, 10).blocked, "bought options always pass"
    assert not check(call, Side.SELL, lots).blocked, "a call sold against 100 shares each is covered"
    res = check(call, Side.SELL, lots + 1)
    assert res.blocked and {b.scope for b in res.new_breaches} == {"AAA"} and "as cover" in res.new_breaches[0].message
    secured = int(cash // 10_000)  # strike 100 x 100 shares = 10,000 of cash per put
    assert not check(put, Side.SELL, secured - 1).blocked, "a put with its strike set aside in cash is secured"
    res = check(put, Side.SELL, secured + 10)
    assert res.blocked and {b.scope for b in res.new_breaches} == {"cash"}
    res = check(odd, Side.SELL, 1)
    assert res.blocked and "cannot verify cover" in res.new_breaches[0].message
