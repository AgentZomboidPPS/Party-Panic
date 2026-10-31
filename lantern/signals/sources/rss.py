"""News headlines from RSS feeds. Low volume, high signal; treated as posts from a trusted author.

Not exercised in this repository's test environment (no outbound network).
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import UTC, datetime

import feedparser
import httpx

from lantern.signals.sources.base import Emit, Post, sleep_or_stop, utcnow

log = logging.getLogger(__name__)

DEFAULT_FEEDS = {
    "wsj-markets": "https://feeds.a.dj.com/rss/RSSMarketsMain.xml",
    "cnbc-top": "https://www.cnbc.com/id/100003114/device/rss/rss.html",
    "ft-markets": "https://www.ft.com/markets?format=rss",
}


class RssSource:
    name = "rss"

    def __init__(self, feeds: dict[str, str] | None = None, poll_seconds: float = 300):
        self.feeds = feeds or DEFAULT_FEEDS
        self.poll_seconds = poll_seconds
        self._seen: set[str] = set()

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=20, headers={"User-Agent": "lantern-signals/0.1"}, follow_redirects=True) as client:
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
                                datetime.fromtimestamp(time.mktime(ts), tz=UTC).replace(tzinfo=None) if ts else utcnow()
                            )
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
