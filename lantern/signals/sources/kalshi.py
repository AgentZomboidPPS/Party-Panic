"""Kalshi prediction markets: public market data (no key needed for read-only endpoints).

API: https://trading-api.readme.io/reference/getmarkets . Prices are in cents.
Not exercised in this repository's test environment (no outbound network).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

import httpx

from lantern.signals.sources.base import Emit, MarketQuote, sleep_or_stop, to_naive_utc, utcnow

log = logging.getLogger(__name__)

BASE = "https://api.elections.kalshi.com/trade-api/v2"


class KalshiSource:
    name = "kalshi"

    def __init__(self, poll_seconds: float = 120, limit: int = 200, series_tickers: list[str] | None = None):
        self.poll_seconds = poll_seconds
        self.limit = limit
        self.series_tickers = series_tickers

    async def _fetch(self, client: httpx.AsyncClient, emit: Emit) -> None:
        params: dict = {"status": "open", "limit": self.limit}
        cursor = None
        pages = 0
        while pages < 5:
            if cursor:
                params["cursor"] = cursor
            r = await client.get(f"{BASE}/markets", params=params)
            r.raise_for_status()
            body = r.json()
            now = utcnow()
            for m in body.get("markets", []):
                if self.series_tickers and not any(m.get("ticker", "").startswith(s) for s in self.series_tickers):
                    continue
                last = m.get("last_price")
                bid, ask = m.get("yes_bid"), m.get("yes_ask")
                if bid is not None and ask is not None and ask > 0:
                    px = (bid + ask) / 2.0
                elif last is not None:
                    px = float(last)
                else:
                    continue
                close = m.get("close_time")
                await emit(
                    MarketQuote(
                        source=self.name,
                        market_id=m["ticker"],
                        title=m.get("title") or m.get("ticker"),
                        yes_price=px / 100.0,
                        observed_at=now,
                        category=m.get("category") or m.get("event_ticker"),
                        volume=m.get("volume"),
                        open_interest=m.get("open_interest"),
                        close_time=to_naive_utc(datetime.fromisoformat(close.replace("Z", "+00:00"))) if close else None,
                    )
                )
            cursor = body.get("cursor")
            pages += 1
            if not cursor:
                break

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=30, headers={"User-Agent": "lantern-signals/0.1"}) as client:
            while not stop.is_set():
                try:
                    await self._fetch(client, emit)
                except Exception as exc:
                    log.warning("kalshi: %s", exc)
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
