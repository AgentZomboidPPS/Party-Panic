"""Measuring the crowd read against what prices did next."""

from datetime import datetime, timedelta

import pytest

from spectre.db import init_db, make_engine, make_session_factory
from spectre.models import Security
from spectre.signals import intraday
from spectre.signals.models import SearchTrend, SocialPost
from spectre.signals.strategy import live_signals

T0 = datetime(2026, 11, 18, 15, 0)
LIKED, DISLIKED = ("AAA", "BBB", "CCC"), ("DDD", "EEE", "FFF")


@pytest.fixture
def world():
    """Six stocks. Through three hours the crowd likes three and dislikes three; `bars(drift)` makes
    the liked ones drift by `drift` per five minutes and the disliked ones the other way."""
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        s.add_all([Security(ticker=t, name=t, asset_class="Equity", currency="USD") for t in LIKED + DISLIKED])
        n = 0
        for minute in range(0, 180, 5):
            for ticker in LIKED + DISLIKED:
                for author in range(5):
                    # Four of five authors lean the way the name is "meant" to; one always disagrees.
                    lean = (0.7 if ticker in LIKED else -0.7) * (1 if author < 4 else -1)
                    when = T0 + timedelta(minutes=minute, seconds=author)
                    s.add(SocialPost(source="t", external_id=str(n), author_hash=f"{ticker}-{author}", author_quality=1.0,
                                     dedup_hash=str(n), text="x", posted_at=when, ingested_at=when, sentiment=lean,
                                     tickers=[ticker], fear=False, screened_out=False))
                    n += 1
        s.commit()

        def bars(drift):
            out = {}
            for i, ticker in enumerate(LIKED + DISLIKED):
                step = drift * (1 if ticker in LIKED else -1) * (1 + i % 3 * 0.1)  # not all the same, so ranks are defined
                out[ticker] = [(T0 + timedelta(minutes=5 * k), 100 * (1 + step) ** k) for k in range(-2, 60)]
            return out

        yield s, bars


def run(s, bars, **kw):
    df = intraday.collect(s, intraday.PricePath(bars), T0, T0 + timedelta(hours=3), step=10, lookback=30, min_authors=4,
                          horizon=30, **kw)
    return df, intraday.summarise(df, horizon=30, lookback=30)


def test_a_crowd_that_is_right_shows_up_as_an_edge(world):
    s, bars = world
    df, r = run(s, bars(+0.001))
    assert r["samples"] == len(df) == 6 * r["moments"] and r["names"] == 6 and r["moments"] == 13
    buy, _, avoid = r["zones"]
    assert buy["samples"] == 3 * r["moments"] and buy["mean_relative_return"] > 0 and buy["share_beating_the_rest"] == 1.0
    assert avoid["mean_relative_return"] < 0 and avoid["share_beating_the_rest"] == 0.0
    assert r["rank_agreement"]["mean"] > 0.5 and r["rank_agreement"]["share_positive"] == 1.0
    # The three liked names are what would be held; their edge over all six is the buy zone's relative return.
    assert r["held"]["mean_edge"] == pytest.approx(buy["mean_relative_return"]) and r["held"]["mean_edge"] > 0
    # Thirteen moments ten minutes apart are five separate half-hour windows, not thirteen observations.
    assert r["windows"] == 5 and "Too little data" in r["verdict"]


def test_a_crowd_that_is_wrong_shows_up_too(world):
    s, bars = world
    _, r = run(s, bars(-0.001))
    assert r["zones"][0]["mean_relative_return"] < 0 and r["rank_agreement"]["mean"] < -0.5 and r["held"]["mean_edge"] < 0


def test_enough_windows_earn_a_verdict(world, monkeypatch):
    s, bars = world
    monkeypatch.setattr(intraday, "ENOUGH_WINDOWS", 4)
    assert "did better than the rest" in run(s, bars(+0.001))[1]["verdict"]
    assert "pointing the wrong way" in run(s, bars(-0.001))[1]["verdict"]
    flat = {t: [(at, 100.0) for at, _ in series] for t, series in bars(0.001).items()}
    assert "not shown an edge" in run(s, flat)[1]["verdict"]


def test_prices_are_only_used_when_fresh_and_never_from_the_future():
    path = intraday.PricePath({"AAA": [(T0, 100.0), (T0 + timedelta(minutes=5), 101.0)]})
    assert path.at("AAA", T0 + timedelta(minutes=4)) is None, "the first bar has not finished yet"
    assert path.at("AAA", T0 + timedelta(minutes=5)) == 100.0 and path.at("AAA", T0 + timedelta(minutes=12)) == 101.0
    assert path.at("AAA", T0 + timedelta(minutes=40)) is None, "half an hour without a bar: the market is shut"
    assert path.at("ZZZ", T0) is None


def test_nothing_to_measure_says_so(world):
    s, _ = world
    df, r = run(s, {})
    assert df.empty and r["samples"] == 0 and "No usable data" in r["verdict"]


def test_a_past_read_does_not_see_searches_that_trended_later(world):
    s, _ = world
    at = T0 + timedelta(minutes=60)
    s.add(SearchTrend(source="t", geo="US", term="aaa stock", tickers=["AAA"], started_at=at + timedelta(minutes=30),
                      first_seen=at + timedelta(minutes=30), last_seen=at + timedelta(minutes=90)))
    s.commit()
    then = {x.ticker: x for x in live_signals(s, 30, min_authors=4, at=at)}
    later = {x.ticker: x for x in live_signals(s, 30, min_authors=4, at=at + timedelta(minutes=60))}
    assert not then["AAA"].trending and later["AAA"].trending
    assert later["AAA"].score == pytest.approx(then["AAA"].score * 1.25)


def test_check_fetches_five_minute_prices_for_the_names_in_the_book(world):
    s, bars = world

    class Prices:
        def stock_bars(self, symbols, start, timeframe="1Day", adjustment="all"):
            self.asked = (sorted(symbols), start, timeframe, adjustment)
            return {t: b for t, b in bars(0.001).items() if t in symbols}

    client = Prices()
    r = intraday.check(s, client, days=2, horizon=30, lookback=30, min_authors=4, now=T0 + timedelta(hours=3))
    assert client.asked == (sorted(LIKED + DISLIKED), T0, "5Min", "raw")
    assert r["moments"] == 13 and r["held"]["mean_edge"] > 0


def test_the_api_serves_the_check_and_says_so_when_prices_are_unavailable(world, monkeypatch):
    from fastapi.testclient import TestClient

    from spectre.api.app import create_app
    from spectre.api.routers import signals as router
    from spectre.execution import alpaca

    s, bars = world

    class Prices:
        def stock_bars(self, symbols, start, timeframe="1Day", adjustment="all"):
            return {t: b for t, b in bars(0.001).items() if t in symbols}

    class Down:
        def stock_bars(self, *a, **k):
            raise alpaca.AlpacaError(403, "no market data")

    web = TestClient(create_app(engine=s.get_bind()))
    monkeypatch.setattr(router, "_CHECKS", {})
    monkeypatch.setattr(alpaca, "AlpacaClient", Down)
    r = web.get("/signals/check?days=100000&horizon=30&lookback=30&min_authors=4").json()
    assert r["samples"] == 0 and "not available" in r["verdict"] and "no market data" in r["verdict"]
    monkeypatch.setattr(alpaca, "AlpacaClient", Prices)
    r = web.get("/signals/check?days=100000&horizon=30&lookback=30&min_authors=4").json()
    assert r["samples"] > 0 and "verdict" in r and r["held"]["top_n"] == 5
    monkeypatch.setattr(alpaca, "AlpacaClient", Down)
    assert web.get("/signals/check?days=100000&horizon=30&lookback=30&min_authors=4").json() == r, "a recent answer is reused rather than asked for again"
