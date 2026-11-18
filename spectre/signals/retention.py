"""Keeping a database that runs for months from growing without limit.

What is trimmed, and what is deliberately kept:
- raw posts and the price ticks that came with them: dropped after `post_days` (30). The
  sentiment bars and topics built from them stay, and so do daily closing prices.
- prediction-market snapshots: one is taken on every poll, thousands a day. After
  `market_detail_days` (7) only the last snapshot of each market on each day is kept, which is
  all a longer-run chart needs.
- never touched: the ledger (orders, fills, trades, cash), compliance checks, the audit trail,
  value snapshots, author statistics (screening needs an account's history) and price history.

SQLite does not hand freed space back to the disk, but it reuses it, so the file stops growing.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from spectre.signals.models import PredictionMarket, PriceTick, SocialPost
from spectre.signals.sources.base import utcnow


def prune(session: Session, post_days: int = 30, market_detail_days: int = 7, now: datetime | None = None) -> dict:
    now = now or utcnow()
    old = now - timedelta(days=post_days)
    posts = session.execute(delete(SocialPost).where(SocialPost.posted_at < old)).rowcount
    ticks = session.execute(delete(PriceTick).where(PriceTick.observed_at < old)).rowcount
    cutoff = now - timedelta(days=market_detail_days)
    keep = (
        select(func.max(PredictionMarket.id))
        .where(PredictionMarket.snapshot_at < cutoff)
        .group_by(PredictionMarket.source, PredictionMarket.market_id, func.date(PredictionMarket.snapshot_at))
    )
    markets = session.execute(
        delete(PredictionMarket).where(PredictionMarket.snapshot_at < cutoff, PredictionMarket.id.not_in(keep))
    ).rowcount
    session.commit()
    return {"posts": posts, "price_ticks": ticks, "market_snapshots": markets}
