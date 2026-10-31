"""Turn screened posts into aggregates: topic bubbles, per-security sentiment bars, fear index."""

from __future__ import annotations

from datetime import datetime, timedelta

import numpy as np
import pandas as pd
from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from lantern.models import Security
from lantern.signals.models import PredictionMarket, SentimentBar, SocialPost, Topic
from lantern.signals.nlp import cluster_topics

BULL_T, BEAR_T = 0.2, -0.2


def floor_time(dt: datetime, minutes: int) -> datetime:
    dt = dt.replace(second=0, microsecond=0)
    if minutes >= 1440:
        return dt.replace(hour=0, minute=0)
    return dt - timedelta(minutes=dt.minute % minutes) if minutes < 60 else dt.replace(minute=0) - timedelta(
        hours=dt.hour % (minutes // 60)
    )


def load_posts(session: Session, start: datetime, end: datetime, include_screened: bool = False) -> pd.DataFrame:
    q = select(
        SocialPost.id, SocialPost.posted_at, SocialPost.text, SocialPost.author_hash, SocialPost.sentiment,
        SocialPost.fear, SocialPost.tickers, SocialPost.source,
    ).where(SocialPost.posted_at >= start, SocialPost.posted_at < end)
    if not include_screened:
        q = q.where(SocialPost.screened_out.is_(False))
    rows = session.execute(q).all()
    return pd.DataFrame(rows, columns=["id", "posted_at", "text", "author_hash", "sentiment", "fear", "tickers", "source"])


def _jaccard(a: list[str], b: list[str]) -> float:
    sa, sb = set(a), set(b)
    return len(sa & sb) / len(sa | sb) if sa | sb else 0.0


def build_topics(session: Session, window_start: datetime, window_end: datetime, max_topics: int = 15) -> list[Topic]:
    """Cluster the window's posts into topics (idempotent for the window)."""
    session.execute(delete(Topic).where(Topic.window_start == window_start, Topic.window_end == window_end))
    df = load_posts(session, window_start, window_end)
    if df.empty:
        return []
    previous = list(session.execute(select(Topic).where(Topic.window_end == window_start)).scalars())
    clusters = cluster_topics(df["text"].tolist(), max_topics=max_topics)
    out: list[Topic] = []
    for c in clusters:
        sub = df.iloc[c.indices]
        counts: dict[str, int] = {}
        for ts in sub["tickers"]:
            for t in ts or []:
                counts[t] = counts.get(t, 0) + 1
        top_tickers = sorted(counts.items(), key=lambda kv: -kv[1])[:5]
        vol = int(len(sub))
        my_tickers = [t for t, _ in top_tickers]

        def _sim(p: Topic, kw=c.keywords, tk=my_tickers) -> float:
            return max(_jaccard(p.keywords, kw), _jaccard([t for t, _ in p.tickers], tk) * 0.8)

        best = max(previous, key=_sim, default=None)
        if best is not None and _sim(best) >= 0.2:
            velocity = (vol - best.volume) / max(best.volume, 1)
        else:
            velocity = 1.0  # brand-new topic
        topic = Topic(
            window_start=window_start,
            window_end=window_end,
            label=c.label,
            keywords=c.keywords,
            volume=vol,
            unique_authors=int(sub["author_hash"].nunique()),
            sentiment_mean=float(sub["sentiment"].mean()),
            fear_share=float(sub["fear"].mean()),
            velocity=float(velocity),
            tickers=[[t, n] for t, n in top_tickers],
            sample=[str(x)[:200] for x in sub["text"].head(3)],
        )
        session.add(topic)
        session.flush()
        session.execute(update(SocialPost).where(SocialPost.id.in_(sub["id"].tolist())).values(topic_id=topic.id))
        out.append(topic)
    return out


def build_sentiment_bars(session: Session, window_start: datetime, window_end: datetime, baseline: int = 20) -> list[SentimentBar]:
    """One bar per security mentioned in the window, with z-scores against its own trailing bars."""
    session.execute(delete(SentimentBar).where(SentimentBar.window_start == window_start))
    df = load_posts(session, window_start, window_end)
    if df.empty:
        return []
    ex = df.explode("tickers").dropna(subset=["tickers"]).rename(columns={"tickers": "ticker"})
    if ex.empty:
        return []
    sec_ids = dict(session.execute(select(Security.ticker, Security.id)).all())
    out: list[SentimentBar] = []
    for ticker, g in ex.groupby("ticker"):
        if ticker not in sec_ids:
            continue
        sid = sec_ids[ticker]
        prior = session.execute(
            select(SentimentBar.n_posts, SentimentBar.sentiment_mean)
            .where(SentimentBar.security_id == sid, SentimentBar.window_start < window_start)
            .order_by(SentimentBar.window_start.desc())
            .limit(baseline)
        ).all()
        n, s_mean = int(len(g)), float(g["sentiment"].mean())
        att_z = sent_z = None
        if len(prior) >= 5:
            pn = np.array([p[0] for p in prior], dtype=float)
            ps = np.array([p[1] for p in prior], dtype=float)
            if pn.std() > 0:
                att_z = float((n - pn.mean()) / pn.std())
            if ps.std() > 0:
                sent_z = float((s_mean - ps.mean()) / ps.std())
        out.append(
            SentimentBar(
                security_id=sid,
                ticker=ticker,
                window_start=window_start,
                window_end=window_end,
                n_posts=n,
                n_authors=int(g["author_hash"].nunique()),
                sentiment_mean=s_mean,
                sentiment_std=float(g["sentiment"].std(ddof=0)),
                bull_share=float((g["sentiment"] > BULL_T).mean()),
                bear_share=float((g["sentiment"] < BEAR_T).mean()),
                attention_z=att_z,
                sentiment_z=sent_z,
            )
        )
    session.add_all(out)
    session.flush()
    return out


def fear_index(session: Session, start: datetime, end: datetime, freq_minutes: int = 60) -> pd.Series:
    """Share of screened-in posts using fear vocabulary, per bucket."""
    df = load_posts(session, start, end)
    if df.empty:
        return pd.Series(dtype=float)
    idx = pd.to_datetime(df["posted_at"]).dt.floor(f"{freq_minutes}min")
    return df.groupby(idx)["fear"].mean().astype(float)


def latest_topics(session: Session, at: datetime | None = None) -> list[Topic]:
    q = select(func.max(Topic.window_end))
    if at is not None:
        q = q.where(Topic.window_end <= at)
    end = session.execute(q).scalar_one_or_none()
    if end is None:
        return []
    return list(session.execute(select(Topic).where(Topic.window_end == end).order_by(Topic.volume.desc())).scalars())


def latest_sentiment(session: Session, at: datetime | None = None) -> pd.DataFrame:
    """Most recent bar per ticker."""
    q = select(SentimentBar.ticker, func.max(SentimentBar.window_start).label("ws")).group_by(SentimentBar.ticker)
    if at is not None:
        q = q.where(SentimentBar.window_end <= at)
    latest = q.subquery()
    rows = session.execute(
        select(SentimentBar).join(latest, (SentimentBar.ticker == latest.c.ticker) & (SentimentBar.window_start == latest.c.ws))
    ).scalars()
    recs = [
        {
            "security_id": b.security_id, "ticker": b.ticker, "window_start": b.window_start, "window_end": b.window_end,
            "n_posts": b.n_posts, "n_authors": b.n_authors, "sentiment_mean": b.sentiment_mean,
            "bull_share": b.bull_share, "bear_share": b.bear_share, "attention_z": b.attention_z, "sentiment_z": b.sentiment_z,
        }
        for b in rows
    ]
    df = pd.DataFrame(recs)
    if df.empty:
        return df
    return df.sort_values("n_posts", ascending=False).reset_index(drop=True)


def latest_markets(session: Session) -> pd.DataFrame:
    latest = (
        select(PredictionMarket.source, PredictionMarket.market_id, func.max(PredictionMarket.snapshot_at).label("t"))
        .group_by(PredictionMarket.source, PredictionMarket.market_id)
        .subquery()
    )
    rows = session.execute(
        select(PredictionMarket).join(
            latest,
            (PredictionMarket.source == latest.c.source)
            & (PredictionMarket.market_id == latest.c.market_id)
            & (PredictionMarket.snapshot_at == latest.c.t),
        )
    ).scalars().all()
    recs = []
    for m in rows:
        day_ago = session.execute(
            select(PredictionMarket.yes_price)
            .where(
                PredictionMarket.source == m.source,
                PredictionMarket.market_id == m.market_id,
                PredictionMarket.snapshot_at <= m.snapshot_at - timedelta(hours=24),
            )
            .order_by(PredictionMarket.snapshot_at.desc())
            .limit(1)
        ).scalar_one_or_none()
        recs.append(
            {
                "source": m.source, "market_id": m.market_id, "title": m.title, "category": m.category,
                "yes_price": m.yes_price, "change_24h": (m.yes_price - day_ago) if day_ago is not None else None,
                "volume": m.volume, "open_interest": m.open_interest,
                "close_time": m.close_time.isoformat() if m.close_time else None, "snapshot_at": m.snapshot_at.isoformat(),
            }
        )
    df = pd.DataFrame(recs)
    return df.sort_values("volume", ascending=False, na_position="last").reset_index(drop=True) if not df.empty else df


def feed_status(session: Session) -> dict:
    total = session.execute(select(func.count(SocialPost.id))).scalar_one()
    screened = session.execute(select(func.count(SocialPost.id)).where(SocialPost.screened_out.is_(True))).scalar_one()
    last = session.execute(select(func.max(SocialPost.posted_at))).scalar_one_or_none()
    hour_ago = (last - timedelta(hours=1)) if last else None
    last_hour = (
        session.execute(select(func.count(SocialPost.id)).where(SocialPost.posted_at >= hour_ago)).scalar_one() if hour_ago else 0
    )
    by_source = dict(session.execute(select(SocialPost.source, func.count(SocialPost.id)).group_by(SocialPost.source)).all())
    reasons = dict(
        session.execute(
            select(SocialPost.screen_reason, func.count(SocialPost.id))
            .where(SocialPost.screened_out.is_(True))
            .group_by(SocialPost.screen_reason)
        ).all()
    )
    markets = session.execute(select(func.count(func.distinct(PredictionMarket.market_id)))).scalar_one()
    return {
        "posts_total": int(total),
        "posts_screened_out": int(screened),
        "screened_share": (screened / total) if total else 0.0,
        "posts_last_hour": int(last_hour),
        "last_post_at": last.isoformat() if last else None,
        "by_source": {k: int(v) for k, v in by_source.items()},
        "screen_reasons": {str(k): int(v) for k, v in reasons.items()},
        "topics_windows": int(session.execute(select(func.count(func.distinct(Topic.window_end)))).scalar_one()),
        "sentiment_bars": int(session.execute(select(func.count(SentimentBar.id))).scalar_one()),
        "prediction_markets": int(markets),
    }
