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

Where the scores come from: once KAIROS is running it writes its score for every name down at
each decision (`record_readings`), and those are used as they were. For the time before the
first written one the score is worked out again from the posts still kept, which is close but
slightly kind to the signal, because today's sentiment model has since read later posts.

Moments ten minutes apart are not independent: they share most of their posts and most of
their following hour. So the count that matters is the number of separate windows, roughly
the hours of data divided by the horizon, and no conclusion is offered below 30 of them. A day
of data is a look, not a result.
"""

from __future__ import annotations

import bisect
import math
from datetime import datetime, timedelta
from statistics import NormalDist

import pandas as pd
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from spectre.signals.models import SignalReading, SocialPost
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


def readings(session: Session, start: datetime, end: datetime, step: int = 10, lookback: int = 45, min_authors: int = 8,
             asset_classes: tuple[str, ...] = STOCKS) -> list[tuple[datetime, str, float, int]]:
    """KAIROS's own score for each name at each decision moment up to `end`: (moment, name, score, authors)."""
    out = []
    t = start + timedelta(minutes=lookback)
    while t <= end:
        for sig in live_signals(session, lookback, min_posts=5, min_authors=min_authors, at=t):
            if sig.asset_class in asset_classes:
                out.append((t, sig.ticker, sig.score, sig.n_authors))
        t += timedelta(minutes=step)
    return out


def record_readings(session: Session, lookback: int = 45, min_authors: int = 8, at: datetime | None = None) -> int:
    """Write down the score for every name as it stands now, exactly as the bot is reading it.
    Called once per decision cycle. Returns how many were written."""
    from spectre.signals.sources.base import utcnow

    at = (at or utcnow()).replace(microsecond=0)
    if session.execute(select(func.count()).select_from(SignalReading).where(SignalReading.at == at)).scalar_one():
        return 0
    signals = live_signals(session, lookback, min_posts=5, min_authors=min_authors)
    session.add_all([SignalReading(at=at, ticker=g.ticker, asset_class=g.asset_class, score=g.score, authors=g.n_authors,
                                   posts=g.n_posts, lookback_minutes=lookback) for g in signals])
    session.commit()
    return len(signals)


def stored_readings(session: Session, start: datetime, end: datetime,
                    asset_classes: tuple[str, ...] = STOCKS) -> list[tuple[datetime, str, float, int]]:
    """The scores written down at the time between `start` and `end`, oldest first."""
    rows = session.execute(
        select(SignalReading.at, SignalReading.ticker, SignalReading.score, SignalReading.authors)
        .where(SignalReading.at >= start, SignalReading.at <= end, SignalReading.asset_class.in_(asset_classes))
        .order_by(SignalReading.at, SignalReading.ticker)).all()
    return [(at, ticker, score, authors) for at, ticker, score, authors in rows]


def collect(session: Session, prices: PricePath, start: datetime, end: datetime, step: int = 10, lookback: int = 45,
            min_authors: int = 8, horizon: int = 60, asset_classes: tuple[str, ...] = STOCKS,
            scored: list[tuple[datetime, str, float, int]] | None = None) -> pd.DataFrame:
    """One row per (moment, name): the score then and the return over the following `horizon` minutes.
    `scored` takes readings already computed, so several horizons can share them."""
    ahead = timedelta(minutes=horizon)
    if scored is None:
        scored = readings(session, start, end - ahead, step, lookback, min_authors, asset_classes)
    rows = []
    for t, ticker, score, authors in scored:
        if t + ahead > end:
            continue
        before, after = prices.at(ticker, t), prices.at(ticker, t + ahead)
        if before and after:
            rows.append({"at": t, "ticker": ticker, "score": score, "authors": authors, "fwd": after / before - 1})
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


class _Span:
    """What there is to measure: the scores, moment by moment, and prices for the names in them."""

    def __init__(self, prices: PricePath, start: datetime, end: datetime, scored: list, recorded: int):
        self.prices, self.start, self.end, self.scored, self.recorded = prices, start, end, scored, recorded

    def counts(self, df: pd.DataFrame) -> dict:
        return {"readings_written_at_the_time": self.recorded, "readings_worked_out_again": len(self.scored) - self.recorded}


def _load(session: Session, client, days: float, step: int, lookback: int, min_authors: int, asset_classes: tuple[str, ...],
          now: datetime | None) -> _Span | None:
    """The scores over the last `days` and five-minute prices from Alpaca for the names in them.
    None when there is nothing to score."""
    from spectre.models import Security
    from spectre.signals.sources.base import utcnow

    end = now or utcnow()
    since = end - timedelta(days=days)
    written = stored_readings(session, since, end, asset_classes)
    scored: list[tuple[datetime, str, float, int]] = []
    start = written[0][0] - timedelta(minutes=30) if written else end
    first = session.execute(select(func.min(SocialPost.posted_at)).where(SocialPost.posted_at >= since)).scalar_one_or_none()
    if first is not None:
        # Before the first score written at the time, work it out again from the posts.
        begin = first.replace(second=0, microsecond=0)
        begin += timedelta(minutes=(-begin.minute) % step)  # onto the clock: :00, :10, :20 ...
        # No read is possible once the last post has aged out of the lookback, so stop there.
        last = session.execute(select(func.max(SocialPost.posted_at))).scalar_one()
        upto = min(end, last + timedelta(minutes=lookback))
        if written:
            upto = min(upto, written[0][0] - timedelta(minutes=step))
        scored = readings(session, begin, upto, step, lookback, min_authors, asset_classes)
        start = min(start, begin)
    scored += written
    if not scored:
        return None
    names = {ticker for _, ticker, _, _ in scored}
    kinds = dict(session.execute(select(Security.ticker, Security.asset_class).where(Security.ticker.in_(names))).all())
    coins = sorted(n for n in names if kinds.get(n) == "Crypto")
    stocks = sorted(names - set(coins))
    bars: dict[str, list[tuple[datetime, float]]] = {}
    if stocks:
        bars.update(client.stock_bars(stocks, start, timeframe="5Min", adjustment="raw"))
    if coins:
        bars.update(client.crypto_bars(coins, start, timeframe="5Min"))
    return _Span(PricePath(bars), start, end, scored, len(written))


_EMPTY = ["at", "ticker", "score", "authors", "fwd", "rel"]


def check(session: Session, client, days: float = 30.0, horizon: int = 60, step: int = 10, lookback: int = 45,
          min_authors: int = 8, enter: float = 0.2, top_n: int = 5, asset_classes: tuple[str, ...] = STOCKS,
          now: datetime | None = None) -> dict:
    """Measure the signal over the last `days` against five-minute prices from Alpaca."""
    span = _load(session, client, days, step, lookback, min_authors, asset_classes, now)
    if span is None:
        return summarise(pd.DataFrame(columns=_EMPTY), horizon, lookback, enter, top_n)
    df = collect(session, span.prices, span.start, span.end, step, lookback, min_authors, horizon, asset_classes, scored=span.scored)
    return summarise(df, horizon, lookback, enter, top_n) | span.counts(df)


HORIZONS = (30, 60, 120, 240)
# Coins trade round the clock and cost far more to get in and out of, so what matters is whether
# the read still says anything hours later.
COIN_HORIZONS = (60, 240, 720, 1440)


def round_trip_cost(crypto: bool) -> float:
    """Roughly what one trip in and out costs. Coins: Alpaca's 0.25% fee each way plus a little
    for the gap between buying and selling prices. Stocks: no commission, so only that gap,
    which for the large names talked about here is a few hundredths of a percent."""
    return 0.006 if crypto else 0.0005


def bar_for(looks: int) -> float:
    """How large t has to be when `looks` horizons were examined. Looking at several and keeping
    the best one finds "something" by luck more often, so each has to clear a higher bar: the
    usual one-in-twenty chance of a fluke is shared out between them."""
    return NormalDist().inv_cdf(1 - 0.025 / max(1, looks))


def sweep(session: Session, client, horizons: tuple[int, ...] = HORIZONS, days: float = 30.0, step: int = 10, lookback: int = 45,
          min_authors: int = 8, enter: float = 0.2, top_n: int = 5, asset_classes: tuple[str, ...] = STOCKS,
          round_trip_cost: float = 0.0, now: datetime | None = None) -> dict:
    """The same measurement at several horizons, from one fetch of prices and one pass over the
    posts: how far ahead, if at all, does the crowd read say anything?

    `round_trip_cost` is what it costs to get in and out once (fees and the gap between buying
    and selling prices), as a fraction; an edge smaller than that is not worth trading at that
    horizon however real it is."""
    horizons = tuple(sorted(set(horizons)))
    bar = bar_for(len(horizons))
    span = _load(session, client, days, step, lookback, min_authors, asset_classes, now)
    rows = []
    if span is not None:
        for horizon in horizons:
            r = summarise(collect(session, span.prices, span.start, span.end, step, lookback, min_authors, horizon, asset_classes,
                                  scored=span.scored), horizon, lookback, enter, top_n)
            if not r["samples"]:
                rows.append({"horizon_minutes": horizon, "samples": 0, "windows": 0, "enough": False})
                continue
            edge, t = r["held"]["mean_edge"], r["held"]["t_stat"]
            rows.append({
                "horizon_minutes": horizon, "samples": r["samples"], "moments": r["moments"], "windows": r["windows"], "names": r["names"],
                "enough": r["windows"] >= ENOUGH_WINDOWS, "rank_agreement": r["rank_agreement"]["mean"], "rank_t": r["rank_agreement"]["t_stat"],
                "edge": edge, "edge_t": t, "edge_share_positive": r["held"]["share_positive"],
                "edge_after_costs": None if edge is None else edge - round_trip_cost,
                "clears_the_bar": bool(r["windows"] >= ENOUGH_WINDOWS and t is not None and abs(t) >= bar),
            })
    measured = [r for r in rows if r["samples"]]
    ready = [r for r in measured if r["enough"]]
    good = [r for r in ready if r["clears_the_bar"] and r["edge"] > 0]
    bad = [r for r in ready if r["clears_the_bar"] and r["edge"] < 0]
    worth = [r for r in good if r["edge_after_costs"] > 0]
    if not measured:
        verdict = "No usable data yet: no moment has both a crowd read and prices before and after it."
    elif not ready:
        most = max(r["windows"] for r in measured)
        verdict = (f"Too little data at every horizon: the most is {most} separate window{'s' if most != 1 else ''}, and nothing below "
                   f"{ENOUGH_WINDOWS} deserves a conclusion. Keep collecting.")
    elif worth:
        best = max(worth, key=lambda r: r["edge_t"])
        verdict = (f"Looking {best['horizon_minutes']} minutes ahead, the names KAIROS would have held beat the rest by more than chance "
                   f"explains, even after allowing for having looked at {len(horizons)} horizons"
                   + (", and by more than it costs to trade." if round_trip_cost else "."))
    elif good:
        best = max(good, key=lambda r: r["edge_t"])
        verdict = (f"Looking {best['horizon_minutes']} minutes ahead the edge looks real, but it is smaller than the cost of getting in "
                   "and out, so it is not worth trading on its own.")
    elif bad:
        worst = min(bad, key=lambda r: r["edge_t"])
        verdict = (f"Looking {worst['horizon_minutes']} minutes ahead, the names KAIROS would have held did worse than the rest by more "
                   "than chance explains. The signal as built is pointing the wrong way there.")
    else:
        verdict = "At no horizon with enough data is there a reliable relation between the crowd read and what prices did next."
    return {"horizons": rows, "bar": bar, "looks": len(horizons), "round_trip_cost": round_trip_cost, "entry_score": enter, "top_n": top_n,
            "lookback_minutes": lookback, "enough_windows": ENOUGH_WINDOWS, "verdict": verdict,
            **(span.counts(None) if span is not None else {})}
