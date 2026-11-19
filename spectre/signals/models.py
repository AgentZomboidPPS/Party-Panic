"""Tables for the signals layer. All timestamps are naive UTC."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from spectre.db import Base


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
    sentiment: Mapped[float] = mapped_column(Float)  # what aggregates use: the author's own label when given
    model_sentiment: Mapped[float | None] = mapped_column(Float)  # the model's score, always
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


class PriceTick(Base):
    """A price observed alongside a post (Stocktwits reports the symbol's price at posting time).

    Good enough to value positions and to line sentiment up against price moves; not an
    execution-grade quote.
    """

    __tablename__ = "price_ticks"
    __table_args__ = (UniqueConstraint("security_id", "observed_at", "source", name="uq_tick"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"), index=True)
    ticker: Mapped[str] = mapped_column(String(32), index=True)
    observed_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    price: Mapped[float] = mapped_column(Float)
    source: Mapped[str] = mapped_column(String(32))


class SearchTrend(Base):
    """A trending search term (Google Trends). One row per term per spike, updated while it lasts."""

    __tablename__ = "search_trends"
    __table_args__ = (UniqueConstraint("source", "geo", "term", "started_at", name="uq_trend_spike"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(32), index=True)
    geo: Mapped[str] = mapped_column(String(8))
    term: Mapped[str] = mapped_column(String(200), index=True)
    started_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    first_seen: Mapped[datetime] = mapped_column(DateTime)
    last_seen: Mapped[datetime] = mapped_column(DateTime, index=True)
    approx_traffic: Mapped[int | None] = mapped_column(Integer)
    headlines: Mapped[list] = mapped_column(JSON, default=list)
    tickers: Mapped[list] = mapped_column(JSON, default=list)


class NewsItem(Base):
    """A news headline about one or more securities, with the tone the sentiment scorer read in
    it. Information for a person looking at a holding; the bot does not trade on it."""

    __tablename__ = "news_items"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)  # "<provider>:<their id>"
    source: Mapped[str] = mapped_column(String(64))
    headline: Mapped[str] = mapped_column(Text)
    summary: Mapped[str | None] = mapped_column(Text)
    url: Mapped[str | None] = mapped_column(String(600))
    published_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    tickers: Mapped[list] = mapped_column(JSON, default=list)
    sentiment: Mapped[float] = mapped_column(Float, default=0.0)


class SignalReading(Base):
    """What KAIROS's score said about one name at one decision moment, written down at the time.

    The record the signal is judged against later: it cannot be flattered by hindsight (a score
    worked out again afterwards would use a sentiment model that has since learned from later
    posts), and it outlives the raw posts, which are dropped after a month."""

    __tablename__ = "signal_readings"
    __table_args__ = (UniqueConstraint("at", "ticker", name="uq_signal_reading"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    at: Mapped[datetime] = mapped_column(DateTime, index=True)
    ticker: Mapped[str] = mapped_column(String(32))
    asset_class: Mapped[str] = mapped_column(String(16))
    score: Mapped[float] = mapped_column(Float)
    authors: Mapped[int] = mapped_column(Integer)
    posts: Mapped[int] = mapped_column(Integer)
    lookback_minutes: Mapped[int] = mapped_column(Integer)
    # The other evidence as it stood then (signals/evidence.py); empty on readings from before it was kept.
    conviction: Mapped[float | None] = mapped_column(Float)  # what buying ranked on: the score, raised for a strong trend
    trend: Mapped[float | None] = mapped_column(Float)  # standing on 6-12 month momentum, 0 to 1
    tape: Mapped[float | None] = mapped_column(Float)  # the day's move against the typical name
    news: Mapped[float | None] = mapped_column(Float)  # tone of recent headlines, -1 to +1
    news_count: Mapped[int | None] = mapped_column(Integer)
    volume: Mapped[float | None] = mapped_column(Float)  # the last full day's volume as a multiple of the usual
