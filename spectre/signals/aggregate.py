"""Turn screened posts into aggregates: topic bubbles, per-security sentiment bars, fear index."""

from __future__ import annotations

from datetime import datetime, timedelta

import numpy as np
import pandas as pd
from sqlalchemy import delete, func, select, update
from sqlalchemy.orm import Session

from spectre.models import Security
from spectre.signals.models import PredictionMarket, SearchTrend, SentimentBar, SocialPost, Topic
from spectre.signals.nlp import cluster_topics

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


def _snapshot_at_or_before(cutoff: datetime | None):
    """Subquery: each market's most recent snapshot time (optionally at or before `cutoff`)."""
    q = select(PredictionMarket.source, PredictionMarket.market_id, func.max(PredictionMarket.snapshot_at).label("t"))
    if cutoff is not None:
        q = q.where(PredictionMarket.snapshot_at <= cutoff)
    return q.group_by(PredictionMarket.source, PredictionMarket.market_id).subquery()


def latest_markets(session: Session, min_prob: float = 0.0, max_prob: float = 1.0) -> pd.DataFrame:
    """Latest snapshot per market with its change over 24 hours, most-traded first.

    `min_prob` / `max_prob` keep only contested markets: a 0.05-0.95 band drops the long shots
    and foregone conclusions that dominate any ranking by volume.
    """

    def _join(sub):
        return (
            (PredictionMarket.source == sub.c.source)
            & (PredictionMarket.market_id == sub.c.market_id)
            & (PredictionMarket.snapshot_at == sub.c.t)
        )

    latest = _snapshot_at_or_before(None)
    rows = session.execute(
        select(PredictionMarket)
        .join(latest, _join(latest))
        .where(PredictionMarket.yes_price >= min_prob, PredictionMarket.yes_price <= max_prob)
    ).scalars().all()
    if not rows:
        return pd.DataFrame()
    newest = max(m.snapshot_at for m in rows)
    earlier = _snapshot_at_or_before(newest - timedelta(hours=24))
    day_ago = {
        (s, mid): px
        for s, mid, px in session.execute(
            select(PredictionMarket.source, PredictionMarket.market_id, PredictionMarket.yes_price).join(earlier, _join(earlier))
        ).all()
    }
    recs = [
        {
            "source": m.source, "market_id": m.market_id, "title": m.title, "category": m.category,
            "yes_price": m.yes_price,
            "change_24h": (m.yes_price - day_ago[(m.source, m.market_id)]) if (m.source, m.market_id) in day_ago else None,
            "volume": m.volume, "open_interest": m.open_interest,
            "close_time": m.close_time.isoformat() if m.close_time else None, "snapshot_at": m.snapshot_at.isoformat(),
        }
        for m in rows
    ]
    return pd.DataFrame(recs).sort_values("volume", ascending=False, na_position="last").reset_index(drop=True)


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
        "search_trends": int(session.execute(select(func.count(SearchTrend.id))).scalar_one()),
    }


def latest_trends(session: Session, hours: float = 24, limit: int = 30) -> list[dict]:
    """Trending search terms seen in the last `hours` of trend data, biggest first."""
    last = session.execute(select(func.max(SearchTrend.last_seen))).scalar_one_or_none()
    if last is None:
        return []
    rows = session.execute(
        select(SearchTrend)
        .where(SearchTrend.last_seen >= last - timedelta(hours=hours))
        .order_by(func.coalesce(SearchTrend.approx_traffic, 0).desc(), SearchTrend.started_at.desc())
        .limit(limit)
    ).scalars()
    return [
        {
            "source": t.source, "geo": t.geo, "term": t.term, "approx_traffic": t.approx_traffic,
            "started_at": t.started_at.isoformat(), "last_seen": t.last_seen.isoformat(),
            "headlines": t.headlines, "tickers": t.tickers,
        }
        for t in rows
    ]


def sentiment_calibration(session: Session, threshold: float = 0.05) -> dict:
    """Score the sentiment model against labels users gave their own posts (Stocktwits
    Bullish/Bearish). `accuracy` is over posts where the model took a side; `coverage` is how
    often it did. A coin flip scores 50% on a balanced sample."""
    rows = session.execute(
        select(SocialPost.source_sentiment, func.coalesce(SocialPost.model_sentiment, SocialPost.sentiment)).where(
            SocialPost.source_sentiment.in_(("Bullish", "Bearish")), SocialPost.screened_out.is_(False)
        )
    ).all()
    n = len(rows)
    counts = {"bull_as_bull": 0, "bull_as_bear": 0, "bull_as_neutral": 0, "bear_as_bear": 0, "bear_as_bull": 0, "bear_as_neutral": 0}
    for label, score in rows:
        side = "bull" if score > threshold else "bear" if score < -threshold else "neutral"
        counts[f"{'bull' if label == 'Bullish' else 'bear'}_as_{side}"] += 1
    decided = n - counts["bull_as_neutral"] - counts["bear_as_neutral"]
    correct = counts["bull_as_bull"] + counts["bear_as_bear"]
    n_bull = counts["bull_as_bull"] + counts["bull_as_bear"] + counts["bull_as_neutral"]
    return {
        "labelled_posts": n,
        "label_bullish_share": (n_bull / n) if n else None,
        "coverage": (decided / n) if n else None,
        "accuracy": (correct / decided) if decided else None,
        "majority_baseline": (max(n_bull, n - n_bull) / n) if n else None,
        "confusion": counts,
    }
