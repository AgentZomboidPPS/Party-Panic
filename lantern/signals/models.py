"""Tables for the signals layer. All timestamps are naive UTC."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from lantern.db import Base


class SocialPost(Base):
    __tablename__ = "social_posts"
    __table_args__ = (
        UniqueConstraint("source", "external_id", name="uq_post_source_ext"),
        Index("ix_post_posted_screened", "posted_at", "screened_out"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(32), index=True)
    external_id: Mapped[str] = mapped_column(String(128))
    posted_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    ingested_at: Mapped[datetime] = mapped_column(DateTime)
    text: Mapped[str] = mapped_column(Text)
    lang: Mapped[str | None] = mapped_column(String(8))
    author_hash: Mapped[str] = mapped_column(String(32), index=True)
    author_quality: Mapped[float] = mapped_column(Float)
    screened_out: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    screen_reason: Mapped[str | None] = mapped_column(String(64))
    sentiment: Mapped[float] = mapped_column(Float)
    fear: Mapped[bool] = mapped_column(Boolean, default=False)
    tickers: Mapped[list] = mapped_column(JSON, default=list)
    dedup_hash: Mapped[str] = mapped_column(String(16), index=True)
    source_sentiment: Mapped[str | None] = mapped_column(String(16))
    topic_id: Mapped[int | None] = mapped_column(ForeignKey("topics.id"), index=True)


class AuthorStats(Base):
    """Per-author aggregates used only for screening. The hash cannot be reversed to an account."""

    __tablename__ = "author_stats"
    __table_args__ = (UniqueConstraint("source", "author_hash", name="uq_author"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(32))
    author_hash: Mapped[str] = mapped_column(String(32), index=True)
    first_seen: Mapped[datetime] = mapped_column(DateTime)
    last_seen: Mapped[datetime] = mapped_column(DateTime)
    post_count: Mapped[int] = mapped_column(Integer, default=0)
    dup_count: Mapped[int] = mapped_column(Integer, default=0)
    burst_max: Mapped[int] = mapped_column(Integer, default=0)
    quality: Mapped[float] = mapped_column(Float, default=1.0)
    flagged: Mapped[bool] = mapped_column(Boolean, default=False)


class Topic(Base):
    """An 'idea bubble': a cluster of posts in one time window."""

    __tablename__ = "topics"
    __table_args__ = (Index("ix_topic_window", "window_start", "window_end"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    window_start: Mapped[datetime] = mapped_column(DateTime)
    window_end: Mapped[datetime] = mapped_column(DateTime, index=True)
    label: Mapped[str] = mapped_column(String(200))
    keywords: Mapped[list] = mapped_column(JSON, default=list)
    volume: Mapped[int] = mapped_column(Integer)
    unique_authors: Mapped[int] = mapped_column(Integer)
    sentiment_mean: Mapped[float] = mapped_column(Float)
    fear_share: Mapped[float] = mapped_column(Float)
    velocity: Mapped[float] = mapped_column(Float)  # volume change vs matching topic in previous window
    tickers: Mapped[list] = mapped_column(JSON, default=list)  # [[ticker, count], ...]
    sample: Mapped[list] = mapped_column(JSON, default=list)  # a few representative texts


class SentimentBar(Base):
    __tablename__ = "sentiment_bars"
    __table_args__ = (UniqueConstraint("security_id", "window_start", name="uq_bar_security_window"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"), index=True)
    ticker: Mapped[str] = mapped_column(String(32), index=True)
    window_start: Mapped[datetime] = mapped_column(DateTime, index=True)
    window_end: Mapped[datetime] = mapped_column(DateTime)
    n_posts: Mapped[int] = mapped_column(Integer)
    n_authors: Mapped[int] = mapped_column(Integer)
    sentiment_mean: Mapped[float] = mapped_column(Float)
    sentiment_std: Mapped[float] = mapped_column(Float)
    bull_share: Mapped[float] = mapped_column(Float)
    bear_share: Mapped[float] = mapped_column(Float)
    attention_z: Mapped[float | None] = mapped_column(Float)
    sentiment_z: Mapped[float | None] = mapped_column(Float)


class PredictionMarket(Base):
    __tablename__ = "prediction_markets"
    __table_args__ = (UniqueConstraint("source", "market_id", "snapshot_at", name="uq_pm_snapshot"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(32), index=True)
    market_id: Mapped[str] = mapped_column(String(128), index=True)
    title: Mapped[str] = mapped_column(String(300))
    category: Mapped[str | None] = mapped_column(String(64))
    yes_price: Mapped[float] = mapped_column(Float)  # implied probability, 0..1
    volume: Mapped[float | None] = mapped_column(Float)
    open_interest: Mapped[float | None] = mapped_column(Float)
    close_time: Mapped[datetime | None] = mapped_column(DateTime)
    snapshot_at: Mapped[datetime] = mapped_column(DateTime, index=True)
