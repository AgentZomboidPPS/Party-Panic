"""Alpaca adapter, tested against a stand-in server that answers in the shapes Alpaca documents
(and that the live paper API returned on 2026-11-18). No network and no real keys are used."""

import json
from datetime import date, datetime

import httpx
import pytest
from sqlalchemy import select

from spectre.db import init_db, make_engine, make_session_factory
from spectre.execution import alpaca
from spectre.execution.brokers import BrokerReject
from spectre.execution.guard import TradingLimits, execute
from spectre.marketdata.universe import seed_universe
from spectre.models import CashFlow, OrderStatus, Portfolio, Price, Security, Side
from spectre.portfolio.positions import value_portfolio
from spectre.signals.models import PriceTick
from spectre.trading import oms

LIMITS = TradingLimits(max_order_notional=5_000, max_daily_notional=50_000, max_position_weight=0.5)


class FakeAlpaca:
    """Just enough of Alpaca's API to exercise the adapter."""

    def __init__(self, is_open=True, fill_after_polls=1, final_status="filled", fill_price="151.40", partial=None,
                 multiplier="1", fills_from=None):
        self.is_open, self.fill_after_polls, self.final_status = is_open, fill_after_polls, final_status
        self.fills_from = fills_from  # a buy limit below this (or a sell limit above it) is never filled
        self.multiplier = multiplier
        self.cash = "100000"
        self.positions: list[dict] = []
        self.activities: list[dict] = []
        self.base_value = 100000.0
        self.coin_quotes = {"BTC/USD": {"bp": 62990.0, "ap": 63010.0, "t": "2026-11-18T18:44:05.077083862Z"},
                            "ETH/USD": {"bp": 1769.0, "ap": 1771.0, "t": "2026-11-18T18:44:03.209396325Z"},
                            "SOL/USD": {"bp": 0, "ap": 73.6, "t": "2026-11-18T18:04:13.3Z"}}  # one-sided: unusable
        self.fill_price, self.partial = fill_price, partial
        self.orders: dict[str, dict] = {}
        self.polls = 0
        self.requests: list[httpx.Request] = []
        self.cancelled: list[str] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, host = request.url.path, request.url.host
        if host == "paper-api.alpaca.markets":
            if path == "/v2/clock":
                return httpx.Response(200, json={"is_open": self.is_open, "next_open": "2026-11-19T09:30:00-05:00",
                                                 "next_close": "2026-11-18T16:00:00-05:00", "timestamp": "x"})
            if path == "/v2/account":
                return httpx.Response(200, json={"status": "ACTIVE", "cash": self.cash, "equity": "100000",
                                                 "multiplier": self.multiplier})
            if path == "/v2/positions":
                return httpx.Response(200, json=self.positions)
            if path == "/v2/account/activities":
                size, after = int(request.url.params.get("page_size", 100)), request.url.params.get("page_token")
                rows = self.activities
                if after:
                    rows = rows[next(i for i, a in enumerate(rows) if a["id"] == after) + 1:]
                return httpx.Response(200, json=rows[:size])
            if path == "/v2/account/portfolio/history":
                return httpx.Response(200, json={"base_value": self.base_value, "equity": [], "timestamp": []})
            if path == "/v2/account/configurations":
                if request.method == "PATCH":
                    self.multiplier = json.loads(request.content).get("max_margin_multiplier", self.multiplier)
                return httpx.Response(200, json={"max_margin_multiplier": self.multiplier, "no_shorting": False})
            if path == "/v2/orders" and request.method == "POST":
                body = json.loads(request.content)
                if body["symbol"] == "BAD":
                    return httpx.Response(422, json={"code": 42210000, "message": "asset BAD is not tradable"})
                o = {"id": f"alp-{len(self.orders) + 1}", "status": "accepted", "filled_qty": "0", "filled_avg_price": None, **body}
                self.orders[o["id"]] = o
                if self.fills_from is not None and "limit_price" in body:
                    px = float(body["limit_price"])
                    o["never"] = px < self.fills_from if body["side"] == "buy" else px > self.fills_from
                    if not o["never"] and self.fill_after_polls == 0:  # marketable: done at once
                        o.update(status="filled", filled_qty=o["qty"], filled_avg_price=body["limit_price"])
                return httpx.Response(200, json=o)
            if path.startswith("/v2/orders/"):
                oid = path.rsplit("/", 1)[1]
                o = self.orders[oid]
                if request.method == "DELETE":
                    self.cancelled.append(oid)
                    if o["status"] != "filled":
                        o["status"] = "canceled"
                        if self.partial:
                            o.update(filled_qty=self.partial, filled_avg_price=self.fill_price)
                    return httpx.Response(204)
                self.polls += 1
                if self.polls >= self.fill_after_polls and o["status"] == "accepted" and not o.get("never"):
                    o["status"] = self.final_status
                    if self.final_status == "filled":
                        o.update(filled_qty=o["qty"], filled_avg_price=self.fill_price)
                return httpx.Response(200, json=o)
        if host == "data.alpaca.markets":
            if path == "/v2/stocks/bars":
                wanted = request.url.params["symbols"].split(",")
                if "page_token" not in request.url.params:  # first page: two days, more to come
                    bars = {"NVDA": [{"c": 148.0, "t": "2026-11-16T05:00:00Z"}, {"c": 150.0, "t": "2026-11-17T05:00:00Z"}],
                            "SPY": [{"c": 725.0, "t": "2026-11-16T05:00:00Z"}]}
                    token = "more"
                else:  # second page: the rest, including the day in progress
                    bars = {"NVDA": [{"c": 151.0, "t": "2026-11-18T05:00:00Z"}, {"c": 0, "t": "2026-07-03T04:00:00Z"}],
                            "SPY": [{"c": 729.0, "t": "2026-11-17T05:00:00Z"}]}
                    token = None
                return httpx.Response(200, json={"bars": {k: v for k, v in bars.items() if k in wanted}, "next_page_token": token})
            if path == "/v1beta3/crypto/us/bars":
                wanted = request.url.params["symbols"].split(",")
                bars = {"BTC/USD": [{"c": 64113.15, "t": "2026-11-14T00:00:00Z"}, {"c": 65320.5, "t": "2026-11-15T00:00:00Z"}]}
                return httpx.Response(200, json={"bars": {k: v for k, v in bars.items() if k in wanted}, "next_page_token": None})
            if path == "/v1beta3/crypto/us/latest/quotes":
                wanted = request.url.params["symbols"].split(",")
                return httpx.Response(200, json={"quotes": {s: self.coin_quotes[s] for s in wanted if s in self.coin_quotes}})
            if path == "/v2/stocks/trades/latest":
                wanted = request.url.params["symbols"].split(",")
                trades = {"NVDA": {"p": 151.38, "s": 150, "t": "2026-11-18T18:11:48.668719255Z", "x": "V"},
                          "SPY": {"p": 729.93, "s": 66, "t": "2026-11-18T18:11:49.565822695Z", "x": "V"}}
                return httpx.Response(200, json={"trades": {s: trades[s] for s in wanted if s in trades}})
            if path == "/v1beta1/options/snapshots/NVDA":
                if "page_token" not in request.url.params:
                    return httpx.Response(200, json={"next_page_token": "p2", "snapshots": {
                        "NVDA261218C00150000": {
                            "latestQuote": {"bp": 9.9, "ap": 10.1, "bs": 10, "as": 12, "t": "2026-11-18T18:11:00Z"},
                            "latestTrade": {"p": 10.0, "s": 1, "t": "2026-11-18T18:10:00Z"},
                            "greeks": {"delta": 0.55, "gamma": 0.02, "theta": -0.08, "vega": 0.17, "rho": 0.05},
                            "impliedVolatility": 0.42, "dailyBar": {"v": 1234}},
                        "not-an-option-symbol": {}}})
                return httpx.Response(200, json={"next_page_token": None, "snapshots": {
                    "NVDA261218P00150000": {"latestQuote": {"bp": 8.0, "ap": 0.0}}}})  # no greeks, empty ask
        return httpx.Response(404, json={"message": f"unexpected {request.method} {request.url}"})


def client_for(fake, **kw):
    return alpaca.AlpacaClient(key_id="PKTEST", secret_key="secret", transport=httpx.MockTransport(fake), **kw)


@pytest.fixture
def book():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        seed_universe(s)
        pf = Portfolio(name="Alpaca paper", base_currency="USD")
        s.add(pf)
        s.flush()
        s.add(CashFlow(portfolio_id=pf.id, date=date(2026, 11, 18), amount=100_000))
        nvda = s.execute(select(Security).where(Security.ticker == "NVDA")).scalar_one()
        s.add(Price(security_id=nvda.id, date=date(2026, 11, 18), close=151.0))
        s.commit()
        yield s, pf, nvda


def test_client_sends_the_key_headers_and_only_when_configured():
    fake = FakeAlpaca()
    client_for(fake).account()
    assert fake.requests[0].headers["APCA-API-KEY-ID"] == "PKTEST"
    assert fake.requests[0].headers["APCA-API-SECRET-KEY"] == "secret"
    bare = alpaca.AlpacaClient(key_id="", secret_key="", transport=httpx.MockTransport(fake))
    bare.account()
    assert "APCA-API-KEY-ID" not in fake.requests[1].headers, "no keys configured: none are invented"


def test_api_errors_carry_alpacas_message():
    with pytest.raises(alpaca.AlpacaError, match="HTTP 404"):
        client_for(FakeAlpaca())._call("GET", "https://paper-api.alpaca.markets/v2/nope")


def test_paper_broker_refuses_any_non_paper_address():
    live = alpaca.AlpacaClient(key_id="AK", secret_key="s", trading_url="https://api.alpaca.markets",
                               transport=httpx.MockTransport(FakeAlpaca()))
    assert not live.paper
    with pytest.raises(ValueError, match="only talks to paper-api.alpaca.markets"):
        alpaca.AlpacaPaperBroker(live)


def test_order_fills_through_alpaca_and_lands_in_the_ledger(book):
    s, pf, nvda = book
    fake = FakeAlpaca(fill_after_polls=2)
    broker = alpaca.AlpacaPaperBroker(client_for(fake), sleep=lambda _: None)
    o = oms.create_order(s, portfolio_id=pf.id, security_id=nvda.id, side=Side.BUY, quantity=10)
    r = execute(s, o.id, broker, LIMITS)
    assert r.outcome == "executed" and r.broker == "alpaca-paper" and r.price == pytest.approx(151.40)
    sent = json.loads(next(q for q in fake.requests if q.method == "POST").content)
    assert sent["symbol"] == "NVDA" and sent["qty"] == "10" and sent["side"] == "buy"
    assert sent["type"] == "market" and sent["time_in_force"] == "day" and sent["client_order_id"].startswith(f"spectre-{o.id}-")
    assert o.status == OrderStatus.FILLED.value
    v = value_portfolio(s, pf.id, datetime.now().date())
    assert v.positions.at[nvda.id, "quantity"] == 10 and v.cash == pytest.approx(100_000 - 1514.0)


def test_closed_market_rejects_before_anything_is_sent(book):
    s, pf, nvda = book
    fake = FakeAlpaca(is_open=False)
    o = oms.create_order(s, portfolio_id=pf.id, security_id=nvda.id, side=Side.BUY, quantity=10)
    r = execute(s, o.id, alpaca.AlpacaPaperBroker(client_for(fake), sleep=lambda _: None), LIMITS)
    assert r.outcome == "blocked" and "market is closed" in r.reasons[0]
    assert not any(q.method == "POST" for q in fake.requests) and o.status == OrderStatus.APPROVED.value


def test_cash_only_mode_refuses_to_trade_while_the_account_can_borrow(book):
    s, pf, nvda = book
    fake = FakeAlpaca(multiplier="2")
    client = client_for(fake)
    o = oms.create_order(s, portfolio_id=pf.id, security_id=nvda.id, side=Side.BUY, quantity=10)
    r = execute(s, o.id, alpaca.AlpacaPaperBroker(client, sleep=lambda _: None), LIMITS)
    assert r.outcome == "blocked" and "margin multiplier 2" in r.reasons[0]
    assert not any(q.method == "POST" for q in fake.requests), "nothing is sent while borrowing is possible"

    assert client.set_configurations(max_margin_multiplier="1")["max_margin_multiplier"] == "1"
    sent = next(q for q in fake.requests if q.method == "PATCH")
    assert sent.url.path == "/v2/account/configurations" and json.loads(sent.content) == {"max_margin_multiplier": "1"}
    assert client.configurations()["max_margin_multiplier"] == "1"
    assert execute(s, o.id, alpaca.AlpacaPaperBroker(client, sleep=lambda _: None), LIMITS).outcome == "executed"


def test_unfilled_order_is_cancelled_and_partial_fills_are_kept(book):
    s, pf, nvda = book
    never = FakeAlpaca(fill_after_polls=10**9)
    o = oms.create_order(s, portfolio_id=pf.id, security_id=nvda.id, side=Side.BUY, quantity=10)
    broker = alpaca.AlpacaPaperBroker(client_for(never), fill_timeout=0.0, sleep=lambda _: None)
    with pytest.raises(BrokerReject, match="not filled within"):
        broker.submit(s, o)
    assert never.cancelled == ["alp-1"], "an order that does not fill is not left working at the broker"

    part = FakeAlpaca(fill_after_polls=10**9, partial="4")
    r = execute(s, o.id, alpaca.AlpacaPaperBroker(client_for(part), fill_timeout=0.0, sleep=lambda _: None), LIMITS)
    assert r.outcome == "executed" and r.quantity == 4
    assert o.status == OrderStatus.PARTIALLY_FILLED.value and o.remaining_quantity == 6


def test_broker_side_rejections_become_clear_reasons(book):
    s, pf, nvda = book
    o = oms.create_order(s, portfolio_id=pf.id, security_id=nvda.id, side=Side.BUY, quantity=10)
    with pytest.raises(BrokerReject, match="ended as rejected"):
        alpaca.AlpacaPaperBroker(client_for(FakeAlpaca(final_status="rejected")), sleep=lambda _: None).submit(s, o)
    nvda.ticker = "BAD"
    with pytest.raises(BrokerReject, match="not tradable"):
        alpaca.AlpacaPaperBroker(client_for(FakeAlpaca()), sleep=lambda _: None).submit(s, o)


def test_limit_orders_carry_their_price(book):
    from spectre.models import OrderType

    s, pf, nvda = book
    fake = FakeAlpaca()
    o = oms.create_order(s, portfolio_id=pf.id, security_id=nvda.id, side=Side.BUY, quantity=3,
                         order_type=OrderType.LIMIT, limit_price=150.5)
    alpaca.AlpacaPaperBroker(client_for(fake), sleep=lambda _: None).submit(s, o)
    sent = json.loads(next(q for q in fake.requests if q.method == "POST").content)
    assert sent["type"] == "limit" and sent["limit_price"] == "150.50"


def test_latest_prices_become_ticks_and_the_days_close(book):
    s, _, nvda = book
    n = alpaca.sync_prices(s, client_for(FakeAlpaca()), tickers=["NVDA", "SPY", "TSLA"])
    assert n == 2, "TSLA had no trade in the response and is simply skipped"
    tick = s.execute(select(PriceTick).where(PriceTick.ticker == "NVDA")).scalar_one()
    assert tick.price == 151.38 and tick.source == "alpaca" and tick.observed_at == datetime(2026, 11, 18, 18, 11, 48)
    assert s.execute(select(Price.close).where(Price.security_id == nvda.id)).scalar_one() == 151.38
    assert alpaca.sync_prices(s, client_for(FakeAlpaca()), tickers=["NVDA", "SPY"]) == 2, "running it twice is harmless"
    assert len(s.execute(select(PriceTick)).scalars().all()) == 2


def test_option_chain_parsing_and_paging():
    assert alpaca.parse_occ("NVDA261218C00150000") == ("NVDA", date(2026, 12, 18), "call", 150.0)
    assert alpaca.parse_occ("BRK.B270115P00412500") == ("BRK.B", date(2027, 1, 15), "put", 412.5)
    assert alpaca.parse_occ("garbage") is None
    fake = FakeAlpaca()
    chain = client_for(fake).option_chain("nvda", expiration_date=date(2026, 12, 18), strike_price_gte=140)
    assert [q.symbol for q in chain] == ["NVDA261218C00150000", "NVDA261218P00150000"], "both pages, junk symbol dropped"
    call, put = chain
    assert call.type == "call" and call.strike == 150.0 and call.mid == pytest.approx(10.0)
    assert call.implied_volatility == 0.42 and call.delta == 0.55 and call.volume == 1234
    assert put.delta is None and put.mid is None, "no greeks and an empty ask stay empty; nothing is invented"
    first = next(q for q in fake.requests if "options/snapshots" in q.url.path)
    assert first.url.params["feed"] == "indicative" and first.url.params["expiration_date"] == "2026-12-18"
    assert first.url.params["strike_price_gte"] == "140"
    assert call.to_dict()["expiration"] == "2026-12-18"


def test_timestamps_with_nanoseconds():
    assert alpaca.parse_time("2026-11-18T18:11:49.565822695Z") == datetime(2026, 11, 18, 18, 11, 49, 565822)
    assert alpaca.parse_time("2026-11-18T13:11:50-05:00") == datetime(2026, 11, 18, 18, 11, 50)


def test_holdings_are_valued_at_the_brokers_own_prices(tmp_path):
    """The account should be worth the same here as in Alpaca's app, options included."""
    from spectre.execution.models import OptionMark  # noqa: F401  (registers the table)
    from spectre.marketdata.prices import latest_prices
    from spectre.marketdata.universe import seed_universe
    from spectre.signals.sources.base import utcnow

    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        seed_universe(s)
        call = Security(ticker="AMZN261224C00275000", name="AMZN call", asset_class="Option", currency="USD", multiplier=100.0)
        s.add(call)
        s.commit()
        amzn = s.execute(select(Security).where(Security.ticker == "AMZN")).scalar_one()
        btc = s.execute(select(Security).where(Security.ticker == "BTC")).scalar_one()
        alpaca.upsert_prices(s, [{"security_id": call.id, "date": utcnow().date(), "close": 9.35}])  # SPECTRE's mid
        fake = FakeAlpaca()
        fake.positions = [
            {"symbol": "AMZN", "asset_class": "us_equity", "qty": "56", "current_price": "270.89"},
            {"symbol": "AMZN261224C00275000", "asset_class": "us_option", "qty": "3", "current_price": "8.75"},
            {"symbol": "BTCUSD", "asset_class": "crypto", "qty": "0.0529", "current_price": "62815.1"},
            {"symbol": "NOTINBOOK", "asset_class": "us_equity", "qty": "1", "current_price": "5"},
            {"symbol": "MSFT", "asset_class": "us_equity", "qty": "1", "current_price": None},
        ]
        assert alpaca.mark_to_broker(s, client_for(fake)) == 3
        px = latest_prices(s, [amzn.id, call.id, btc.id], utcnow().date())
        assert px[amzn.id] == 270.89 and px[call.id] == 8.75 and px[btc.id] == 62815.1


def test_the_trading_day_is_read_off_the_market_clock():
    def clock(now, is_open, next_open, next_close):
        return {"timestamp": now, "is_open": is_open, "next_open": next_open, "next_close": next_close}

    # Mid-session: run, and say how long is left.
    wanted, why = alpaca.trading_day_state(clock("2026-11-19T10:00:00.123456789-05:00", True, "2026-11-20T09:30:00-05:00", "2026-11-19T16:00:00-05:00"))
    assert wanted and "is open (it closes in 360 minutes)" in why
    # An hour before the open: run, so the morning's posts are in hand when it does.
    wanted, why = alpaca.trading_day_state(clock("2026-11-19T08:30:00-05:00", False, "2026-11-19T09:30:00-05:00", "2026-11-19T16:00:00-05:00"))
    assert wanted and "opens in 60 minutes" in why
    # The evening before, and a weekend: rest.
    wanted, why = alpaca.trading_day_state(clock("2026-11-19T20:00:00-05:00", False, "2026-11-20T09:30:00-05:00", "2026-11-20T16:00:00-05:00"))
    assert not wanted and "opens in 13.5 hours" in why
    assert not alpaca.trading_day_state(clock("2026-11-21T12:00:00-05:00", False, "2026-11-23T09:30:00-05:00", "2026-11-23T16:00:00-05:00"))[0]
    # A longer lead reaches further back.
    assert alpaca.trading_day_state(clock("2026-11-19T07:00:00-05:00", False, "2026-11-19T09:30:00-05:00", "2026-11-19T16:00:00-05:00"), lead_minutes=180)[0]
