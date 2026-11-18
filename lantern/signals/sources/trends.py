"""Google Trends: the public "trending now" RSS feed, per country.

Each item is a search term that is spiking, with an approximate search count and the news
headlines Google attaches to it. This is attention data: there is no text to score and no
author, so items are stored as trends rather than posts.

What this does not provide: interest-over-time for a keyword of your choosing. Google has no
open API for that; the unofficial endpoints answer servers with HTTP 429 (they did here on the
first request), so that needs Google's own Trends API access or a paid provider.

Verified against the live feed on 2026-11-18.
"""

from __future__ import annotations

import asyncio
import logging
import re
import xml.etree.ElementTree as ET
from datetime import datetime
from email.utils import parsedate_to_datetime

import httpx

from lantern.signals.sources.base import Emit, TrendItem, sleep_or_stop, to_naive_utc, utcnow

log = logging.getLogger(__name__)

URL = "https://trends.google.com/trending/rss"
HT = "{https://trends.google.com/trending/rss}"
MAX_BYTES = 2_000_000
_TRAFFIC = re.compile(r"([\d.,]+)\s*([KMB]?)", re.IGNORECASE)


def parse_traffic(s: str | None) -> int | None:
    """'5000+' -> 5000, '200K+' -> 200000, '2M+' -> 2000000."""
    if not s:
        return None
    m = _TRAFFIC.search(s)
    if not m:
        return None
    try:
        n = float(m.group(1).replace(",", ""))
    except ValueError:
        return None
    return int(n * {"": 1, "K": 1_000, "M": 1_000_000, "B": 1_000_000_000}[m.group(2).upper()])


def parse_trends_rss(xml_text: str, geo: str, observed_at: datetime) -> list[TrendItem]:
    # The feed is plain RSS. Refuse anything with a DTD (entity-expansion tricks) or absurd size.
    if len(xml_text) > MAX_BYTES or "<!DOCTYPE" in xml_text or "<!ENTITY" in xml_text:
        raise ValueError("unexpected trends feed content")
    root = ET.fromstring(xml_text)
    out: list[TrendItem] = []
    for item in root.iter("item"):
        term = (item.findtext("title") or "").strip()
        if not term:
            continue
        started = None
        pub = item.findtext("pubDate")
        if pub:
            try:
                started = to_naive_utc(parsedate_to_datetime(pub))
            except (TypeError, ValueError):
                started = None
        headlines = [
            (n.findtext(f"{HT}news_item_title") or "").strip()
            for n in item.findall(f"{HT}news_item")
        ]
        out.append(
            TrendItem(
                source="google_trends",
                geo=geo,
                term=term,
                observed_at=observed_at,
                started_at=started,
                approx_traffic=parse_traffic(item.findtext(f"{HT}approx_traffic")),
                headlines=[h for h in headlines if h][:5],
            )
        )
    return out


class GoogleTrendsSource:
    name = "trends"

    def __init__(self, geos: tuple[str, ...] = ("US",), poll_seconds: float = 600):
        self.geos = tuple(geos)
        self.poll_seconds = poll_seconds

    async def fetch(self, client: httpx.AsyncClient) -> list[TrendItem]:
        out: list[TrendItem] = []
        for geo in self.geos:
            r = await client.get(URL, params={"geo": geo})
            r.raise_for_status()
            out.extend(parse_trends_rss(r.text, geo, utcnow()))
        return out

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        async with httpx.AsyncClient(timeout=30, headers={"User-Agent": "lantern-signals/0.1"}) as client:
            while not stop.is_set():
                try:
                    for item in await self.fetch(client):
                        await emit(item)
                except Exception as exc:
                    log.warning("trends: %s: %s", type(exc).__name__, exc)
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
