from __future__ import annotations

import math
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd
from fastapi import APIRouter
from fastapi.responses import FileResponse
from sqlalchemy import select

from spectre.api.deps import DB
from spectre.signals import aggregate, signals
from spectre.signals.models import SentimentBar, Topic

router = APIRouter(prefix="/signals", tags=["signals"])
DASHBOARD = Path(__file__).resolve().parents[2] / "dashboard" / "index.html"


def _clean(obj):
    """JSON-safe: NaN -> None, Timestamps -> iso."""
    if isinstance(obj, float):
        return None if math.isnan(obj) or math.isinf(obj) else obj
    if isinstance(obj, dict):
        return {k: _clean(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_clean(v) for v in obj]
    if isinstance(obj, (pd.Timestamp, datetime)):
        return obj.isoformat()
    return obj


def _records(df: pd.DataFrame) -> list[dict]:
    return _clean(df.to_dict(orient="records")) if not df.empty else []


def _topic(t: Topic) -> dict:
    return {
        "id": t.id, "window_start": t.window_start.isoformat(), "window_end": t.window_end.isoformat(), "label": t.label,
        "keywords": t.keywords, "volume": t.volume, "unique_authors": t.unique_authors, "sentiment_mean": t.sentiment_mean,
        "fear_share": t.fear_share, "velocity": t.velocity, "tickers": t.tickers, "sample": t.sample,
    }


@router.get("/status")
def status(db: DB) -> dict:
    return aggregate.feed_status(db)


@router.get("/bubbles")
def bubbles(db: DB, at: datetime | None = None) -> dict:
    topics = aggregate.latest_topics(db, at)
    return {
        "window_start": topics[0].window_start.isoformat() if topics else None,
        "window_end": topics[0].window_end.isoformat() if topics else None,
        "topics": [_topic(t) for t in topics],
    }


@router.get("/bubbles/history")
def bubbles_history(db: DB, hours: float = 24, limit: int = 500) -> list[dict]:
    end = db.execute(select(Topic.window_end).order_by(Topic.window_end.desc()).limit(1)).scalar_one_or_none()
    if end is None:
        return []
    rows = db.execute(
        select(Topic).where(Topic.window_end > end - timedelta(hours=hours)).order_by(Topic.window_end, Topic.volume.desc()).limit(limit)
    ).scalars()
    return [_topic(t) for t in rows]


@router.get("/sentiment")
def sentiment_latest(db: DB, at: datetime | None = None) -> list[dict]:
    return _records(aggregate.latest_sentiment(db, at))


@router.get("/sentiment/{ticker}")
def sentiment_history(ticker: str, db: DB, limit: int = 200) -> list[dict]:
    rows = db.execute(
        select(SentimentBar).where(SentimentBar.ticker == ticker.upper()).order_by(SentimentBar.window_start.desc()).limit(limit)
    ).scalars()
    out = [
        {"window_start": b.window_start.isoformat(), "window_end": b.window_end.isoformat(), "n_posts": b.n_posts, "n_authors": b.n_authors,
         "sentiment_mean": b.sentiment_mean, "bull_share": b.bull_share, "bear_share": b.bear_share,
         "attention_z": b.attention_z, "sentiment_z": b.sentiment_z}
        for b in rows
    ]
    return _clean(list(reversed(out)))


@router.get("/fear")
def fear(db: DB, hours: float = 24 * 30, bucket_minutes: int = 1440) -> dict:
    last = aggregate.feed_status(db)["last_post_at"]
    if last is None:
        return {"latest": None, "series": []}
    end = datetime.fromisoformat(last) + timedelta(seconds=1)
    s = aggregate.fear_index(db, end - timedelta(hours=hours), end, bucket_minutes)
    return {"latest": float(s.iloc[-1]) if len(s) else None, "mean": float(s.mean()) if len(s) else None,
            "series": [{"t": t.isoformat(), "fear": float(v)} for t, v in s.items()]}


@router.get("/markets")
def markets(db: DB, limit: int = 200, min_prob: float = 0.0, max_prob: float = 1.0, source: str | None = None,
            category: str | None = None) -> list[dict]:
    """Latest prediction-market snapshots, most-traded first. Use min_prob/max_prob (for
    example 0.05 and 0.95) to keep only contested markets."""
    df = aggregate.latest_markets(db, min_prob, max_prob)
    if not df.empty and source:
        df = df[df["source"] == source]
    if not df.empty and category:
        df = df[df["category"] == category]
    return _records(df.head(limit))


@router.get("/trends")
def trends(db: DB, hours: float = 24, limit: int = 30) -> list[dict]:
    """Trending search terms (Google Trends), with any securities they point at."""
    return aggregate.latest_trends(db, hours, limit)


@router.get("/live")
def live(db: DB, lookback_minutes: int = 60, min_posts: int = 5, min_authors: int = 4, evidence: bool = True) -> list[dict]:
    """What KAIROS trades on: the crowd's stance on each security over the last stretch of data
    and, with `evidence`, the rest of what it weighs (trend, news, today's move) and the
    conviction that comes out. Strongest first."""
    from spectre.signals.evidence import weigh
    from spectre.signals.strategy import live_signals

    signals = live_signals(db, lookback_minutes, min_posts, min_authors)
    return _clean([s.to_dict() for s in (weigh(db, signals) if evidence else signals)])


_TESTS: dict[str, tuple[float, dict]] = {}  # database -> (when computed, the tests on history)


@router.get("/evidence")
def evidence_summary(db: DB) -> dict:
    """What KAIROS weighs besides the crowd, which of it is in use and which on trial, the state
    of the market backdrop now, and the tests on price history behind the parts in use (those
    are recomputed at most once an hour)."""
    import time

    from spectre.config import settings
    from spectre.signals import evidence as ev

    key = str(db.get_bind().url)
    cached = _TESTS.get(key)
    if not cached or time.monotonic() - cached[0] > 3600:
        cached = (time.monotonic(), _clean({"trend": ev.trend_check(db), "backdrop": ev.backdrop_check(db),
                                            "volume": ev.volume_check(db)}))
        _TESTS[key] = cached
    switched_on = {"crowd": True, "trend": settings.kairos_evidence, "backdrop": settings.kairos_backdrop}
    kinds = [{**k, "status": k["status"] if switched_on.get(k["key"], True) else "switched off"} for k in ev.KINDS]
    return {"kinds": kinds, "backdrop": _clean(ev.backdrop(db)), "tests": cached[1],
            "settings": {"trend_strength": ev.TREND_STRENGTH, "target_volatility": ev.TARGET_VOL, "smallest_scale": ev.MIN_SCALE}}


@router.get("/evidence/live")
def evidence_live(db: DB, days: float = 30.0, horizon: int = 60) -> dict:
    """What each kind of evidence has been worth so far on KAIROS's own recorded readings."""
    from spectre.execution.alpaca import AlpacaClient
    from spectre.signals.intraday import evidence_check

    r = _measured(db, ("evidence", days, horizon), lambda: evidence_check(db, AlpacaClient(), days=days, horizon=horizon))
    return r if "kinds" in r else {**r, "kinds": []}


@router.get("/calibration")
def calibration(db: DB, threshold: float = 0.05) -> dict:
    """How well the sentiment model agrees with labels users put on their own posts."""
    return _clean(aggregate.sentiment_calibration(db, threshold))


@router.get("/backtest")
def backtest(db: DB, start: date | None = None, end: date | None = None, horizon: int = 1, signal: str = "score",
             quantile: float = 0.3, cost_bps: float = 5.0) -> dict:
    """`cost_bps` is the one-way trading cost; headline results are after costs, `gross_` before."""
    end = end or date.today()
    start = start or end - timedelta(days=365)
    return _clean(signals.evaluate(db, start, end, horizon, signal, quantile, cost_bps))


@router.post("/paper-trade/{portfolio_id}")
def paper_trade(portfolio_id: int, db: DB, top_n: int = 5, sleeve: float = 0.10, min_score: float = 0.5, fill: bool = False) -> dict:
    orders = signals.strategy_orders(db, portfolio_id, top_n=top_n, sleeve=sleeve, min_score=min_score)
    filled = signals.fill_approved_at_market(db, orders) if fill else 0
    return {
        "orders": [{"id": o.id, "security_id": o.security_id, "side": o.side, "quantity": o.quantity, "status": o.status,
                    "reject_reason": o.reject_reason} for o in orders],
        "filled": filled,
    }


@router.get("/news")
def news(db: DB, limit: int = 25, ticker: str | None = None, portfolio_id: int | None = None) -> list[dict]:
    """The latest company headlines; with `portfolio_id`, those about its holdings come first."""
    from spectre.portfolio.positions import value_portfolio
    from spectre.signals.news import recent_news

    held: set[str] = set()
    if portfolio_id is not None:
        for t in value_portfolio(db, portfolio_id).positions["ticker"]:
            held.add(str(t))
            if len(str(t)) > 15:  # an option contract: news about its underlying is news about it
                held.add("".join(ch for ch in str(t)[:6] if ch.isalpha()))
    return recent_news(db, limit, ticker, held)


_CHECKS: dict[tuple, tuple[float, dict]] = {}  # (database, question) -> (when computed, result)


def _measured(db, key: tuple, compute) -> dict:
    """The signal check, recomputed at most every ten minutes per question."""
    import time

    from spectre.execution.alpaca import AlpacaError

    key = (str(db.get_bind().url), *key)
    cached = _CHECKS.get(key)
    if cached and time.monotonic() - cached[0] < 600:
        return cached[1]
    try:
        result = _clean(compute())
    except AlpacaError as exc:
        return {"samples": 0, "moments": 0, "windows": 0, "horizons": [],
                "verdict": f"Prices are not available to measure against ({exc})."}
    _CHECKS[key] = (time.monotonic(), result)
    return result


@router.get("/check")
def signal_check(db: DB, horizon: int = 60, days: float = 30.0, crypto: bool = False, lookback: int = 45,
                 min_authors: int = 8) -> dict:
    """Does the crowd read predict what the price does next? Measured on the data collected so
    far, with five-minute prices from Alpaca. Recomputed at most every ten minutes."""
    from spectre.execution.alpaca import AlpacaClient
    from spectre.signals.intraday import check
    from spectre.signals.strategy import CRYPTO, STOCKS

    return _measured(db, ("check", horizon, days, crypto, lookback, min_authors), lambda: check(
        db, AlpacaClient(), days=days, horizon=horizon, lookback=lookback, min_authors=min_authors,
        enter=0.5 if crypto else 0.2, top_n=3 if crypto else 5, asset_classes=CRYPTO if crypto else STOCKS))


@router.get("/sweep")
def signal_sweep(db: DB, days: float = 30.0, lookback: int = 45, min_authors: int = 8) -> dict:
    """The same check at 30, 60, 120 and 240 minutes ahead, for the stock book and the coin book:
    how far ahead, if at all, does the crowd read say anything, and is it more than trading costs?"""
    from spectre.execution.alpaca import AlpacaClient
    from spectre.signals import intraday
    from spectre.signals.strategy import CRYPTO, STOCKS

    def both() -> dict:
        from spectre.trading.costs import round_trip

        client = AlpacaClient()
        out = {}
        for key, book, crypto in (("stocks", "Stocks and funds", False), ("coins", "Coins", True)):
            # What a trip in and out costs: measured from SPECTRE's own fills once there are enough, else an estimate.
            cost, measured = round_trip(db, book, intraday.round_trip_cost(crypto))
            out[key] = intraday.sweep(db, client, horizons=intraday.COIN_HORIZONS if crypto else intraday.HORIZONS, days=days,
                                      lookback=lookback, min_authors=min_authors, enter=0.5 if crypto else 0.2,
                                      top_n=3 if crypto else 5, asset_classes=CRYPTO if crypto else STOCKS, round_trip_cost=cost)
            out[key]["cost_is_measured"] = measured
        return out

    return _measured(db, ("sweep", days, lookback, min_authors), both)


dashboard_router = APIRouter(tags=["dashboard"])


@dashboard_router.get("/", include_in_schema=False)
@dashboard_router.get("/dashboard", include_in_schema=False)
def dashboard():
    return FileResponse(DASHBOARD, media_type="text/html")
