"""Bluesky public firehose via Jetstream (JSON websocket, no authentication).

Docs: https://github.com/bluesky-social/jetstream . Every public post on the network arrives
here in real time, which makes it the best open substitute for the X firehose.

Not exercised in this repository's test environment (no outbound network); written to the
documented message shape.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime

from lantern.signals.sources.base import Emit, Post, sleep_or_stop, to_naive_utc

log = logging.getLogger(__name__)

DEFAULT_URL = "wss://jetstream2.us-east.bsky.network/subscribe?wantedCollections=app.bsky.feed.post"


class BlueskyJetstream:
    name = "bluesky"

    def __init__(self, url: str = DEFAULT_URL, languages: tuple[str, ...] = ("en",), keywords: list[str] | None = None):
        self.url = url
        self.languages = set(languages)
        self.keywords = [k.lower() for k in (keywords or [])]

    def _wanted(self, text: str, langs: list[str]) -> bool:
        if self.languages and langs and not (set(langs) & self.languages):
            return False
        if self.keywords:
            low = text.lower()
            return any(k in low for k in self.keywords)
        return True

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        import websockets

        backoff = 1.0
        while not stop.is_set():
            try:
                async with websockets.connect(self.url, open_timeout=20, max_size=2**22) as ws:
                    backoff = 1.0
                    while not stop.is_set():
                        try:
                            raw = await asyncio.wait_for(ws.recv(), timeout=30)
                        except TimeoutError:
                            continue
                        msg = json.loads(raw)
                        if msg.get("kind") != "commit":
                            continue
                        commit = msg.get("commit", {})
                        if commit.get("operation") != "create" or commit.get("collection") != "app.bsky.feed.post":
                            continue
                        rec = commit.get("record", {})
                        text = rec.get("text") or ""
                        langs = rec.get("langs") or []
                        if not text or not self._wanted(text, langs):
                            continue
                        did = msg.get("did", "")
                        rkey = commit.get("rkey", "")
                        created = rec.get("createdAt")
                        try:
                            ts = to_naive_utc(datetime.fromisoformat(created.replace("Z", "+00:00"))) if created else None
                        except ValueError:
                            ts = None
                        await emit(
                            Post(
                                source=self.name,
                                external_id=f"{did}/{rkey}",
                                author_id=did,
                                text=text,
                                created_at=ts or to_naive_utc(datetime.now()),
                                lang=langs[0] if langs else None,
                                url=f"https://bsky.app/profile/{did}/post/{rkey}",
                            )
                        )
            except Exception as exc:  # network hiccups: reconnect with backoff
                log.warning("bluesky: %s: %s; reconnecting in %.0fs", type(exc).__name__, exc, backoff)
                if await sleep_or_stop(backoff, stop):
                    return
                backoff = min(backoff * 2, 60)
