"""Does the crowd read predict what the price does next? Measured, not assumed.

For every past decision moment (every `step` minutes) this asks two things:
- what did KAIROS's own score say about each name then, computed exactly as the bot computes
  it, from posts up to that moment only;
- what did each name's price do over the following `horizon` minutes.

Then three views of the answer:
- **rank agreement** (information coefficient): at each moment, did the names scored higher go
  on to do better than the names scored lower? +1 is perfect, 0 is no relation, -1 is backwards;
- **by zone**: what followed for names in the buy zone, in between, and at or below zero, each
  relative to the other names at the same moment (so a rising market does not flatter it);
- **what KAIROS would have held**: the top few names in the buy zone against all the names
  it could have picked from.

Moments ten minutes apart are not independent: they share most of their posts and most of
their following hour. So the count that matters is the number of separate windows, roughly
the hours of data divided by the horizon, and no conclusion is offered below 30 of them. A day
of data is a look, not a result.
"""

from __future__ import annotations

import bisect
import math
from datetime import datetime, timedelta

import pandas as pd
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from spectre.signals.models import SocialPost
from spectre.signals.strategy import STOCKS, live_signals

ENOUGH_WINDOWS = 30


class PricePath:
    """Prices through the day from bars: the price "at" a moment is the close of the last bar
    that had finished by then, and there is none if that bar is stale (the market was shut)."""

    def __init__(self, bars: dict[str, list[tuple[datetime, float]]], bar_minutes: int = 5, stale_minutes: int = 15):
        self.closes: dict[str, tuple[list[datetime], list[float]]] = {}
        for ticker, series in bars.items():
            series = sorted(series)
            self.closes[ticker] = ([t + timedelta(minutes=bar_minutes) for t, _ in series], [c for _, c in series])
        self.stale = timedelta(minutes=stale_minutes)

    def at(self, ticker: str, when: datetime) -> float | None:
        times, closes = self.closes.get(ticker, ([], []))
        i = bisect.bisect_right(times, when) - 1
        if i < 0 or when - times[i] > self.stale:
            return None
        return closes[i]


def collect(session: Session, prices: PricePath, start: datetime, end: datetime, step: int = 10, lookback: int = 45,
            min_authors: int = 8, horizon: int = 60, asset_classes: tuple[str, ...] = STOCKS) -> pd.DataFrame:
    """One row per (moment, name): the score then and the return over the following `horizon` minutes."""
    rows = []
    t = start + timedelta(minutes=lookback)
    while t + timedelta(minutes=horizon) <= end:
        for sig in live_signals(session, lookback, min_posts=5, min_authors=min_authors, at=t):
            if sig.asset_class not in asset_classes:
                continue
            before, after = prices.at(sig.ticker, t), prices.at(sig.ticker, t + timedelta(minutes=horizon))
            if before and after:
                rows.append({"at": t, "ticker": sig.ticker, "score": sig.score, "authors": sig.n_authors, "fwd": after / before - 1})
        t += timedelta(minutes=step)
    df = pd.DataFrame(rows, columns=["at", "ticker", "score", "authors", "fwd"])
    if len(df):
        # Relative to the other names at the same moment, where there are enough to compare with.
        peers = df.groupby("at")["fwd"].transform("count")
        df["rel"] = (df["fwd"] - df.groupby("at")["fwd"].transform("mean")).where(peers >= 3)
    else:
        df["rel"] = []
    return df


def _t_stat(values: pd.Series, windows: int) -> float | None:
    """Mean over its standard error, with the sample size capped at the number of separate windows."""
    values = values.dropna()
    n = min(len(values), windows)
    if n < 3 or values.std() == 0 or math.isnan(values.std()):
        return None
    return float(values.mean() / (values.std() / math.sqrt(n)))


def summarise(df: pd.DataFrame, horizon: int = 60, lookback: int = 45, enter: float = 0.2, top_n: int = 5) -> dict:
    if df.empty:
        return {"samples": 0, "moments": 0, "windows": 0, "verdict": "No usable data yet: no moment has both a crowd read and prices before and after it."}
    span = max(horizon, lookback)
    # Separate windows, counted day by day so an overnight gap is not counted as data.
    windows = 0
    for _, day in df.groupby(df["at"].dt.date):
        minutes = (day["at"].max() - day["at"].min()).total_seconds() / 60 + 1
        windows += max(1, math.ceil(minutes / span))

    ics = df.groupby("at").apply(lambda g: g["score"].corr(g["fwd"], method="spearman") if len(g) >= 5 else float("nan"),
                                 include_groups=False).dropna()
    zones = []
    for name, part in (("buy zone (score at or above the entry level)", df[df["score"] >= enter]),
                       ("in between", df[(df["score"] > 0) & (df["score"] < enter)]),
                       ("at or below zero (would be sold)", df[df["score"] <= 0])):
        rel = part["rel"].dropna()
        zones.append({"zone": name, "samples": int(len(part)), "mean_return": float(part["fwd"].mean()) if len(part) else None,
                      "mean_relative_return": float(rel.mean()) if len(rel) else None,
                      "share_beating_the_rest": float((rel > 0).mean()) if len(rel) else None})

    def held_edge(g: pd.DataFrame) -> float:
        picks = g[g["score"] >= enter].nlargest(top_n, "score")
        return picks["fwd"].mean() - g["fwd"].mean() if len(picks) and len(g) > len(picks) else float("nan")

    edge = df.groupby("at").apply(held_edge, include_groups=False).dropna()
    ic_t, edge_t = _t_stat(ics, windows), _t_stat(edge, windows)
    if windows < ENOUGH_WINDOWS:
        verdict = (f"Too little data to say anything: {windows} separate window{'s' if windows != 1 else ''} so far, and nothing "
                   f"below {ENOUGH_WINDOWS} deserves a conclusion. Keep collecting.")
    elif edge_t is not None and edge_t >= 2 and len(ics) and ics.mean() > 0:
        verdict = "The names KAIROS would have held did better than the rest by more than chance alone explains. Worth trusting a little, and checking again as data grows."
    elif edge_t is not None and edge_t <= -2:
        verdict = "The names KAIROS would have held did worse than the rest by more than chance alone explains. The signal as built is pointing the wrong way."
    else:
        verdict = "No reliable relation between the crowd read and what prices did next. So far the signal has not shown an edge."
    return {
        "samples": int(len(df)), "moments": int(df["at"].nunique()), "windows": int(windows), "names": int(df["ticker"].nunique()),
        "from": df["at"].min().isoformat(timespec="minutes"), "to": df["at"].max().isoformat(timespec="minutes"),
        "horizon_minutes": horizon, "lookback_minutes": lookback, "entry_score": enter,
        "rank_agreement": {"moments": int(len(ics)), "mean": float(ics.mean()) if len(ics) else None,
                           "share_positive": float((ics > 0).mean()) if len(ics) else None, "t_stat": ic_t},
        "zones": zones,
        "held": {"moments": int(len(edge)), "mean_edge": float(edge.mean()) if len(edge) else None,
                 "share_positive": float((edge > 0).mean()) if len(edge) else None, "t_stat": edge_t, "top_n": top_n},
        "verdict": verdict,
    }


def check(session: Session, client, days: float = 5.0, horizon: int = 60, step: int = 10, lookback: int = 45,
          min_authors: int = 8, enter: float = 0.2, top_n: int = 5, asset_classes: tuple[str, ...] = STOCKS,
          now: datetime | None = None) -> dict:
    """Fetch five-minute prices from Alpaca for the names the crowd has talked about and measure
    the signal over the last `days`."""
    from spectre.models import Security
    from spectre.signals.sources.base import utcnow

    end = now or utcnow()
    first = session.execute(select(func.min(SocialPost.posted_at)).where(SocialPost.posted_at >= end - timedelta(days=days))).scalar_one_or_none()
    if first is None:
        return summarise(pd.DataFrame(columns=["at", "ticker", "score", "authors", "fwd", "rel"]), horizon, lookback, enter, top_n)
    start = first.replace(second=0, microsecond=0)
    start += timedelta(minutes=(-start.minute) % step)  # onto the clock: :00, :10, :20 ...
    # No read is possible once the last post has aged out of the lookback, so stop there.
    last = session.execute(select(func.max(SocialPost.posted_at))).scalar_one()
    end = min(end, last + timedelta(minutes=lookback + horizon))
    wanted = session.execute(select(Security.ticker, Security.asset_class).where(Security.asset_class.in_(asset_classes))).all()
    coins = sorted(t for t, kind in wanted if kind == "Crypto")
    stocks = sorted(t for t, kind in wanted if kind != "Crypto")
    bars: dict[str, list[tuple[datetime, float]]] = {}
    if stocks:
        bars.update(client.stock_bars(stocks, start, timeframe="5Min", adjustment="raw"))
    if coins:
        bars.update(client.crypto_bars(coins, start, timeframe="5Min"))
    df = collect(session, PricePath(bars), start, end, step, lookback, min_authors, horizon, asset_classes)
    return summarise(df, horizon, lookback, enter, top_n)
