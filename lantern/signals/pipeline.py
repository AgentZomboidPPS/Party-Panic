"""Ingestion pipeline: sources -> screening -> NLP -> store -> periodic aggregation."""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Callable
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from lantern.models import Security
from lantern.signals import aggregate
from lantern.signals.models import AuthorStats, PredictionMarket, SocialPost
from lantern.signals.nlp import SentimentModel, TickerExtractor, fear_flag
from lantern.signals.screening import Screener, author_hash
from lantern.signals.sources.base import MarketQuote, Post, Source, utcnow

log = logging.getLogger(__name__)

GENERIC_WORDS = {"us", "the", "and", "trust", "group", "inc", "corp", "treasury", "fund", "etf", "ag", "nv", "sa"}


def build_extractor(session: Session) -> TickerExtractor:
    """Tickers plus name aliases from the securities table ("Acme Systems" and "Acme" -> ACME)."""
    rows = session.execute(select(Security.ticker, Security.name)).all()
    tickers = {t for t, _ in rows}
    aliases: dict[str, str] = {}
    first_words: dict[str, set[str]] = {}
    for t, name in rows:
        aliases[name.lower()] = t
        first = name.split()[0].lower().strip(",.")
        if first.isalpha() and len(first) >= 4 and first not in GENERIC_WORDS:
            first_words.setdefault(first, set()).add(t)
    for w, ts in first_words.items():
        if len(ts) == 1:  # only unambiguous first words become aliases
            aliases[w] = next(iter(ts))
    return TickerExtractor(tickers, aliases)


class Pipeline:
    def __init__(
        self,
        session_factory: sessionmaker[Session],
        screener: Screener | None = None,
        sentiment: SentimentModel | None = None,
        extractor: TickerExtractor | None = None,
        salt: str = "lantern",
    ):
        self.session_factory = session_factory
        self.screener = screener or Screener()
        self.sentiment = sentiment or SentimentModel()
        self.salt = salt
        if extractor is None:
            with session_factory() as s:
                extractor = build_extractor(s)
        self.extractor = extractor
        self.counters = {"received": 0, "stored": 0, "duplicates": 0, "screened_out": 0, "quotes": 0}

    # --- batch processing (synchronous, usable without the event loop) -------------------

    def process_posts(self, posts: list[Post]) -> int:
        if not posts:
            return 0
        self.counters["received"] += len(posts)
        now = utcnow()
        with self.session_factory() as s:
            keys = {(p.source, p.external_id) for p in posts}
            existing = set(
                s.execute(
                    select(SocialPost.source, SocialPost.external_id).where(
                        SocialPost.external_id.in_({k[1] for k in keys})
                    )
                ).all()
            )
            rows: list[SocialPost] = []
            seen_batch: set[tuple[str, str]] = set()
            touched: set[tuple[str, str]] = set()
            for p in sorted(posts, key=lambda x: x.created_at):
                key = (p.source, p.external_id)
                if key in existing or key in seen_batch:
                    self.counters["duplicates"] += 1
                    continue
                seen_batch.add(key)
                ah = author_hash(p.source, p.author_id, self.salt)
                sr = self.screener.screen(p, ah)
                rows.append(
                    SocialPost(
                        source=p.source,
                        external_id=p.external_id,
                        posted_at=p.created_at,
                        ingested_at=now,
                        text=p.text[:4000],
                        lang=p.lang,
                        author_hash=ah,
                        author_quality=sr.quality,
                        screened_out=sr.screened_out,
                        screen_reason=sr.reason,
                        sentiment=self.sentiment.score(p.text),
                        fear=fear_flag(p.text),
                        tickers=self.extractor.extract(p.text),
                        dedup_hash=f"{sr.dedup_hash:016x}",
                        source_sentiment=p.source_sentiment,
                    )
                )
                touched.add((p.source, ah))
                if sr.screened_out:
                    self.counters["screened_out"] += 1
            s.add_all(rows)
            self._persist_author_stats(s, touched)
            s.commit()
        self.counters["stored"] += len(rows)
        return len(rows)

    def _persist_author_stats(self, s: Session, touched: set[tuple[str, str]]) -> None:
        if not touched:
            return
        hashes = {h for _, h in touched}
        existing = {
            (a.source, a.author_hash): a
            for a in s.execute(select(AuthorStats).where(AuthorStats.author_hash.in_(hashes))).scalars()
        }
        for source, h in touched:
            st = self.screener.stats.get(h)
            if not st:
                continue
            quality = 1.0
            if st["posts"]:
                quality = max(0.0, 1.0 - st["dups"] / st["posts"]) * (0.5 if st["burst_max"] >= self.screener.burst_hard else 1.0)
            a = existing.get((source, h))
            if a is None:
                a = AuthorStats(source=source, author_hash=h, first_seen=st["first"], last_seen=st["last"])
                s.add(a)
            a.post_count = st["posts"]
            a.dup_count = st["dups"]
            a.burst_max = st["burst_max"]
            a.last_seen = max(a.last_seen, st["last"])
            a.quality = quality
            a.flagged = quality < 0.5

    def process_quotes(self, quotes: list[MarketQuote]) -> int:
        if not quotes:
            return 0
        with self.session_factory() as s:
            for q in quotes:
                s.add(
                    PredictionMarket(
                        source=q.source,
                        market_id=q.market_id,
                        title=q.title[:300],
                        category=q.category,
                        yes_price=float(q.yes_price),
                        volume=q.volume,
                        open_interest=q.open_interest,
                        close_time=q.close_time,
                        snapshot_at=q.observed_at.replace(microsecond=0),
                    )
                )
            s.commit()
        self.counters["quotes"] += len(quotes)
        return len(quotes)

    def aggregate_window(self, start: datetime, end: datetime, topics: bool = True, bars: bool = True) -> None:
        with self.session_factory() as s:
            if topics:
                aggregate.build_topics(s, start, end)
            if bars:
                aggregate.build_sentiment_bars(s, start, end)
            s.commit()

    # --- live loop -----------------------------------------------------------------------

    async def run(
        self,
        sources: list[Source],
        duration_seconds: float | None = None,
        batch_seconds: float = 2.0,
        topic_window_minutes: int = 15,
        bar_window_minutes: int = 60,
        on_batch: Callable[[dict], None] | None = None,
    ) -> dict:
        """Run sources concurrently, flushing batches every `batch_seconds` and building
        topic bubbles / sentiment bars each time a window closes."""
        queue: asyncio.Queue = asyncio.Queue(maxsize=50_000)
        stop = asyncio.Event()

        async def emit(item):
            await queue.put(item)

        tasks = [asyncio.create_task(src.run(emit, stop)) for src in sources]
        started = time.monotonic()
        now = utcnow()
        last_topic = aggregate.floor_time(now, topic_window_minutes)
        last_bar = aggregate.floor_time(now, bar_window_minutes)
        try:
            while True:
                deadline = time.monotonic() + batch_seconds
                posts: list[Post] = []
                quotes: list[MarketQuote] = []
                while time.monotonic() < deadline:
                    try:
                        item = await asyncio.wait_for(queue.get(), timeout=max(deadline - time.monotonic(), 0.01))
                    except TimeoutError:
                        break
                    (posts if isinstance(item, Post) else quotes).append(item)
                loop = asyncio.get_running_loop()
                if posts:
                    await loop.run_in_executor(None, self.process_posts, posts)
                if quotes:
                    await loop.run_in_executor(None, self.process_quotes, quotes)

                now = utcnow()
                t_end = aggregate.floor_time(now, topic_window_minutes)
                if t_end > last_topic:
                    await loop.run_in_executor(None, self.aggregate_window, last_topic, t_end, True, False)
                    last_topic = t_end
                b_end = aggregate.floor_time(now, bar_window_minutes)
                if b_end > last_bar:
                    await loop.run_in_executor(None, self.aggregate_window, last_bar, b_end, False, True)
                    last_bar = b_end
                if on_batch:
                    on_batch(dict(self.counters, queue=queue.qsize()))
                if duration_seconds is not None and time.monotonic() - started >= duration_seconds:
                    break
        finally:
            stop.set()
            for t in tasks:
                t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            # Close out the partial windows so the dashboard shows the latest activity.
            now = utcnow()
            await asyncio.get_running_loop().run_in_executor(
                None, self.aggregate_window, last_topic, now + timedelta(seconds=1), True, True
            )
        return dict(self.counters)
