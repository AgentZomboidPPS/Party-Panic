"""Stocktwits: the trending stream (one request, messages across many symbols) and optional
per-symbol streams. Messages carry an optional user-declared Bullish/Bearish label, which is
the ground truth used to calibrate the sentiment model.

The unauthenticated API allows roughly 200 requests an hour, so requests are spaced out.

Verified against the live API on 2026-11-18.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

import httpx

from spectre.signals.sources.base import Emit, Post, sleep_or_stop, to_naive_utc

log = logging.getLogger(__name__)

BASE = "https://api.stocktwits.com/api/2"


def parse_message(m: dict) -> Post | None:
    try:
        created = to_naive_utc(datetime.fromisoformat(m["created_at"].replace("Z", "+00:00")))
        ext = str(m["id"])
    except (KeyError, ValueError, AttributeError):
        return None
    body = m.get("body") or ""
    if not body:
        return None
    user = m.get("user") or {}
    age = None
    joined = user.get("join_date")
    if joined:
        try:
            age = (created - datetime.fromisoformat(joined)).days
        except ValueError:
            age = None
    sentiment = ((m.get("entities") or {}).get("sentiment") or {}).get("basic")
    prices: dict[str, float] = {}
    for p in m.get("prices") or []:  # the symbol's price when the message was posted
        try:
            if p.get("symbol") and float(p["price"]) > 0:
                prices[p["symbol"]] = float(p["price"])
        except (KeyError, TypeError, ValueError):
            continue
    return Post(
        source="stocktwits",
        external_id=ext,
        author_id=str(user.get("id", "")),
        text=body,
        created_at=created,
        lang="en",
        followers=user.get("followers"),
        account_age_days=age,
        source_sentiment=sentiment,
        meta={"symbols": [s.get("symbol") for s in (m.get("symbols") or []) if s.get("symbol")], "prices": prices},
    )


class StocktwitsSource:
    name = "stocktwits"

    def __init__(
        self,
        symbols: list[str] | None = None,
        trending: bool = True,
        poll_seconds: float = 120,
        request_gap_seconds: float = 20,
    ):
        self.symbols = list(symbols or [])
        self.trending = trending
        self.poll_seconds = poll_seconds
        self.request_gap_seconds = request_gap_seconds
        self._since: dict[str, int] = {}

    async def _fetch(self, client: httpx.AsyncClient, path: str, key: str) -> list[Post]:
        params = {"since": self._since[key]} if key in self._since else {}
        r = await client.get(f"{BASE}/{path}", params=params)
        r.raise_for_status()
        out: list[Post] = []
        for m in r.json().get("messages", []):
            try:
                self._since[key] = max(self._since.get(key, 0), int(m["id"]))
            except (KeyError, ValueError, TypeError):
                pass
            p = parse_message(m)
            if p is not None:
                out.append(p)
        return out

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        streams = ([("streams/trending.json", "__trending__")] if self.trending else []) + [
            (f"streams/symbol/{s}.json", s) for s in self.symbols
        ]
        async with httpx.AsyncClient(timeout=30, headers={"User-Agent": "spectre-signals/0.1"}) as client:
            while not stop.is_set():
                for path, key in streams:
                    try:
                        for p in await self._fetch(client, path, key):
                            await emit(p)
                    except Exception as exc:
                        log.warning("stocktwits %s: %s: %s", key, type(exc).__name__, exc)
                    if await sleep_or_stop(self.request_gap_seconds, stop):
                        return
                remaining = self.poll_seconds - self.request_gap_seconds * len(streams)
                if remaining > 0 and await sleep_or_stop(remaining, stop):
                    return
