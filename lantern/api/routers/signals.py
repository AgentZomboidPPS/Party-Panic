from __future__ import annotations

import math
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd
from fastapi import APIRouter
from fastapi.responses import FileResponse
from sqlalchemy import select

from lantern.api.deps import DB
from lantern.signals import aggregate, signals
from lantern.signals.models import SentimentBar, Topic

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
def markets(db: DB) -> list[dict]:
    return _records(aggregate.latest_markets(db))


@router.get("/backtest")
def backtest(db: DB, start: date | None = None, end: date | None = None, horizon: int = 1, signal: str = "score",
             quantile: float = 0.3) -> dict:
    end = end or date.today()
    start = start or end - timedelta(days=365)
    return _clean(signals.evaluate(db, start, end, horizon, signal, quantile))


@router.post("/paper-trade/{portfolio_id}")
def paper_trade(portfolio_id: int, db: DB, top_n: int = 5, sleeve: float = 0.10, min_score: float = 0.5, fill: bool = False) -> dict:
    orders = signals.strategy_orders(db, portfolio_id, top_n=top_n, sleeve=sleeve, min_score=min_score)
    filled = signals.fill_approved_at_market(db, orders) if fill else 0
    return {
        "orders": [{"id": o.id, "security_id": o.security_id, "side": o.side, "quantity": o.quantity, "status": o.status,
                    "reject_reason": o.reject_reason} for o in orders],
        "filled": filled,
    }


dashboard_router = APIRouter(tags=["dashboard"])


@dashboard_router.get("/dashboard", include_in_schema=False)
def dashboard():
    return FileResponse(DASHBOARD, media_type="text/html")
