"""Polymarket via the public Gamma API (read-only, no key).

API: https://docs.polymarket.com/ . `outcomePrices` is a JSON-encoded list aligned with `outcomes`.
Not exercised in this repository's test environment (no outbound network).
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime

import httpx

from lantern.signals.sources.base import Emit, MarketQuote, sleep_or_stop, to_naive_utc, utcnow

log = logging.getLogger(__name__)


class PolymarketSource:
    name = "polymarket"

    def __init__(self, poll_seconds: float = 120, limit: int = 200):
        self.poll_seconds = poll_seconds
        self.limit = limit

    async def _fetch(self, client: httpx.AsyncClient, emit: Emit) -> None:
        r = await client.get(
            "https://gamma-api.polymarket.com/markets",
            params={"active": "true", "closed": "false", "limit": self.limit, "order": "volume24hr", "ascending": "false"},
        )
        r.raise_for_status()
        now = utcnow()
        for m in r.json():
            try:
                outcomes = json.loads(m.get("outcomes") or "[]")
                prices = [float(p) for p in json.loads(m.get("outcomePrices") or "[]")]
            except (ValueError, TypeError):
                continue
            if not prices:
                continue
            yes_idx = outcomes.index("Yes") if "Yes" in outcomes else 0
            end = m.get("endDate")
            await emit(
                MarketQuote(
                    source=self.name,
                    market_id=str(m.get("id") or m.get("slug")),
                    title=m.get("question") or m.get("slug", ""),
                    yes_price=prices[yes_idx],
                    observed_at=now,
                    category=(m.get("category") or None),
                    volume=float(m["volume"]) if m.get("volume") is not None else None,
                    open_interest=float(m["liquidity"]) if m.get("liquidity") is not None else None,
                    close_time=to_naive_utc(datetime.fromisoformat(end.replace("Z", "+00:00"))) if end else None,
                )
            )

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=30, headers={"User-Agent": "lantern-signals/0.1"}) as client:
            while not stop.is_set():
                try:
                    await self._fetch(client, emit)
                except Exception as exc:
                    log.warning("polymarket: %s", exc)
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
