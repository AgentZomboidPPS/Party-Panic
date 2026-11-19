"""What KAIROS weighs besides the crowd: price trend, the market backdrop, and the evidence on trial."""

import math
from datetime import date, timedelta

import pandas as pd
import pytest
from sqlalchemy import select

from spectre.marketdata.prices import upsert_prices
from spectre.models import Price, Security
from spectre.portfolio.positions import value_portfolio
from spectre.signals import evidence as ev
from spectre.signals import intraday
from spectre.signals.models import NewsItem, SignalReading
from spectre.signals.strategy import live_signals, run_once
from tests.test_strategy import LIMITS, T0, _post, book  # noqa: F401  (the fixture)

NAMES = ("SPY", "NVDA", "MSFT", "TSLA", "AMD", "AAPL", "AMZN", "GOOGL", "META", "JPM", "KO", "XOM")
NOW = T0 + timedelta(minutes=20)


def business_days(n: int, end: date) -> list[date]:
    out, d = [], end
    while len(out) < n:
        if d.weekday() < 5:
            out.append(d)
        d -= timedelta(days=1)
    return out[::-1]


def history(s, drifts: dict[str, float], days: int = 300, spy_last_20: list[float] | None = None, today: dict[str, float] | None = None):
    """Give each name `days` of daily closes ending the day before T0, growing by its drift a
    day, and a price on T0's date (the last close, or `today[name]` times it)."""
    dates = business_days(days, T0.date() - timedelta(days=1))
    ids = dict(s.execute(select(Security.ticker, Security.id).where(Security.ticker.in_(drifts))).all())
    rows = []
    for name, drift in drifts.items():
        px = 100.0
        for i, d in enumerate(dates):
            step = drift
            if name == "SPY" and spy_last_20 and i >= days - 20:
                step = spy_last_20[i - (days - 20)]
            px *= 1 + step
            rows.append({"security_id": ids[name], "date": d, "close": px})
        rows.append({"security_id": ids[name], "date": T0.date(), "close": px * (today or {}).get(name, 1.0)})
    upsert_prices(s, rows)
    s.commit()


def crowd(pipe, name: str, bulls: int, bears: int = 0, price: float = 100.0, start: int = 100):
    posts = [_post(f"{name}{start + i}", f"{name}-bull{i}", f"${name} looks strong here, adding more", "Bullish", i % 10, {name: price}, (name,))
             for i in range(bulls)]
    posts += [_post(f"{name}b{start + i}", f"{name}-bear{i}", f"${name} is breaking down, getting out", "Bearish", i % 10, {name: price}, (name,))
              for i in range(bears)]
    pipe.process_posts(posts)


# a market where NVDA has the strongest trend and MSFT the weakest; SPY drifts gently
DRIFTS = {n: 0.0002 * i for i, n in enumerate(("MSFT", "KO", "XOM", "JPM", "TSLA", "META", "GOOGL", "AMZN", "AAPL", "AMD", "NVDA"))} | {"SPY": 0.0004}


# --------------------------------------------------------------------------- the pieces


def test_standing_ranks_names_by_momentum_and_ignores_the_latest_week():
    days = pd.date_range("2025-01-01", periods=300, freq="B")
    closes = pd.DataFrame({name: 100 * (1 + 0.001 * i) ** pd.RangeIndex(300) for i, name in enumerate("ABCDE")}, index=days)
    standing = ev.momentum_standing(closes).iloc[-1]
    assert list(standing.sort_values().index) == list("ABCDE") and standing["E"] == 1.0 and standing["A"] == 0.2
    crashed = closes.copy()
    crashed.iloc[-4:, crashed.columns.get_loc("E")] *= 0.5  # the strongest name halves this week
    assert ev.momentum_standing(crashed).iloc[-1]["E"] == 1.0, "the latest week is left out of the trend"
    young = closes.copy()
    young.iloc[:120, young.columns.get_loc("E")] = float("nan")  # listed for 180 days: no twelve-month look yet
    assert ev.momentum_standing(young).iloc[-1]["E"] == 1.0, "ranked on its six-month momentum alone"
    assert ev.momentum_standing(closes).iloc[100].isna().all(), "nothing is ranked before there is six months of history"


def test_the_trend_only_ever_raises_and_only_near_the_top():
    assert ev.trend_boost(None) == 1.0 and ev.trend_boost(float("nan")) == 1.0
    assert ev.trend_boost(0.0) == 1.0 and ev.trend_boost(0.5) == 1.0 and ev.trend_boost(0.7) == 1.0
    assert ev.trend_boost(0.8) == pytest.approx(1.25) and ev.trend_boost(0.9) == pytest.approx(1.5) and ev.trend_boost(1.0) == pytest.approx(1.5)


def test_events_are_spotted_in_headlines():
    def spot(text):
        return ev.headline_events(text)

    assert spot("Acme beats estimates as cloud revenue jumps") == [("results beat", 1)]
    assert spot("Acme misses Wall Street expectations") == [("results miss", -1)]
    assert spot("Acme raises full-year guidance") == [("guidance raised", 1)] and spot("Acme cuts its outlook") == [("guidance cut", -1)]
    assert spot("Big Bank upgrades Acme to buy") == [("analyst upgrade", 1)]
    assert spot("Broker lowers Acme price target to $90") == [("analyst downgrade", -1)]
    assert spot("Acme announces $2 billion public offering") == [("share offering", -1)]
    assert spot("Regulator opens investigation into Acme") == [("legal or regulatory trouble", -1)]
    assert spot("Acme opens a new office in Austin") == []


def test_news_counts_newer_headlines_more_and_an_event_pulls_the_tone(book):  # noqa: F811
    factory, _, _ = book
    with factory() as s:
        s.add_all([
            NewsItem(id="1", source="t", headline="Acme said something pleasant", tickers=["NVDA"], sentiment=0.4, published_at=NOW - timedelta(hours=1)),
            NewsItem(id="2", source="t", headline="Acme said something unpleasant", tickers=["NVDA"], sentiment=-0.4, published_at=NOW - timedelta(hours=37)),
            NewsItem(id="3", source="t", headline="Broker downgrades Tesla", tickers=["TSLA"], sentiment=0.1, published_at=NOW - timedelta(hours=2)),
            NewsItem(id="4", source="t", headline="Too old to count", tickers=["TSLA"], sentiment=1.0, published_at=NOW - timedelta(hours=60)),
            NewsItem(id="5", source="t", headline="Not published yet as of then", tickers=["TSLA"], sentiment=1.0, published_at=NOW + timedelta(hours=1)),
        ])
        s.commit()
        news = ev.news_evidence(s, NOW)
    # the hour-old headline weighs eight times the 37-hour-old one (three half-lives of twelve hours)
    assert news["NVDA"]["count"] == 2 and news["NVDA"]["tone"] == pytest.approx((0.4 * 8 - 0.4) / 9, abs=0.01)
    assert news["TSLA"] == {"tone": pytest.approx(0.1 - 0.5), "count": 1, "events": ["analyst downgrade"]}


def test_the_backdrop_scales_buying_down_only_when_the_market_is_turbulent(book):  # noqa: F811
    factory, _, _ = book
    with factory() as s:
        assert ev.backdrop(s)["available"] is False and ev.backdrop(s)["scale"] == 1.0, "no S&P 500 history: full size, and it says so"
        history(s, {"SPY": 0.0004})
        calm = ev.backdrop(s)
        assert calm["state"] == "calm" and calm["scale"] == 1.0 and calm["trend_in_play"] and "full size" in calm["note"]
    factory, _, _ = book
    with factory() as s:
        s.execute(Price.__table__.delete())
        history(s, {"SPY": 0.0004}, spy_last_20=[0.012, -0.012] * 10)  # swinging 1.2% a day: about 19% a year
        wild = ev.backdrop(s)
        assert wild["state"] == "turbulent" and wild["volatility"] == pytest.approx(0.012 * math.sqrt(252), rel=0.06)
        assert wild["scale"] == pytest.approx(ev.TARGET_VOL / wild["volatility"]) and 0.5 < wild["scale"] < 1
        assert "of normal size" in wild["note"]
        s.execute(Price.__table__.delete())
        history(s, {"SPY": 0.0004}, spy_last_20=[0.05, -0.05] * 10)
        assert ev.backdrop(s)["scale"] == ev.MIN_SCALE and ev.backdrop(s)["state"] == "very turbulent", "never below half size"


# --------------------------------------------------------------------------- conviction


def test_conviction_raises_a_crowd_read_on_a_strong_trend_and_leaves_the_rest_alone(book):  # noqa: F811
    factory, _, pipe = book
    crowd(pipe, "MSFT", bulls=7)
    crowd(pipe, "BTC.X", bulls=6, price=60_000.0)
    with factory() as s:
        history(s, DRIFTS, today={"NVDA": 1.01})
        read = {g.ticker: g for g in ev.weigh(s, live_signals(s, 60, 5, 4), NOW)}
    nvda, msft, tsla, btc = read["NVDA"], read["MSFT"], read["TSLA"], read["BTC"]
    assert nvda.trend == 1.0 and nvda.conviction == pytest.approx(nvda.score * 1.5), "top of the trend ranking: raised by half"
    assert msft.trend == pytest.approx(1 / 12) and msft.conviction == msft.score, "a weak trend takes nothing away"
    assert tsla.score < 0 and tsla.conviction == tsla.score, "a bearish read is left as it is"
    assert btc.trend is None and btc.tape is None and btc.conviction == btc.score, "coins get no trend evidence"
    assert nvda.tape == pytest.approx(0.01, abs=1e-6) and msft.tape == pytest.approx(0.0, abs=1e-6), "today's move against the typical name"
    assert "strong trend (top 1% of the book" in ev.describe(nvda) and ev.describe(msft) == "" and ev.describe(tsla) == ""
    assert msft.score > nvda.score and nvda.conviction > msft.conviction, "the trend changes which name comes first"


def test_no_raise_while_the_market_itself_is_deep_in_a_fall(book):  # noqa: F811
    factory, _, _ = book
    with factory() as s:
        history(s, DRIFTS, spy_last_20=[-0.008] * 20)  # the S&P 500 has lost 15% in a month
        state = ev.backdrop(s, NOW.date())
        assert state["below_year_high"] < -0.10 and state["trend_in_play"] is False and "is not being counted" in state["note"]
        nvda = next(g for g in ev.weigh(s, live_signals(s, 60, 5, 4), NOW) if g.ticker == "NVDA")
        assert nvda.trend == 1.0 and nvda.conviction == nvda.score


def test_kairos_buys_the_name_with_both_the_crowd_and_the_trend_behind_it(book):  # noqa: F811
    factory, pid, pipe = book
    crowd(pipe, "MSFT", bulls=8, price=100.0)  # a slightly stronger crowd read than NVDA's, on the weakest trend in the book
    with factory() as s:
        history(s, DRIFTS)
        nvda = s.execute(select(Security.id).where(Security.ticker == "NVDA")).scalar_one()
        upsert_prices(s, [{"security_id": nvda, "date": T0.date(), "close": 150.0}])
        s.commit()
        plain = run_once(s, pid, limits=LIMITS, top_n=1, invest=0.2, at=NOW, dry_run=True)
        assert plain.targets == ["MSFT"], "on the crowd alone the louder name wins"
        r = run_once(s, pid, limits=LIMITS, top_n=1, invest=0.2, at=NOW, evidence=True)
        assert r.targets == ["NVDA"]
        (buy,) = [a for a in r.actions if a["side"] == "BUY"]
        assert buy["ticker"] == "NVDA" and buy["outcome"] == "executed" and "strong trend" in buy["why"] and "raises it to" in buy["why"]


def test_a_turbulent_market_shrinks_new_purchases_and_never_forces_a_sale(book):  # noqa: F811
    factory, pid, _ = book
    with factory() as s:
        full = run_once(s, pid, limits=LIMITS, top_n=1, invest=0.2, at=NOW, dry_run=True).actions[0]
        assert full["ticker"] == "NVDA" and full["quantity"] == 13  # 2,000 at 150
        r = run_once(s, pid, limits=LIMITS, top_n=1, invest=0.2, at=NOW, buy_scale=0.6)
        (buy,) = r.actions
        assert buy["quantity"] == 8 and "at 60% of normal size because the market is turbulent" in buy["why"]  # 1,200 at 150
        # Later the market turns wilder still: nothing more is bought, and what is held is kept.
        again = run_once(s, pid, limits=LIMITS, top_n=1, invest=0.2, at=NOW, buy_scale=0.5)
        assert again.actions == [] and value_portfolio(s, pid).positions["quantity"].tolist() == [8.0]


# --------------------------------------------------------------------------- the record and the tests


def test_readings_keep_the_evidence_and_the_kinds_are_compared_on_the_same_prices(book):  # noqa: F811
    factory, _, pipe = book
    crowd(pipe, "MSFT", bulls=7)
    for name in ("AAPL", "AMZN", "GOOGL", "META"):
        crowd(pipe, name, bulls=5, bears=1)
    with factory() as s:
        history(s, DRIFTS)
        s.add(NewsItem(id="n", source="t", headline="Acme raises guidance", tickers=["NVDA"], sentiment=0.2, published_at=NOW - timedelta(hours=1)))
        s.commit()
        for minute in range(0, 180, 10):  # KAIROS decides every ten minutes for three hours
            at = NOW + timedelta(minutes=minute)
            for g in ev.weigh(s, live_signals(s, 60, 5, 4, at=NOW), NOW):
                s.add(SignalReading(at=at, ticker=g.ticker, asset_class=g.asset_class, score=g.score, authors=g.n_authors, posts=g.n_posts,
                                    lookback_minutes=60, conviction=g.conviction, trend=g.trend, tape=g.tape, news=g.news,
                                    news_count=g.news_count))
        s.commit()
        row = s.execute(select(SignalReading).where(SignalReading.ticker == "NVDA").limit(1)).scalar_one()
        assert row.trend == 1.0 and row.conviction == pytest.approx(row.score * 1.5) and row.news == pytest.approx(0.7) and row.news_count == 1

        class Prices:  # every name drifts in proportion to its trend standing: trend "works", in this world
            def stock_bars(self, symbols, start, timeframe="1Day", adjustment="all"):
                rank = {n: i for i, n in enumerate(("MSFT", "KO", "XOM", "JPM", "TSLA", "META", "GOOGL", "AMZN", "AAPL", "AMD", "NVDA"))}
                return {t: [(NOW + timedelta(minutes=5 * k), 100 * (1 + 0.0002 * rank.get(t, 0)) ** k) for k in range(-12, 60)] for t in symbols}

        r = intraday.evidence_check(s, Prices(), days=2, horizon=30, top_n=1, now=NOW + timedelta(hours=4))
    by = {k["key"]: k for k in r["kinds"]}
    assert set(by) == {"crowd", "conviction", "trend", "news", "tape"}
    assert by["trend"]["top_edge"] > 0 and by["trend"]["rank_agreement"] == pytest.approx(1.0)
    assert by["conviction"]["top_edge"] > by["crowd"]["top_edge"], "adding the trend to the crowd did better than the crowd alone"
    assert by["news"]["readings"] > 0 and by["news"]["windows"] > 0 and not by["news"]["clears_the_bar"]
    assert r["bar"] == pytest.approx(intraday.bar_for(5)) and "Too little data to compare them" in r["verdict"]
    # The main check judges what KAIROS bought on: conviction where it was written down.
    with factory() as s:
        assert {t: v for _, t, v, _ in intraday.stored_readings(s, NOW, NOW)}["NVDA"] == pytest.approx(row.conviction)
        assert {t: v for _, t, v, _ in intraday.stored_readings(s, NOW, NOW, column="score")}["NVDA"] == pytest.approx(row.score)


def test_recording_writes_the_evidence_down(book):  # noqa: F811
    factory, _, _ = book
    with factory() as s:
        history(s, DRIFTS)
        assert intraday.record_readings(s, lookback=10_000_000, min_authors=4, at=NOW) == 2  # NVDA and TSLA
        nvda = s.execute(select(SignalReading).where(SignalReading.ticker == "NVDA")).scalar_one()
        assert nvda.conviction is not None and nvda.trend is not None


def test_the_tests_on_history_find_what_was_built_into_it(book):  # noqa: F811
    factory, _, _ = book
    with factory() as s:
        assert ev.trend_check(s)["available"] is False and ev.backdrop_check(s) == {"available": False}, "no history: no test"
        # A world where the trend persists: each name keeps its own drift for 400 days.
        many = [t for (t,) in s.execute(select(Security.ticker).where(Security.asset_class.in_(ev.STOCKS)).order_by(Security.ticker).limit(30))]
        history(s, {n: 0.0001 * i for i, n in enumerate(n for n in many if n != "SPY")} | {"SPY": 0.0004}, days=400,
                spy_last_20=[0.012, -0.012] * 10)
        trend = ev.trend_check(s)
        assert trend["available"] and [f["fifth"] for f in trend["fifths"]] == [1, 2, 3, 4, 5]
        ahead = [f["next_day_against_average"] for f in trend["fifths"]]
        assert ahead == sorted(ahead) and ahead[0] < 0 < ahead[-1], "stronger trend, better next day, as built"
        assert trend["top_fifth_by_market"][0]["days"] > 0
        calm = ev.backdrop_check(s)
        assert calm["available"] and {st["state"] for st in calm["states"]} == {"calm", "turbulent"}
        assert calm["scaled_down_when_turbulent"]["volatility"] < calm["held_throughout"]["volatility"]
        assert calm["average_scale"] < 1


def test_the_api_shows_what_is_weighed(book, monkeypatch):  # noqa: F811
    from fastapi.testclient import TestClient

    from spectre.api.app import create_app
    from spectre.api.routers import signals as router
    from spectre.config import settings

    factory, _, _ = book
    with factory() as s:
        history(s, DRIFTS)
        engine = s.get_bind()
    monkeypatch.setattr(router, "_TESTS", {})
    web = TestClient(create_app(engine=engine))
    live = {r["ticker"]: r for r in web.get("/signals/live").json()}
    assert live["NVDA"]["conviction"] == pytest.approx(live["NVDA"]["score"] * 1.5) and live["NVDA"]["trend"] == 1.0
    assert web.get("/signals/live?evidence=false").json()[0]["conviction"] is None
    r = web.get("/signals/evidence").json()
    assert {k["key"]: k["status"] for k in r["kinds"]} == {"crowd": "in use", "trend": "in use", "backdrop": "in use",
                                                         "news": "on trial", "tape": "on trial"}
    assert r["backdrop"]["state"] == "calm" and "trend" in r["tests"] and r["settings"]["trend_strength"] == 0.5
    monkeypatch.setattr(settings, "kairos_evidence", False)
    assert {k["key"]: k["status"] for k in web.get("/signals/evidence").json()["kinds"]}["trend"] == "switched off"
