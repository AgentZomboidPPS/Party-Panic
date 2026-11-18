"""Coins: recognised in posts, priced from Alpaca, sized in fractions, routed around the clock,
and reconciled against the broker (whose fee on a purchase is taken in coin)."""

import json
from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import inspect, select, text

from spectre.db import init_db, make_engine, make_session_factory
from spectre.execution import alpaca
from spectre.execution.guard import TradingLimits, execute
from spectre.marketdata.universe import CRYPTO_TICKERS, crypto_base, lot_size, seed_universe
from spectre.models import CashFlow, ComplianceRule, OrderStatus, Portfolio, Price, Security, Side, Trade
from spectre.portfolio.positions import value_portfolio
from spectre.signals.models import PriceTick
from spectre.signals.pipeline import Pipeline
from spectre.signals.sources import stocktwits
from spectre.signals.sources.base import Post
from spectre.signals.strategy import CRYPTO, live_signals, run_once
from spectre.trading import oms
from tests.test_alpaca import FakeAlpaca, client_for

T0 = datetime(2026, 11, 18, 15, 0)
LIMITS = TradingLimits(max_order_notional=50_000, max_daily_notional=500_000, max_orders_per_day=50, max_position_weight=0.5)


def _post(i, author, text, label, minute=0, prices=None, symbols=("BTC",)):
    return Post("stocktwits", f"c{i}", author, text, T0 + timedelta(minutes=minute), "en", followers=20, account_age_days=500,
                source_sentiment=label, meta={"symbols": list(symbols), "prices": prices or {}})


def crowd() -> list[Post]:
    """Bitcoin clearly liked (6 of 7 authors), ether clearly not (4 of 5), and NVDA liked too."""
    posts = []
    bulls = ["$BTC.X reclaimed the range high, this looks strong", "Spot demand for bitcoin keeps absorbing every dip",
             "Adding to my $BTC.X stack again this week", "Funding is flat and $BTC.X is grinding up, healthy",
             "Bitcoin dominance climbing, staying long here", "$BTC.X weekly close above resistance would be huge"]
    for a, body in enumerate(bulls):
        posts.append(_post(f"b{a}", f"cb{a}", body, "Bullish", a, {"BTC": 63_000.0}))
    posts.append(_post("bb", "cbear", "$BTC.X is one bad headline from a flush", "Bearish", 7, {"BTC": 63_000.0}))
    bears = ["$ETH.X keeps losing ground, nothing to like", "Ethereum fees collapsing and nobody is using it",
             "Sold the last of my $ETH.X, dead money", "$ETH.X breaking down against everything"]
    for a, body in enumerate(bears):
        posts.append(_post(f"e{a}", f"eb{a}", body, "Bearish", a, {"ETH": 1_770.0}, ("ETH",)))
    posts.append(_post("eu", "ebull", "$ETH.X is cheap here, buying a little", "Bullish", 5, {"ETH": 1_770.0}, ("ETH",)))
    stock = ["$NVDA clean breakout above resistance this morning", "Data center demand keeps surprising, long $NVDA",
             "Adding to my $NVDA position before the print", "$NVDA guidance will crush, the supply checks are great",
             "Every hyperscaler is still buying, $NVDA is the trade"]
    for a, body in enumerate(stock):
        posts.append(_post(f"n{a}", f"nb{a}", body, "Bullish", a, {"NVDA": 150.0}, ("NVDA",)))
    return posts


@pytest.fixture
def book():
    e = make_engine("sqlite://")
    init_db(e)
    factory = make_session_factory(e)
    with factory() as s:
        seed_universe(s)
        pf = Portfolio(name="Coins", base_currency="USD")
        s.add(pf)
        s.flush()
        s.add(CashFlow(portfolio_id=pf.id, date=T0.date(), amount=100_000))
        s.add(ComplianceRule(portfolio_id=pf.id, name="No overdraft", rule_type="no_negative_cash", params={}))
        s.add(ComplianceRule(portfolio_id=pf.id, name="No shorts", rule_type="no_short_positions", params={}))
        s.commit()
        pid = pf.id
    Pipeline(factory).process_posts(crowd())
    return factory, pid


def coin(s, ticker="BTC") -> Security:
    return s.execute(select(Security).where(Security.ticker == ticker)).scalar_one()


# --------------------------------------------------------------------------- naming


def test_platform_symbols_map_to_the_coin_and_look_alikes_are_dropped():
    assert crypto_base("BTC.X") == "BTC" and crypto_base("BTC/USD") == "BTC" and crypto_base("ETHUSD") == "ETH"
    assert crypto_base("BTC") is None and crypto_base("AAPL") is None and crypto_base("XYZUSD") is None
    assert {"BTC", "ETH", "SOL"} <= CRYPTO_TICKERS and lot_size("Crypto") == 1e-6 and lot_size("Equity") == 1.0
    # Stocktwits writes the coin as BTC.X; a plain BTC there is a fund that shares the letters.
    post = stocktwits.parse_message({
        "id": 9, "body": "$BTC.X strong", "created_at": "2026-11-18T17:15:27Z", "user": {"id": 1},
        "symbols": [{"symbol": "BTC.X"}, {"symbol": "BTC"}, {"symbol": "COIN"}],
        "prices": [{"symbol": "BTC.X", "price": "63197.8"}, {"symbol": "BTC", "price": "28.11"}, {"symbol": "COIN", "price": "201.5"}],
    })
    assert post.meta["symbols"] == ["BTC", "COIN"]
    assert post.meta["prices"] == {"BTC": 63197.8, "COIN": 201.5}, "the fund's price never becomes the coin's"


def test_coins_are_read_from_the_crowd_like_any_other_name(book):
    factory, _ = book
    with factory() as s:
        sig = {x.ticker: x for x in live_signals(s, min_authors=4)}
        assert set(sig) == {"BTC", "ETH", "NVDA"}
        assert sig["BTC"].asset_class == "Crypto" and sig["NVDA"].asset_class == "Equity"
        assert sig["BTC"].n_authors == 7 and sig["BTC"].net == pytest.approx(5 / 7) and sig["BTC"].price == 63_000.0
        assert sig["ETH"].score < 0


# --------------------------------------------------------------------------- prices


def test_coin_prices_come_from_the_quote_midpoint(book):
    factory, _ = book
    fake = FakeAlpaca()
    with factory() as s:
        assert alpaca.sync_prices(s, client_for(fake), tickers=["BTC", "ETH", "SOL", "NVDA"]) == 3
        asked = next(q for q in fake.requests if "crypto" in q.url.path).url.params["symbols"]
        assert asked == "BTC/USD,ETH/USD,SOL/USD"
        btc = coin(s)
        tick = s.execute(select(PriceTick).where(PriceTick.security_id == btc.id, PriceTick.source == "alpaca")).scalar_one()
        assert tick.price == 63_000.0 and tick.observed_at == datetime(2026, 11, 18, 18, 44, 5)
        close = s.execute(select(Price.close).where(Price.security_id == btc.id, Price.date == date(2026, 11, 18))).scalar_one()
        assert close == 63_000.0
        sol_ticks = s.execute(select(PriceTick).where(PriceTick.ticker == "SOL", PriceTick.source == "alpaca")).all()
        assert sol_ticks == [], "a one-sided quote is not a price"


# --------------------------------------------------------------------------- the coin book


def test_coin_book_buys_fractions_inside_its_own_allowance(book):
    factory, pid = book
    with factory() as s:
        r = run_once(s, pid, limits=LIMITS, top_n=3, invest=0.10, min_authors=4, asset_classes=CRYPTO)
        assert r.targets == ["BTC"] and {x.ticker for x in r.signals} == {"BTC", "ETH"}, "only coins are considered"
        (buy,) = r.actions
        # 100,000 x 10% / 3 coins = 3,333.33 per coin -> 0.052910 BTC at 63,000 (rounded down to a millionth)
        assert buy["ticker"] == "BTC" and buy["quantity"] == pytest.approx(0.05291) and buy["outcome"] == "executed"
        v = value_portfolio(s, pid)
        assert v.positions.at[coin(s).id, "quantity"] == pytest.approx(0.05291)
        assert v.cash == pytest.approx(100_000 - 0.05291 * 63_000)
        assert run_once(s, pid, limits=LIMITS, top_n=3, invest=0.10, min_authors=4, asset_classes=CRYPTO).actions == [], \
            "nothing left to top up but dust"

        stocks = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, min_authors=4)
        assert [a["ticker"] for a in stocks.actions] == ["NVDA"] and {x.ticker for x in stocks.signals} == {"NVDA"}
        assert stocks.actions[0]["quantity"] == 166, "the stock book still buys whole shares: 25,000 at 150"


def test_coin_is_sold_when_the_crowd_turns(book):
    factory, pid = book
    with factory() as s:
        run_once(s, pid, limits=LIMITS, top_n=3, invest=0.10, min_authors=4, asset_classes=CRYPTO)
    turns = ["$BTC.X rolling over hard now", "That bitcoin breakout was a trap", "Out of $BTC.X completely",
             "ETF outflows just gutted the $BTC.X story", "$BTC.X lost the 50 day, not a dip to buy",
             "Leverage is getting wiped on $BTC.X", "Short $BTC.X from here with a tight stop",
             "Everyone is trapped long $BTC.X at the highs"]
    Pipeline(factory).process_posts([_post(f"z{a}", f"turn{a}", t, "Bearish", 30 + a, {"BTC": 60_000.0}) for a, t in enumerate(turns)])
    with factory() as s:
        r = run_once(s, pid, limits=LIMITS, top_n=3, invest=0.10, min_authors=4, asset_classes=CRYPTO)
        (sell,) = r.actions
        assert sell["side"] == "SELL" and sell["quantity"] == pytest.approx(0.05291) and sell["outcome"] == "executed"
        assert coin(s).id not in value_portfolio(s, pid).positions.index, "the whole position is gone, no dust left"


def test_a_book_over_its_allowance_lets_go_of_its_weakest_outsider(book):
    factory, pid = book
    with factory() as s:
        eth = coin(s, "ETH")
        # Coins already at 30% of the portfolio (ETH, which the crowd dislikes mildly here, and BTC).
        s.add(Trade(portfolio_id=pid, security_id=eth.id, side="BUY", quantity=10.0, price=1_770.0, currency="USD", trade_date=T0.date()))
        s.add(Trade(portfolio_id=pid, security_id=coin(s).id, side="BUY", quantity=0.2, price=63_000.0, currency="USD", trade_date=T0.date()))
        s.commit()
        # exit_below is set so low that nothing is sold for its score alone: only the allowance can force a sale.
        r = run_once(s, pid, limits=LIMITS, top_n=1, invest=0.10, min_authors=4, exit_below=-9.0, asset_classes=CRYPTO)
        (trim,) = r.actions
        assert trim["ticker"] == "ETH" and trim["side"] == "SELL" and "over its 10% allowance" in trim["why"]
        assert coin(s).id in value_portfolio(s, pid).positions.index, "the top name is kept even though the book is still full"


# --------------------------------------------------------------------------- routing


def test_coin_orders_go_out_as_pairs_at_any_hour(book):
    factory, pid = book
    fake = FakeAlpaca(is_open=False, fill_price="63005.5")
    with factory() as s:
        o = oms.create_order(s, portfolio_id=pid, security_id=coin(s).id, side=Side.BUY, quantity=0.05291)
        r = execute(s, o.id, alpaca.AlpacaPaperBroker(client_for(fake), sleep=lambda _: None), LIMITS)
        assert r.outcome == "executed" and r.price == 63005.5, "coins trade while the stock market is closed"
        sent = json.loads(next(q for q in fake.requests if q.method == "POST").content)
        assert sent["symbol"] == "BTC/USD" and sent["qty"] == "0.05291" and sent["time_in_force"] == "gtc" and sent["type"] == "market"
        assert not any(q.url.path == "/v2/clock" for q in fake.requests)

        nvda = s.execute(select(Security).where(Security.ticker == "NVDA")).scalar_one()
        o2 = oms.create_order(s, portfolio_id=pid, security_id=nvda.id, side=Side.BUY, quantity=1)
        assert "market is closed" in execute(s, o2.id, alpaca.AlpacaPaperBroker(client_for(fake), sleep=lambda _: None), LIMITS).reasons[0]


def test_a_coin_sale_never_asks_for_more_than_the_broker_holds(book):
    factory, pid = book
    fake = FakeAlpaca(fill_price="63000")
    broker = alpaca.AlpacaPaperBroker(client_for(fake), sleep=lambda _: None)
    with factory() as s:
        btc = coin(s)
        execute(s, oms.create_order(s, portfolio_id=pid, security_id=btc.id, side=Side.BUY, quantity=0.05).id, broker, LIMITS)
        # The fee (0.25%) has since been taken in coin: the broker has 0.049875, the ledger still says 0.05.
        fake.positions = [{"symbol": "BTCUSD", "asset_class": "crypto", "qty": "0.049875", "qty_available": "0.049875"}]
        o = oms.create_order(s, portfolio_id=pid, security_id=btc.id, side=Side.SELL, quantity=0.05)
        r = execute(s, o.id, broker, LIMITS)
        sent = [json.loads(q.content) for q in fake.requests if q.method == "POST"][-1]
        assert sent["side"] == "sell" and sent["qty"] == "0.049875"
        assert r.outcome == "executed" and r.quantity == pytest.approx(0.049875) and o.status == OrderStatus.PARTIALLY_FILLED.value

        fake.positions = []
        o2 = oms.create_order(s, portfolio_id=pid, security_id=btc.id, side=Side.SELL, quantity=0.0001)
        assert "holds no BTC" in execute(s, o2.id, broker, LIMITS).reasons[0]


# --------------------------------------------------------------------------- reconciliation


def test_reconciliation_books_small_explainable_differences_and_flags_the_rest(book):
    factory, pid = book
    fake = FakeAlpaca(fill_price="63000")
    client = client_for(fake)
    with factory() as s:
        btc, nvda = coin(s), s.execute(select(Security).where(Security.ticker == "NVDA")).scalar_one()
        for sec, qty, px in ((btc, 0.05, 63_000.0), (nvda, 10, 150.0)):
            s.add(Trade(portfolio_id=pid, security_id=sec.id, side="BUY", quantity=qty, price=px, currency="USD", trade_date=T0.date()))
        s.commit()
        cash = 100_000 - 0.05 * 63_000 - 1_500

        fake.cash = str(cash)
        fake.positions = [{"symbol": "BTCUSD", "asset_class": "crypto", "qty": "0.05"},
                          {"symbol": "NVDA", "asset_class": "us_equity", "qty": "10"}]
        agree = alpaca.reconcile(s, client, pid, apply=True)
        assert agree["clean"] and agree["positions"] == [] and agree["cash"] is None

        # The coin fee has posted (0.25% of 0.05 BTC) and 8 cents of option fees came out of cash.
        fake.positions[0]["qty"] = "0.049875"
        fake.cash = str(cash - 0.08)
        look = alpaca.reconcile(s, client, pid)
        assert look["positions"][0]["action"] == "fee taken in coin" and look["cash"]["action"] == "fees and rounding"
        assert value_portfolio(s, pid).positions.at[btc.id, "quantity"] == 0.05, "looking changes nothing"

        done = alpaca.reconcile(s, client, pid, apply=True)
        assert done["clean"] and done["positions"][0]["action"].startswith("booked") and done["cash"]["action"].startswith("booked")
        v = value_portfolio(s, pid)
        assert v.positions.at[btc.id, "quantity"] == pytest.approx(0.049875) and v.cash == pytest.approx(cash - 0.08)
        fee = s.execute(select(CashFlow).where(CashFlow.kind == "FEE")).scalar_one()
        assert fee.amount == pytest.approx(-0.08)
        sliver = s.execute(select(Trade).where(Trade.security_id == btc.id, Trade.side == "SELL")).scalar_one()
        assert sliver.fees == pytest.approx(0.000125 * 63_000), "the coin fee is recorded in dollars and costs no cash"
        again = alpaca.reconcile(s, client, pid, apply=True)
        assert again["positions"] == [] and again["cash"] is None, "booking twice is impossible: the books now agree"

        # Differences nobody should paper over: shares the ledger has never heard of, and real money missing.
        fake.positions.append({"symbol": "TSLA", "asset_class": "us_equity", "qty": "5"})
        fake.positions[1]["qty"] = "7"
        fake.cash = str(cash - 0.08 - 900)
        bad = alpaca.reconcile(s, client, pid, apply=True)
        assert not bad["clean"]
        assert {i["ticker"]: i["action"] for i in bad["positions"]} == {"NVDA": "unexplained: left alone", "TSLA": "unexplained: left alone"}
        assert bad["cash"]["action"] == "unexplained: left alone"
        assert value_portfolio(s, pid).cash == pytest.approx(cash - 0.08), "nothing was booked for them"


# --------------------------------------------------------------------------- older databases


def test_a_database_from_an_older_version_gains_the_new_columns(tmp_path):
    e = make_engine(f"sqlite:///{tmp_path / 'old.db'}")
    init_db(e)
    with e.begin() as conn:  # put cash_flows back to how it was before `kind` existed
        conn.execute(text("ALTER TABLE cash_flows DROP COLUMN kind"))
        conn.execute(text("INSERT INTO portfolios (name, base_currency, created_at) VALUES ('Old', 'USD', '2026-11-01')"))
        conn.execute(text("INSERT INTO cash_flows (portfolio_id, date, amount) VALUES (1, '2026-11-18', 100000)"))
    assert "kind" not in {c["name"] for c in inspect(e).get_columns("cash_flows")}
    init_db(e)
    init_db(e)  # safe to run on every start
    assert "kind" in {c["name"] for c in inspect(e).get_columns("cash_flows")}
    with e.connect() as conn:
        assert conn.execute(text("SELECT kind, amount FROM cash_flows")).one() == ("EXTERNAL", 100000.0)
    with make_session_factory(e)() as s:
        assert value_portfolio(s, 1).cash == 100_000
