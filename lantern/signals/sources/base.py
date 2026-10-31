from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Protocol


def utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def to_naive_utc(dt: datetime) -> datetime:
    if dt.tzinfo is not None:
        dt = dt.astimezone(UTC).replace(tzinfo=None)
    return dt


@dataclass
class Post:
    source: str
    external_id: str
    author_id: str  # raw platform id; hashed before anything is stored
    text: str
    created_at: datetime
    lang: str | None = None
    url: str | None = None
    followers: int | None = None
    account_age_days: float | None = None
    source_sentiment: str | None = None  # e.g. Stocktwits "Bullish"/"Bearish"
    meta: dict = field(default_factory=dict)


@dataclass
class MarketQuote:
    source: str
    market_id: str
    title: str
    yes_price: float  # 0..1
    observed_at: datetime
    category: str | None = None
    volume: float | None = None
    open_interest: float | None = None
    close_time: datetime | None = None


Emit = Callable[[Post | MarketQuote], Awaitable[None]]


class Source(Protocol):
    name: str

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        """Produce items until `stop` is set. Must return promptly after stop."""
        ...


async def sleep_or_stop(seconds: float, stop: asyncio.Event) -> bool:
    """Sleep, returning True if `stop` was set during the wait."""
    try:
        await asyncio.wait_for(stop.wait(), timeout=seconds)
        return True
    except TimeoutError:
        return False
