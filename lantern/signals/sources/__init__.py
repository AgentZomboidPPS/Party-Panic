"""Source adapters. Each yields Post or MarketQuote objects; the pipeline does the rest.

Live adapters (bluesky, reddit, stocktwits, rss, x, kalshi, polymarket) talk to public APIs
and need outbound network access. `synthetic` and `replay` work offline.
"""

from __future__ import annotations

from lantern.signals.sources.base import MarketQuote, Post, Source


def build(name: str, **kwargs) -> Source:
    """Construct a source by name. Keyword arguments are passed to the adapter."""
    name = name.lower()
    if name == "synthetic":
        from lantern.signals.sources.synthetic import SyntheticLiveSource

        return SyntheticLiveSource(**kwargs)
    if name == "replay":
        from lantern.signals.sources.replay import ReplaySource

        return ReplaySource(**kwargs)
    if name == "bluesky":
        from lantern.signals.sources.bluesky import BlueskyJetstream

        return BlueskyJetstream(**kwargs)
    if name == "reddit":
        from lantern.signals.sources.reddit import RedditSource

        return RedditSource(**kwargs)
    if name == "stocktwits":
        from lantern.signals.sources.stocktwits import StocktwitsSource

        return StocktwitsSource(**kwargs)
    if name == "rss":
        from lantern.signals.sources.rss import RssSource

        return RssSource(**kwargs)
    if name == "x":
        from lantern.signals.sources.x import XRecentSearch

        return XRecentSearch(**kwargs)
    if name == "kalshi":
        from lantern.signals.sources.kalshi import KalshiSource

        return KalshiSource(**kwargs)
    if name == "polymarket":
        from lantern.signals.sources.polymarket import PolymarketSource

        return PolymarketSource(**kwargs)
    raise ValueError(f"Unknown source {name!r}")


__all__ = ["MarketQuote", "Post", "Source", "build"]
