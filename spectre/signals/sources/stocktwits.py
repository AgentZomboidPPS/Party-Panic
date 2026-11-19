"""Stocktwits: the trending stream (one request, messages across many symbols) and per-symbol
streams. Messages carry an optional user-declared Bullish/Bearish label, which is the ground
truth used to calibrate the sentiment model.

The unauthenticated API allows roughly 200 requests an hour, so requests are spaced out and
there are only so many streams to go round. Each round they are spent on:
- the symbols always followed (the busiest names, and the coins);
- then whichever names in the book Stocktwits itself says are trending right now, so
  attention goes where the crowd's has gone;
- then, with what is left, the rest of the book in turn, so every name is looked at a few
  times a day and nothing is never heard from.

Verified against the live API on 2026-11-18.
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime

import httpx

from spectre.marketdata.universe import CRYPTO_TICKERS, crypto_base
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
            sym = _symbol(p.get("symbol"))
            if sym and float(p["price"]) > 0:
                prices[sym] = float(p["price"])
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
        meta={"symbols": [sym for s in (m.get("symbols") or []) if (sym := _symbol(s.get("symbol")))], "prices": prices},
    )


def _symbol(raw: str | None) -> str | None:
    """Stocktwits writes coins as "BTC.X"; SPECTRE calls the coin "BTC". A plain "BTC" here is a
    different instrument (a fund that happens to share the letters), so it is dropped rather
    than have its price recorded as the coin's."""
    if not raw:
        return None
    coin = crypto_base(raw)
    if coin:
        return coin
    return None if raw.upper() in CRYPTO_TICKERS else raw


class StocktwitsSource:
    name = "stocktwits"

    def __init__(
        self,
        symbols: list[str] | None = None,
        trending: bool = True,
        poll_seconds: float = 120,
        request_gap_seconds: float = 20,
        universe: list[str] | None = None,
        extra_per_round: int = 5,
    ):
        self.symbols = list(symbols or [])
        self.trending = trending
        self.poll_seconds = poll_seconds
        self.request_gap_seconds = request_gap_seconds
        # Every other name in the book: followed when trending, otherwise in turn.
        self.others = [s for s in dict.fromkeys(universe or []) if s not in self.symbols]
        self.extra_per_round = extra_per_round
        self.hot: list[str] = []  # names in the book that Stocktwits lists as trending now
        self._turn = 0
        self._since: dict[str, int] = {}

    async def _trending_symbols(self, client: httpx.AsyncClient) -> list[str]:
        """The symbols Stocktwits lists as trending now, as SPECTRE names them."""
        r = await client.get(f"{BASE}/trending/symbols.json")
        r.raise_for_status()
        return [sym for s in r.json().get("symbols", []) if (sym := _symbol(s.get("symbol")))]

    def extras(self, trending: list[str]) -> list[str]:
        """This round's streams beyond the always-followed ones: the book's trending names
        first (taking turns if there are more than fit), then the rest of the book in turn."""
        if not self.others or self.extra_per_round <= 0:
            return []
        pool = set(self.others)
        self.hot = [s for s in dict.fromkeys(trending) if s in pool]
        start = self._turn
        self._turn += 1
        hot = [self.hot[(start + i) % len(self.hot)] for i in range(min(len(self.hot), self.extra_per_round))]
        rest = [s for s in self.others if s not in self.hot]
        spare = self.extra_per_round - len(hot)
        offset = (start * spare) % len(rest) if rest and spare > 0 else 0
        return hot + [rest[(offset + i) % len(rest)] for i in range(min(spare, len(rest)))]

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
        base = ([("streams/trending.json", "__trending__")] if self.trending else []) + [
            (f"streams/symbol/{s}.json", s) for s in self.symbols
        ]
        async with httpx.AsyncClient(timeout=30, headers={"User-Agent": "spectre-signals/0.1"}) as client:
            while not stop.is_set():
                trending: list[str] = []
                if self.others:
                    try:
                        trending = await self._trending_symbols(client)
                    except Exception as exc:
                        log.warning("stocktwits trending symbols: %s: %s", type(exc).__name__, exc)
                    if await sleep_or_stop(self.request_gap_seconds, stop):
                        return
                streams = base + [(f"streams/symbol/{s}.json", s) for s in self.extras(trending)]
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
