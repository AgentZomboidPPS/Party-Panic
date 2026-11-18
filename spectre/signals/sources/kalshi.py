"""Kalshi prediction markets: public market data, no key needed for read-only endpoints.

Uses the events endpoint with nested markets, because events carry the category (Economics,
Politics, Financials, ...) and the plain markets listing is dominated by multi-leg sports
parlays. Prices arrive as dollar strings ("0.1200" = 12% implied probability).

Verified against the live API on 2026-11-18.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

import httpx

from spectre.signals.sources.base import Emit, MarketQuote, sleep_or_stop, to_naive_utc, utcnow

log = logging.getLogger(__name__)

BASE = "https://api.elections.kalshi.com/trade-api/v2"
DEFAULT_CATEGORIES = ("Economics", "Financials", "Politics", "Elections", "Companies", "World")
MAX_SPREAD = 0.15  # wider than this and the mid says little; fall back to the last trade


def _num(x) -> float | None:
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def _when(s: str | None) -> datetime | None:
    if not s:
        return None
    try:
        return to_naive_utc(datetime.fromisoformat(s.replace("Z", "+00:00")))
    except ValueError:
        return None


def market_price(m: dict) -> float | None:
    """Implied probability: the bid/ask mid when the book is tight, else the last trade."""
    bid, ask, last = _num(m.get("yes_bid_dollars")), _num(m.get("yes_ask_dollars")), _num(m.get("last_price_dollars"))
    if bid is not None and ask is not None and 0 < bid <= ask < 1 and ask - bid <= MAX_SPREAD:
        return (bid + ask) / 2.0
    if last is not None and 0 < last < 1:
        return last
    return None


def parse_event(event: dict, observed_at: datetime, max_markets: int = 3, min_volume: float = 1.0) -> list[MarketQuote]:
    """The most-traded priced markets of one event. Multi-leg parlay markets are skipped."""
    markets = event.get("markets") or []
    priced: list[tuple[float, dict, float]] = []
    for m in markets:
        if m.get("status") not in (None, "active", "open") or m.get("mve_collection_ticker"):
            continue
        volume = _num(m.get("volume_fp")) or 0.0
        px = market_price(m)
        if px is None or volume < min_volume:
            continue
        priced.append((volume, m, px))
    priced.sort(key=lambda t: -t[0])
    event_title = event.get("title") or ""
    out: list[MarketQuote] = []
    for volume, m, px in priced[:max_markets]:
        sub = (m.get("yes_sub_title") or "").strip()
        title = event_title or m.get("title") or m["ticker"]
        if len(markets) > 1 and sub:
            title = f"{title} — {sub}"
        out.append(
            MarketQuote(
                source="kalshi",
                market_id=m["ticker"],
                title=title,
                yes_price=px,
                observed_at=observed_at,
                category=event.get("category"),
                volume=volume,
                open_interest=_num(m.get("open_interest_fp")),
                close_time=_when(m.get("close_time")),
            )
        )
    return out


class KalshiSource:
    name = "kalshi"

    def __init__(
        self,
        poll_seconds: float = 300,
        categories: tuple[str, ...] | None = DEFAULT_CATEGORIES,
        max_pages: int = 3,
        max_markets_per_event: int = 3,
    ):
        self.poll_seconds = poll_seconds
        self.categories = set(categories) if categories else None
        self.max_pages = max_pages
        self.max_markets_per_event = max_markets_per_event

    async def fetch(self, client: httpx.AsyncClient) -> list[MarketQuote]:
        params: dict = {"status": "open", "with_nested_markets": "true", "limit": 200}
        out: list[MarketQuote] = []
        for _ in range(self.max_pages):
            r = await client.get(f"{BASE}/events", params=params)
            r.raise_for_status()
            body = r.json()
            now = utcnow()
            for event in body.get("events", []):
                if self.categories and event.get("category") not in self.categories:
                    continue
                out.extend(parse_event(event, now, self.max_markets_per_event))
            cursor = body.get("cursor")
            if not cursor:
                break
            params["cursor"] = cursor
        return out

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=60, headers={"User-Agent": "spectre-signals/0.1"}) as client:
            while not stop.is_set():
                try:
                    for q in await self.fetch(client):
                        await emit(q)
                except Exception as exc:
                    log.warning("kalshi: %s: %s", type(exc).__name__, exc)
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
