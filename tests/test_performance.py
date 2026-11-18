"""The track record: what the portfolio was worth over time, against the index, and where the
profit and loss came from."""

from datetime import date, datetime, timedelta

import pytest

from spectre.db import init_db, make_engine, make_session_factory
from spectre.execution.brokers import PaperBroker
from spectre.execution.guard import TradingLimits, execute
from spectre.marketdata.prices import upsert_prices
from spectre.models import CashFlow, NavSnapshot, Portfolio, Security, Side, Trade
from spectre.portfolio import performance as perf
from spectre.portfolio.positions import value_portfolio
from spectre.signals.models import PriceTick
from spectre.trading import oms

DAY = date(2026, 11, 18)
LIMITS = TradingLimits(max_order_notional=1e6, max_daily_notional=1e7, max_orders_per_day=500, max_position_weight=1.0)


@pytest.fixture
def acct():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        pf = Portfolio(name="Record", base_currency="USD")
        secs = {t: Security(ticker=t, name=t, asset_class=k, currency="USD", multiplier=m)
                for t, k, m in (("AAA", "Equity", 1.0), ("SPY", "Fund", 1.0), ("BTC", "Crypto", 1.0),
                                ("AAA261218C00100000", "Option", 100.0))}
        s.add_all([pf, *secs.values()])
        s.flush()
        s.add(CashFlow(portfolio_id=pf.id, date=DAY, amount=10_000))
        s.commit()

        def price(ticker, close):
            upsert_prices(s, [{"security_id": secs[ticker].id, "date": DAY, "close": close}])
            s.commit()

        def trade(ticker, side, qty):
            o = oms.create_order(s, portfolio_id=pf.id, security_id=secs[ticker].id, side=Side(side), quantity=qty)
            assert execute(s, o.id, PaperBroker(), LIMITS).outcome == "executed"

        for t, px in (("AAA", 100.0), ("SPY", 700.0), ("BTC", 60_000.0), ("AAA261218C00100000", 5.0)):
            price(t, px)
        yield s, pf.id, secs, price, trade


def test_profit_and_loss_by_sleeve_adds_up_to_the_change_in_value(acct):
    s, pid, secs, price, trade = acct
    trade("AAA", "BUY", 20)  # 2,000
    trade("AAA261218C00100000", "BUY", 2)  # 1,000 of premium
    trade("BTC", "BUY", 0.01)  # 600
    price("AAA", 110.0)
    trade("AAA", "SELL", 5)  # banks 5 x 10
    price("AAA", 104.0)  # the other 15 are up 4 each
    price("AAA261218C00100000", 3.5)  # the calls are down 1.50 x 200
    price("BTC", 63_000.0)
    # A coin fee taken in kind (a sliver, not a sale) and a broker fee outside any trade.
    s.add(Trade(portfolio_id=pid, security_id=secs["BTC"].id, side="SELL", quantity=0.0001, price=63_000.0, currency="USD",
                fees=6.30, trade_date=DAY))
    s.add(CashFlow(portfolio_id=pid, date=DAY, amount=-0.50, kind="FEE", memo="regulatory"))
    s.commit()

    r = perf.performance(s, pid)
    by = {x["sleeve"]: x for x in r["sleeves"]}
    stocks, options, coins = by["Stocks and funds"], by["Options"], by["Coins"]
    assert stocks["realised"] == pytest.approx(50) and stocks["unrealised"] == pytest.approx(60) and stocks["closed_trades"] == 1
    assert stocks["winners"] == 1 and stocks["market_value"] == pytest.approx(15 * 104)
    assert options["unrealised"] == pytest.approx(-300) and options["realised"] == 0 and options["market_value"] == pytest.approx(700)
    # 0.0099 BTC left, bought at 60,000 and now 63,000; the sliver shows as a 6.30 fee, not as a sale.
    assert coins["unrealised"] == pytest.approx(0.0099 * 3_000) and coins["fees"] == pytest.approx(6.30)
    assert coins["realised"] == pytest.approx(0.0001 * 3_000) and coins["closed_trades"] == 0
    assert r["account_fees_and_adjustments"] == pytest.approx(-0.50)

    v = value_portfolio(s, pid)
    assert r["put_in"] == 10_000 and r["pnl"] == pytest.approx(v.total_value - 10_000)
    assert sum(x["total"] for x in r["sleeves"]) + r["account_fees_and_adjustments"] == pytest.approx(r["pnl"]), \
        "the parts add up exactly to the whole"
    assert r["return"] == pytest.approx(r["pnl"] / 10_000) and r["closed_trades"] == 1 and r["winners"] == 1


def test_snapshots_build_a_record_against_the_index(acct):
    s, pid, secs, price, trade = acct
    trade("AAA", "BUY", 50)  # 5,000 of stock; the first fill marks the start of the record
    start = perf._inception(s, pid)
    s.add(PriceTick(security_id=secs["SPY"].id, ticker="SPY", observed_at=start - timedelta(minutes=1), price=700.0, source="t"))
    s.commit()

    t0 = start + timedelta(minutes=10)
    assert perf.record_snapshot(s, pid, at=t0).nav == pytest.approx(10_000)
    assert perf.record_snapshot(s, pid, at=t0 + timedelta(minutes=1)) is None, "not twice within a few minutes"
    price("AAA", 104.0)
    price("SPY", 707.0)
    second = perf.record_snapshot(s, pid, at=t0 + timedelta(minutes=10))
    assert second.nav == pytest.approx(10_200) and second.stocks == pytest.approx(5_200) and second.cash == pytest.approx(5_000)
    assert second.benchmark == 707.0 and second.options == 0 and second.coins == 0
    price("AAA", 98.0)
    price("SPY", 693.0)
    perf.record_snapshot(s, pid, at=t0 + timedelta(minutes=20))

    r = perf.performance(s, pid)
    series = r["series"]
    assert [p["nav"] for p in series] == pytest.approx([10_000, 10_000, 10_200, 9_900]), "it starts from the money put in"
    assert [round(p["return"], 4) for p in series] == [0.0, 0.0, 0.02, -0.01]
    assert [round(p["benchmark_return"], 4) for p in series] == [0.0, 0.0, 0.01, -0.01], "the index over the same moments"
    assert r["return"] == pytest.approx(-0.01) and r["benchmark"]["return"] == pytest.approx(-0.01) and r["excess_return"] == pytest.approx(0)
    assert r["max_drawdown"] == pytest.approx(9_900 / 10_200 - 1), "from the 10,200 high to 9,900"
    assert r["snapshots"] == 3 and r["since"] == start.isoformat(timespec="seconds")


def test_a_long_record_is_thinned_but_keeps_its_newest_point(acct):
    s, pid, _, _, trade = acct
    trade("AAA", "BUY", 1)
    base = datetime(2026, 11, 19, 0, 0)
    s.add_all([NavSnapshot(portfolio_id=pid, at=base + timedelta(minutes=10 * i), nav=10_000 + i, cash=0.0) for i in range(1_000)])
    s.commit()
    series = perf.performance(s, pid, max_points=100)["series"]
    assert len(series) == 100 and series[-1]["nav"] == 10_999


def test_an_untouched_portfolio_has_a_record_of_nothing(acct):
    s, pid, *_ = acct
    r = perf.performance(s, pid)
    assert r["pnl"] == 0 and r["series"] == [] and r["sleeves"] == [] and r["since"] is None and r["max_drawdown"] == 0
