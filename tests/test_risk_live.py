"""Risk on real holdings: price history from Alpaca, options counted through their delta, and
coins (which trade at weekends) sampled alongside stocks (which do not)."""

from datetime import date, datetime, timedelta

import numpy as np
import pandas as pd
import pytest
from sqlalchemy import select

from spectre.db import init_db, make_engine, make_session_factory
from spectre.execution import alpaca
from spectre.execution.models import OptionMark
from spectre.marketdata.prices import price_matrix
from spectre.marketdata.universe import seed_universe
from spectre.models import CashFlow, Portfolio, Price, Security, Trade
from spectre.portfolio.positions import value_portfolio
from spectre.risk.options import option_exposures
from spectre.risk.report import asset_returns, stress_suite, var_suite
from spectre.risk.stress import Scenario
from spectre.signals.sources.base import utcnow
from tests.test_alpaca import FakeAlpaca, client_for

END = date(2026, 11, 18)  # a Wednesday


def business_days(n: int, end: date = END) -> list[date]:
    out, d = [], end
    while len(out) < n:
        if d.weekday() < 5:
            out.append(d)
        d -= timedelta(days=1)
    return out[::-1]


@pytest.fixture
def book():
    """100 shares of a stock at 100, two calls and one put on it, and half a coin."""
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        pf = Portfolio(name="Risk", base_currency="USD")
        stock = Security(ticker="AAA", name="Alpha", asset_class="Equity", currency="USD", sector="Technology", country="US")
        call = Security(ticker="AAA261218C00105000", name="AAA call", asset_class="Option", currency="USD", sector="Technology",
                        country="US", multiplier=100.0)
        put = Security(ticker="AAA261218P00095000", name="AAA put", asset_class="Option", currency="USD", sector="Technology",
                       country="US", multiplier=100.0)
        coin = Security(ticker="BTC", name="Bitcoin", asset_class="Crypto", currency="USD", sector="Crypto", country="Global")
        s.add_all([pf, stock, call, put, coin])
        s.flush()
        rng = np.random.default_rng(7)
        days = business_days(61)
        level = 100.0 / np.prod(1 + (moves := rng.normal(0, 0.02, 60)))  # so the last close is exactly 100
        closes = [level, *(level * np.cumprod(1 + moves))]
        s.add_all([Price(security_id=stock.id, date=d, close=float(c)) for d, c in zip(days, closes, strict=True)])
        d, px = days[0], 60_000.0  # the coin has a price every calendar day, weekends included
        while d <= END:
            s.add(Price(security_id=coin.id, date=d, close=px))
            px *= 1.01
            d += timedelta(days=1)
        s.add_all([Price(security_id=call.id, date=END, close=5.0), Price(security_id=put.id, date=END, close=4.0)])
        s.add(OptionMark(security_id=call.id, underlying="AAA", option_type="call", strike=105, expiration=date(2026, 12, 18),
                         as_of=datetime(2026, 11, 18, 15), mark=5.0, delta=0.50, underlying_price=100.0))
        s.add(OptionMark(security_id=put.id, underlying="AAA", option_type="put", strike=95, expiration=date(2026, 12, 18),
                         as_of=datetime(2026, 11, 18, 15), mark=4.0, delta=-0.40, underlying_price=None))  # spot looked up instead
        s.add(CashFlow(portfolio_id=pf.id, date=days[0], amount=100_000))
        for sec, qty, price in ((stock, 100, 100.0), (call, 2, 5.0), (put, 1, 4.0), (coin, 0.5, px / 1.01)):
            s.add(Trade(portfolio_id=pf.id, security_id=sec.id, side="BUY", quantity=qty, price=price, currency="USD", trade_date=END))
        s.commit()
        yield s, pf.id, {"stock": stock, "call": call, "put": put, "coin": coin}


def test_an_option_is_geared_to_its_underlying_by_delta(book):
    s, pid, sec = book
    v = value_portfolio(s, pid, END)
    exp = option_exposures(s, v)
    assert exp.at[sec["call"].id, "leverage"] == pytest.approx(0.50 * 100 / 5.0)  # +10: one percent in the stock is ten in the call
    assert exp.at[sec["put"].id, "leverage"] == pytest.approx(-0.40 * 100 / 4.0), "a put moves the other way; spot came from the price table"
    assert exp.at[sec["call"].id, "underlying_class"] == "Equity"

    rets = asset_returns(s, v)
    assert set(rets.columns) == {x.id for x in sec.values()} and len(rets) == 60
    stock, call, put = rets[sec["stock"].id], rets[sec["call"].id], rets[sec["put"].id]
    pd.testing.assert_series_equal(call, (stock * 10).clip(lower=-1.0), check_names=False)
    pd.testing.assert_series_equal(put, (stock * -10).clip(lower=-1.0), check_names=False)
    assert call.min() >= -1.0, "a bought option cannot lose more than it cost"


def test_value_at_risk_counts_the_options_and_says_how(book):
    s, pid, sec = book
    v = value_portfolio(s, pid, END)
    out = var_suite(s, v)
    assert out["observations"] == 60 and out["methods"]["parametric"]["var"] > 0
    assert {o["ticker"]: round(o["leverage"]) for o in out["options_by_delta"]} == {"AAA261218C00105000": 10, "AAA261218P00095000": -10}
    assert out["not_modelled"] == []
    by = {c["ticker"]: c["component_var"] for c in out["component_var"]}
    # 1,000 of calls at 10x is as much stock exposure as the 10,000 of shares, so it carries as much of the risk...
    assert by["AAA261218C00105000"] == pytest.approx(by["AAA"], rel=0.02)
    assert by["AAA261218P00095000"] < 0, "...and the put is a hedge: it takes risk away"

    # A contract nobody has a delta for is named, not quietly treated as safe.
    s.get(OptionMark, sec["put"].id).delta = None
    s.commit()
    out = var_suite(s, value_portfolio(s, pid, END))
    assert out["not_modelled"] == ["AAA261218P00095000"] and len(out["options_by_delta"]) == 1


def test_stress_scenarios_gear_options_and_stop_at_the_premium(book):
    s, pid, sec = book
    v = value_portfolio(s, pid, END)

    def run(shock):
        (r,) = stress_suite(s, v, [Scenario("x", "", {"asset_class": {"Equity": shock}})])
        return {b["ticker"]: b["pnl"] for b in r["by_security"]}

    down5 = run(-0.05)
    assert down5["AAA"] == pytest.approx(-500) and down5["AAA261218C00105000"] == pytest.approx(-500), "calls: 1,000 x (10 x -5%)"
    assert down5["AAA261218P00095000"] == pytest.approx(+200), "the put gains: 400 x (-10 x -5%)"
    assert down5["BTC"] == 0, "an equity shock does not touch the coin"
    down30 = run(-0.30)
    assert down30["AAA261218C00105000"] == pytest.approx(-1_000), "the loss stops at what the calls cost"
    assert down30["AAA261218P00095000"] == pytest.approx(+1_200)
    assert run(+0.20)["AAA261218P00095000"] == pytest.approx(-400), "and a rally can only cost the put its premium"


def test_coins_and_stocks_are_sampled_on_the_same_days(book):
    s, _, sec = book
    both = price_matrix(s, [sec["stock"].id, sec["coin"].id], END, 500)
    assert len(both) == 61 and all(d.weekday() < 5 for d in both.index), "weekend rows are dropped when a stock is in the mix"
    monday = both.index[[d.weekday() == 0 for d in both.index]][1]
    friday = both.index[both.index.get_loc(monday) - 1]
    assert both.at[monday, sec["coin"].id] / both.at[friday, sec["coin"].id] == pytest.approx(1.01**3), \
        "the coin's weekend move lands in Monday's return"
    alone = price_matrix(s, [sec["coin"].id], END, 500)
    assert len(alone) > 61 and any(d.weekday() >= 5 for d in alone.index), "a coin on its own keeps every day"


# --------------------------------------------------------------------------- history from Alpaca


def test_daily_history_is_downloaded_page_by_page():
    fake = FakeAlpaca()
    client = client_for(fake)
    bars = client.daily_bars(["NVDA", "SPY"], date(2026, 11, 1))
    assert bars["NVDA"][:3] == [(date(2026, 11, 16), 148.0), (date(2026, 11, 17), 150.0), (date(2026, 11, 18), 151.0)]
    assert bars["NVDA"][3] == (date(2026, 7, 3), 0.0), "summer bars start an hour earlier in UTC but are the same calendar day"
    assert bars["SPY"] == [(date(2026, 11, 16), 725.0), (date(2026, 11, 17), 729.0)]
    first, second = (q.url.params for q in fake.requests)
    assert first["timeframe"] == "1Day" and first["adjustment"] == "all" and first["feed"] == "sip" and first["start"] == "2026-11-01"
    assert second["page_token"] == "more"
    assert client.crypto_daily_bars(["BTC"], date(2026, 11, 1)) == {"BTC": [(date(2026, 11, 14), 64113.15), (date(2026, 11, 15), 65320.5)]}
    assert client.crypto_daily_bars([], date(2026, 11, 1)) == {}


def test_backfill_stores_history_but_never_overwrites_today_or_made_up_tickers():
    e = make_engine("sqlite://")
    init_db(e)
    today = utcnow().date()
    with make_session_factory(e)() as s:
        seed_universe(s)
        fake_co = Security(ticker="SPY2", name="Made-up fund", asset_class="Fund", currency="USD")
        s.add(fake_co)
        s.flush()
        nvda = s.execute(select(Security).where(Security.ticker == "NVDA")).scalar_one()
        s.add(Price(security_id=nvda.id, date=today, close=152.25))  # the live price
        s.commit()

        class Today(FakeAlpaca):
            def __call__(self, request):
                r = super().__call__(request)
                if request.url.path == "/v2/stocks/bars":  # make the last NVDA bar "today"
                    body = r.json()
                    for bar in body["bars"].get("NVDA", []):
                        if bar["t"].startswith("2026-11-18"):
                            bar["t"] = f"{today.isoformat()}T05:00:00Z"
                    return type(r)(200, json=body)
                return r

        fake = Today()
        out = alpaca.backfill_prices(s, client_for(fake), days=30, tickers=None)
        asked = [q.url.params["symbols"] for q in fake.requests if q.url.path == "/v2/stocks/bars"]
        assert all("SPY2" not in a for a in asked), "only the curated real-world universe is asked for"
        assert out["securities"] == 3 and "AAPL" in out["missing"] and out["from"] == (today - timedelta(days=30)).isoformat()
        prices = dict(s.execute(select(Price.date, Price.close).where(Price.security_id == nvda.id)).all())
        assert prices[date(2026, 11, 16)] == 148.0 and prices[date(2026, 11, 17)] == 150.0
        assert prices[today] == 152.25, "today's live price is fresher than a daily bar and is left alone"
        assert date(2026, 7, 3) not in prices, "a zero is not a price"
        btc = s.execute(select(Security).where(Security.ticker == "BTC")).scalar_one()
        assert s.execute(select(Price.close).where(Price.security_id == btc.id, Price.date == date(2026, 11, 15))).scalar_one() == 65320.5
