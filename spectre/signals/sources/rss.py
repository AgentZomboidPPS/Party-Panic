"""News headlines from RSS feeds. Low volume, high signal; treated as posts from a trusted author.

There are no default feeds: the two tried on 2026-11-18 were unusable (the WSJ markets feed
answers but has been frozen since January 2025; CNBC refuses automated clients). Pass your own
`feeds`. Entries older than `max_age_days` are ignored so a frozen feed cannot pose as news.
"""

from __future__ import annotations

import asyncio
import calendar
import logging
from datetime import UTC, datetime

import feedparser
import httpx

from spectre.signals.sources.base import Emit, Post, sleep_or_stop, utcnow

log = logging.getLogger(__name__)


class RssSource:
    name = "rss"

    def __init__(self, feeds: dict[str, str] | None = None, poll_seconds: float = 300, max_age_days: float = 3.0):
        if not feeds:
            raise ValueError("rss needs feeds: a mapping of name -> feed URL")
        self.feeds = feeds
        self.poll_seconds = poll_seconds
        self.max_age_days = max_age_days  # a feed frozen in the past must not look like fresh news
        self._seen: set[str] = set()

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=20, headers={"User-Agent": "spectre-signals/0.1"}, follow_redirects=True) as client:
            while not stop.is_set():
                for key, url in self.feeds.items():
                    try:
                        r = await client.get(url)
                        r.raise_for_status()
                        parsed = feedparser.parse(r.text)
                        for e in parsed.entries:
                            ext = e.get("id") or e.get("link")
                            if not ext or ext in self._seen:
                                continue
                            self._seen.add(ext)
                            text = " ".join(x for x in (e.get("title"), e.get("summary")) if x)
                            ts = e.get("published_parsed") or e.get("updated_parsed")
                            created = (
                                datetime.fromtimestamp(calendar.timegm(ts), tz=UTC).replace(tzinfo=None) if ts else utcnow()
                            )
                            if (utcnow() - created).total_seconds() > self.max_age_days * 86400:
                                continue
                            await emit(
                                Post(
                                    source=self.name,
                                    external_id=ext,
                                    author_id=key,
                                    text=text[:4000],
                                    created_at=created,
                                    lang="en",
                                    url=e.get("link"),
                                    followers=10**6,  # publishers are trusted authors
                                    account_age_days=3650,
                                    meta={"feed": key},
                                )
                            )
                    except Exception as exc:
                        log.warning("rss %s: %s", key, exc)
                    if stop.is_set():
                        return
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
