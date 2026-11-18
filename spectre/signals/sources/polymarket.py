"""Polymarket via the public Gamma API (read-only, no key).

Pulls events by topic tag, because "top markets by volume" is mostly esports and football.
Each event nests its markets; `outcomes` and `outcomePrices` are JSON-encoded lists.

Verified against the live API on 2026-11-18.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime

import httpx

from spectre.signals.sources.base import Emit, MarketQuote, sleep_or_stop, to_naive_utc, utcnow

log = logging.getLogger(__name__)

BASE = "https://gamma-api.polymarket.com"
DEFAULT_TAGS = ("economy", "fed", "finance", "business", "politics", "geopolitics", "crypto", "tech")


def _num(x) -> float | None:
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def parse_market(m: dict, observed_at: datetime, category: str | None = None) -> MarketQuote | None:
    """One binary Yes/No market, or None if it is closed, non-binary or unpriced."""
    if m.get("closed") or m.get("active") is False:
        return None
    try:
        outcomes = json.loads(m.get("outcomes") or "[]")
        prices = [float(p) for p in json.loads(m.get("outcomePrices") or "[]")]
    except (ValueError, TypeError):
        return None
    if "Yes" not in outcomes or len(prices) != len(outcomes):
        return None
    end = m.get("endDate")
    close = None
    if end:
        try:
            close = to_naive_utc(datetime.fromisoformat(end.replace("Z", "+00:00")))
        except ValueError:
            close = None
    return MarketQuote(
        source="polymarket",
        market_id=str(m.get("id") or m.get("slug")),
        title=m.get("question") or m.get("slug", ""),
        yes_price=prices[outcomes.index("Yes")],
        observed_at=observed_at,
        category=category,
        volume=_num(m.get("volume")),
        open_interest=_num(m.get("liquidity")),
        close_time=close,
    )


def parse_event(event: dict, observed_at: datetime, category: str | None, max_markets: int = 5) -> list[MarketQuote]:
    """The most actively traded markets of one event (some events nest over a hundred)."""
    markets = sorted(event.get("markets") or [], key=lambda m: -(_num(m.get("volume24hr")) or 0.0))
    out: list[MarketQuote] = []
    for m in markets:
        q = parse_market(m, observed_at, category)
        if q is not None:
            out.append(q)
        if len(out) >= max_markets:
            break
    return out


class PolymarketSource:
    name = "polymarket"

    def __init__(
        self,
        poll_seconds: float = 300,
        tags: tuple[str, ...] = DEFAULT_TAGS,
        events_per_tag: int = 15,
        max_markets_per_event: int = 5,
    ):
        self.poll_seconds = poll_seconds
        self.tags = tuple(tags)
        self.events_per_tag = events_per_tag
        self.max_markets_per_event = max_markets_per_event

    async def fetch(self, client: httpx.AsyncClient) -> list[MarketQuote]:
        seen: set[str] = set()
        out: list[MarketQuote] = []
        for tag in self.tags:
            r = await client.get(
                f"{BASE}/events",
                params={"tag_slug": tag, "active": "true", "closed": "false", "limit": self.events_per_tag,
                        "order": "volume24hr", "ascending": "false"},
            )
            r.raise_for_status()
            now = utcnow()
            for event in r.json():
                for q in parse_event(event, now, tag, self.max_markets_per_event):
                    if q.market_id not in seen:  # an event can carry several tags; first one wins
                        seen.add(q.market_id)
                        out.append(q)
        return out

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=60, headers={"User-Agent": "spectre-signals/0.1"}) as client:
            while not stop.is_set():
                try:
                    for q in await self.fetch(client):
                        await emit(q)
                except Exception as exc:
                    log.warning("polymarket: %s: %s", type(exc).__name__, exc)
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
