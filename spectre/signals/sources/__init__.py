"""Source adapters. Each yields Post, MarketQuote or TrendItem objects; the pipeline does the rest.

Verified live: bluesky, stocktwits, kalshi, polymarket, trends. Written to the documented API
but not verified: reddit (refuses unauthenticated servers), x (needs a paid token), rss (bring
your own feed URLs). `synthetic` and `replay` work offline.
"""

from __future__ import annotations

from spectre.signals.sources.base import MarketQuote, Post, Source, TrendItem


def build(name: str, **kwargs) -> Source:
    """Construct a source by name. Keyword arguments are passed to the adapter."""
    name = name.lower()
    if name == "synthetic":
        from spectre.signals.sources.synthetic import SyntheticLiveSource

        return SyntheticLiveSource(**kwargs)
    if name == "replay":
        from spectre.signals.sources.replay import ReplaySource

        return ReplaySource(**kwargs)
    if name == "bluesky":
        from spectre.signals.sources.bluesky import BlueskyJetstream

        return BlueskyJetstream(**kwargs)
    if name == "reddit":
        from spectre.signals.sources.reddit import RedditSource

        return RedditSource(**kwargs)
    if name == "stocktwits":
        from spectre.signals.sources.stocktwits import StocktwitsSource

        return StocktwitsSource(**kwargs)
    if name == "rss":
        from spectre.signals.sources.rss import RssSource

        return RssSource(**kwargs)
    if name == "x":
        from spectre.signals.sources.x import XRecentSearch

        return XRecentSearch(**kwargs)
    if name == "kalshi":
        from spectre.signals.sources.kalshi import KalshiSource

        return KalshiSource(**kwargs)
    if name == "polymarket":
        from spectre.signals.sources.polymarket import PolymarketSource

        return PolymarketSource(**kwargs)
    if name in ("trends", "google_trends"):
        from spectre.signals.sources.trends import GoogleTrendsSource

        return GoogleTrendsSource(**kwargs)
    raise ValueError(f"Unknown source {name!r}")


__all__ = ["MarketQuote", "Post", "Source", "TrendItem", "build"]
