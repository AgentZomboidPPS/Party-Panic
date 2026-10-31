"""Stocktwits symbol streams. Posts carry an optional user-declared Bullish/Bearish label,
which is a useful calibration source for the sentiment model.

Not exercised in this repository's test environment (no outbound network).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

import httpx

from lantern.signals.sources.base import Emit, Post, sleep_or_stop, to_naive_utc

log = logging.getLogger(__name__)


class StocktwitsSource:
    name = "stocktwits"

    def __init__(self, symbols: list[str], poll_seconds: float = 60):
        self.symbols = symbols
        self.poll_seconds = poll_seconds
        self._since: dict[str, int] = {}

    async def _fetch(self, client: httpx.AsyncClient, symbol: str, emit: Emit) -> None:
        params = {"since": self._since[symbol]} if symbol in self._since else {}
        r = await client.get(f"https://api.stocktwits.com/api/2/streams/symbol/{symbol}.json", params=params)
        r.raise_for_status()
        for m in r.json().get("messages", []):
            self._since[symbol] = max(self._since.get(symbol, 0), int(m["id"]))
            user = m.get("user", {})
            joined = user.get("join_date")
            created = to_naive_utc(datetime.fromisoformat(m["created_at"].replace("Z", "+00:00")))
            age = None
            if joined:
                try:
                    age = (created - datetime.fromisoformat(joined)).days
                except ValueError:
                    age = None
            sentiment = ((m.get("entities") or {}).get("sentiment") or {}).get("basic")
            await emit(
                Post(
                    source=self.name,
                    external_id=str(m["id"]),
                    author_id=str(user.get("id", "")),
                    text=m.get("body", ""),
                    created_at=created,
                    lang="en",
                    followers=user.get("followers"),
                    account_age_days=age,
                    source_sentiment=sentiment,
                    meta={"symbol": symbol},
                )
            )

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=20, headers={"User-Agent": "lantern-signals/0.1"}) as client:
            while not stop.is_set():
                for s in self.symbols:
                    try:
                        await self._fetch(client, s, emit)
                    except Exception as exc:
                        log.warning("stocktwits %s: %s", s, exc)
                    if stop.is_set():
                        return
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
