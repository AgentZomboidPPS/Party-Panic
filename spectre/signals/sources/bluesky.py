"""Bluesky public firehose via Jetstream (JSON websocket, no authentication).

Docs: https://github.com/bluesky-social/jetstream . Every public post on the network arrives
here in real time: about 48 posts a second, 34 of them in English (measured 2026-11-18), which
makes it the best open substitute for the X firehose.

Two ways to cut that down: `keywords` keeps only posts matching a term (whole words, case
insensitive) or carrying a cashtag; `sample` keeps a random fraction of what is left.

Verified against the live stream on 2026-11-18.
"""

from __future__ import annotations

import asyncio
import json
import logging
import random
import re
from datetime import datetime

from spectre.signals.sources.base import Emit, Post, sleep_or_stop, to_naive_utc, utcnow

log = logging.getLogger(__name__)

DEFAULT_URL = "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.post"
_CASHTAG = re.compile(r"\$[A-Za-z]{1,6}\b")


def parse_commit(msg: dict) -> Post | None:
    """A new-post commit as a Post; anything else (deletes, likes, identity events) is None."""
    if msg.get("kind") != "commit":
        return None
    commit = msg.get("commit") or {}
    if commit.get("operation") != "create" or commit.get("collection") != "app.bsky.feed.post":
        return None
    rec = commit.get("record") or {}
    text = rec.get("text") or ""
    did, rkey = msg.get("did") or "", commit.get("rkey") or ""
    if not text or not did or not rkey:
        return None
    created = None
    raw = rec.get("createdAt")
    if raw:
        try:
            created = to_naive_utc(datetime.fromisoformat(raw.replace("Z", "+00:00")))
        except ValueError:
            created = None
    now = utcnow()
    # createdAt comes from the author's device: never accept the future, nor anything over an
    # hour old (backdated or replayed posts). Fall back to the arrival time.
    if created is None or created > now or (now - created).total_seconds() > 3600:
        created = now
    langs = rec.get("langs") or []
    return Post(
        source="bluesky",
        external_id=f"{did}/{rkey}",
        author_id=did,
        text=text,
        created_at=created,
        lang=langs[0] if langs else None,
        url=f"https://bsky.app/profile/{did}/post/{rkey}",
        meta={"is_reply": "reply" in rec},
    )


def keyword_pattern(keywords: list[str]) -> re.Pattern | None:
    words = sorted({k.strip().lower() for k in keywords if k and k.strip()}, key=len, reverse=True)
    if not words:
        return None
    return re.compile(r"(?<![\w$])(?:" + "|".join(re.escape(w) for w in words) + r")(?![\w])", re.IGNORECASE)


class BlueskyJetstream:
    name = "bluesky"

    def __init__(
        self,
        url: str = DEFAULT_URL,
        languages: tuple[str, ...] = ("en",),
        keywords: list[str] | None = None,
        match_cashtags: bool = True,
        sample: float = 1.0,
        seed: int | None = None,
    ):
        self.url = url
        self.languages = set(languages)
        self.pattern = keyword_pattern(keywords or [])
        self.match_cashtags = match_cashtags
        self.sample = sample
        self._rng = random.Random(seed)

    def wanted(self, post: Post) -> bool:
        if self.languages and (post.lang or "").split("-")[0] not in self.languages:
            return False
        if self.pattern is not None:
            hit = bool(self.pattern.search(post.text)) or (self.match_cashtags and bool(_CASHTAG.search(post.text)))
            if not hit:
                return False
        return self.sample >= 1.0 or self._rng.random() < self.sample

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        import websockets

        backoff = 1.0
        while not stop.is_set():
            try:
                async with websockets.connect(self.url, open_timeout=25, max_size=2**22) as ws:
                    backoff = 1.0
                    while not stop.is_set():
                        try:
                            raw = await asyncio.wait_for(ws.recv(), timeout=30)
                        except TimeoutError:
                            continue
                        try:
                            post = parse_commit(json.loads(raw))
                        except (ValueError, TypeError):
                            continue
                        if post is not None and self.wanted(post):
                            await emit(post)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # network hiccups: reconnect with backoff
                log.warning("bluesky: %s: %s; reconnecting in %.0fs", type(exc).__name__, exc, backoff)
                if await sleep_or_stop(backoff, stop):
                    return
                backoff = min(backoff * 2, 60)
