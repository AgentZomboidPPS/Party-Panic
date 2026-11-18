"""Ingestion pipeline: sources -> screening -> NLP -> store -> periodic aggregation."""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Callable
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session, sessionmaker

from lantern.marketdata.prices import upsert_prices
from lantern.marketdata.universe import BY_TICKER, recognition_maps
from lantern.models import Security
from lantern.signals import aggregate
from lantern.signals.models import AuthorStats, PredictionMarket, PriceTick, SearchTrend, SocialPost
from lantern.signals.nlp import SentimentModel, TickerExtractor, fear_flag
from lantern.signals.screening import Screener, author_hash
from lantern.signals.sources.base import MarketQuote, Post, Source, TrendItem, utcnow

log = logging.getLogger(__name__)

# When an author declares their stance, that beats any model's reading of their words.
LABEL_SCORES = {"Bullish": 0.7, "Bearish": -0.7}

GENERIC_WORDS = {"us", "the", "and", "trust", "group", "inc", "corp", "treasury", "fund", "etf", "ag", "nv", "sa"}


def build_extractor(session: Session) -> TickerExtractor:
    """How each security in the database may be recognised in free text.

    Securities in the curated universe use its hand-written rules (so "apple" needs market
    context and "nvidia" does not). Anything else falls back to its full name plus an
    unambiguous first word ("Acme Systems" and "Acme" -> ACME).
    """
    rows = session.execute(select(Security.ticker, Security.name)).all()
    tickers = {t for t, _ in rows}
    aliases, context_aliases, bare, context_bare = recognition_maps(tickers)
    first_words: dict[str, set[str]] = {}
    for t, name in rows:
        if t in BY_TICKER:
            continue
        aliases[name.lower()] = t
        first = name.split()[0].lower().strip(",.")
        if first.isalpha() and len(first) >= 4 and first not in GENERIC_WORDS:
            first_words.setdefault(first, set()).add(t)
    for w, ts in first_words.items():
        if len(ts) == 1 and w not in aliases and w not in context_aliases:
            aliases[w] = next(iter(ts))
    return TickerExtractor(tickers, aliases, context_aliases, bare, context_bare)


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
        self.counters = {"received": 0, "stored": 0, "duplicates": 0, "screened_out": 0, "quotes": 0, "trends": 0,
                         "price_ticks": 0}
        self._sec_ids: dict[str, int] | None = None
        self._last_tick: dict[tuple[int, object], datetime] = {}  # (security, date) -> newest tick time stored

    def _store_prices(self, s: Session, posts: list[Post]) -> None:
        """Keep the prices that arrived attached to posts: every tick, plus the day's latest as the close."""
        ticks: dict[tuple[str, datetime, str], float] = {}
        for p in posts:
            for sym, px in (p.meta.get("prices") or {}).items():
                ticks[(str(sym).upper(), p.created_at.replace(microsecond=0), p.source)] = float(px)
        if not ticks:
            return
        if self._sec_ids is None:
            self._sec_ids = dict(s.execute(select(Security.ticker, Security.id)).all())
        known = {k: v for k, v in ticks.items() if k[0] in self._sec_ids}
        if not known:
            return
        stamps = {k[1] for k in known}
        taken = set(
            s.execute(select(PriceTick.security_id, PriceTick.observed_at, PriceTick.source).where(PriceTick.observed_at.in_(stamps))).all()
        )
        daily: dict[tuple[int, object], tuple[datetime, float]] = {}
        for (sym, at, source), px in known.items():
            sid = self._sec_ids[sym]
            if (sid, at, source) not in taken:
                s.add(PriceTick(security_id=sid, ticker=sym, observed_at=at, price=px, source=source))
                self.counters["price_ticks"] += 1
            key = (sid, at.date())
            if at >= self._last_tick.get(key, datetime.min) and (key not in daily or at >= daily[key][0]):
                daily[key] = (at, px)
        for key, (at, _) in daily.items():
            self._last_tick[key] = at
        upsert_prices(s, [{"security_id": sid, "date": day, "close": px} for (sid, day), (_, px) in daily.items()])

    def _tickers(self, p: Post) -> list[str]:
        found = self.extractor.extract(p.text)
        for sym in p.meta.get("symbols") or []:  # symbols the platform itself attached to the post
            sym = str(sym).upper()
            if sym in self.extractor.tickers and sym not in found:
                found.append(sym)
        return found

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
                model_score = self.sentiment.score(p.text)
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
                        sentiment=LABEL_SCORES.get(p.source_sentiment or "", model_score),
                        model_sentiment=model_score,
                        fear=fear_flag(p.text),
                        tickers=self._tickers(p),
                        dedup_hash=f"{sr.dedup_hash:016x}",
                        source_sentiment=p.source_sentiment,
                    )
                )
                touched.add((p.source, ah))
                if sr.screened_out:
                    self.counters["screened_out"] += 1
            s.add_all(rows)
            self._persist_author_stats(s, touched)
            self._store_prices(s, posts)
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
        unique: dict[tuple, MarketQuote] = {}
        for q in quotes:  # one snapshot per market per second, whatever the sources send
            unique[(q.source, q.market_id, q.observed_at.replace(microsecond=0))] = q
        quotes = list(unique.values())
        with self.session_factory() as s:
            stamps = {k[2] for k in unique}
            taken = set(
                s.execute(
                    select(PredictionMarket.source, PredictionMarket.market_id, PredictionMarket.snapshot_at).where(
                        PredictionMarket.snapshot_at.in_(stamps)
                    )
                ).all()
            )
            quotes = [q for k, q in unique.items() if k not in taken]
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

    def process_trends(self, items: list[TrendItem]) -> int:
        """Upsert trending search terms: one row per term per spike, refreshed while it lasts."""
        if not items:
            return 0
        n = 0
        with self.session_factory() as s:
            for it in items:
                started = (it.started_at or it.observed_at.replace(hour=0, minute=0, second=0)).replace(microsecond=0)
                row = s.execute(
                    select(SearchTrend).where(
                        SearchTrend.source == it.source, SearchTrend.geo == it.geo,
                        SearchTrend.term == it.term[:200], SearchTrend.started_at == started,
                    )
                ).scalar_one_or_none()
                tickers = self.extractor.extract(" . ".join([it.term, *it.headlines]))
                if row is None:
                    s.add(SearchTrend(source=it.source, geo=it.geo, term=it.term[:200], started_at=started,
                                      first_seen=it.observed_at, last_seen=it.observed_at,
                                      approx_traffic=it.approx_traffic, headlines=it.headlines, tickers=tickers))
                    n += 1
                else:
                    row.last_seen = max(row.last_seen, it.observed_at)
                    row.approx_traffic = max(row.approx_traffic or 0, it.approx_traffic or 0) or None
                    row.headlines = it.headlines or row.headlines
                    row.tickers = tickers
            s.commit()
        self.counters["trends"] += n
        return n

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
        periodic: list[tuple[float, Callable[[], None]]] | None = None,
    ) -> dict:
        """Run sources concurrently, flushing batches every `batch_seconds` and building
        topic bubbles / sentiment bars each time a window closes.

        `periodic` is a list of (interval_seconds, job): each job runs on that cadence in a
        worker thread (the trend bot uses this). A job that raises is logged and tried again
        next time; it never stops ingestion."""
        jobs = [[interval, job, time.monotonic()] for interval, job in (periodic or [])]
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
                trends: list[TrendItem] = []
                while time.monotonic() < deadline:
                    try:
                        item = await asyncio.wait_for(queue.get(), timeout=max(deadline - time.monotonic(), 0.01))
                    except TimeoutError:
                        break
                    if isinstance(item, Post):
                        posts.append(item)
                    elif isinstance(item, MarketQuote):
                        quotes.append(item)
                    elif isinstance(item, TrendItem):
                        trends.append(item)
                loop = asyncio.get_running_loop()
                if posts:
                    await loop.run_in_executor(None, self.process_posts, posts)
                if quotes:
                    await loop.run_in_executor(None, self.process_quotes, quotes)
                if trends:
                    await loop.run_in_executor(None, self.process_trends, trends)

                now = utcnow()
                t_end = aggregate.floor_time(now, topic_window_minutes)
                if t_end > last_topic:
                    await loop.run_in_executor(None, self.aggregate_window, last_topic, t_end, True, False)
                    last_topic = t_end
                b_end = aggregate.floor_time(now, bar_window_minutes)
                if b_end > last_bar:
                    await loop.run_in_executor(None, self.aggregate_window, last_bar, b_end, False, True)
                    last_bar = b_end
                for entry in jobs:
                    interval, job, last_run = entry
                    if time.monotonic() - last_run >= interval:
                        entry[2] = time.monotonic()
                        try:
                            await loop.run_in_executor(None, job)
                        except Exception as exc:
                            log.warning("periodic job failed: %s: %s", type(exc).__name__, exc)
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
