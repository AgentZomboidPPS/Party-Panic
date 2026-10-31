"""Reddit: polls the public JSON listing of each subreddit's newest posts and comments.

Reddit's API terms restrict commercial redistribution of content; this adapter is for
aggregate analysis. Set a descriptive user agent and keep the poll interval >= 30s.
Not exercised in this repository's test environment (no outbound network).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime

import httpx

from lantern.signals.sources.base import Emit, Post, sleep_or_stop

log = logging.getLogger(__name__)

DEFAULT_SUBREDDITS = ("wallstreetbets", "stocks", "investing", "economics", "StockMarket")


class RedditSource:
    name = "reddit"

    def __init__(self, subreddits=DEFAULT_SUBREDDITS, poll_seconds: float = 60, user_agent: str = "lantern-signals/0.1"):
        self.subreddits = list(subreddits)
        self.poll_seconds = poll_seconds
        self.user_agent = user_agent
        self._seen: set[str] = set()

    async def _fetch(self, client: httpx.AsyncClient, sub: str, emit: Emit) -> None:
        r = await client.get(f"https://www.reddit.com/r/{sub}/new.json", params={"limit": 100})
        r.raise_for_status()
        for child in r.json().get("data", {}).get("children", []):
            d = child.get("data", {})
            ext = d.get("name")
            if not ext or ext in self._seen:
                continue
            self._seen.add(ext)
            text = " ".join(x for x in (d.get("title"), d.get("selftext")) if x).strip()
            if not text:
                continue
            await emit(
                Post(
                    source=self.name,
                    external_id=ext,
                    author_id=d.get("author") or "",
                    text=text[:4000],
                    created_at=datetime.fromtimestamp(d.get("created_utc", 0), tz=UTC).replace(tzinfo=None),
                    lang="en",
                    url="https://www.reddit.com" + d.get("permalink", ""),
                    meta={"subreddit": sub, "score": d.get("score"), "num_comments": d.get("num_comments")},
                )
            )
        if len(self._seen) > 50_000:
            self._seen = set(list(self._seen)[-20_000:])

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(headers={"User-Agent": self.user_agent}, timeout=20) as client:
            while not stop.is_set():
                for sub in self.subreddits:
                    try:
                        await self._fetch(client, sub, emit)
                    except Exception as exc:
                        log.warning("reddit r/%s: %s", sub, exc)
                    if stop.is_set():
                        return
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
