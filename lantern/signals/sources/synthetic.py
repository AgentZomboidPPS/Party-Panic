"""Synthetic social stream and prediction markets tied to the demo universe.

Posts are generated with a configurable, small relationship to *next-day* returns (the "edge"),
narratives whose intensity waxes and wanes (the topic bubbles), a bot population that bursts
and duplicates (for the screener), and fear vocabulary on down days (the fear index).
Because the edge is known, the backtester can be checked against it.
"""

from __future__ import annotations

import asyncio
import math
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

import numpy as np
import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.models import Price, Security
from lantern.signals.aggregate import build_sentiment_bars, build_topics
from lantern.signals.sources.base import Emit, MarketQuote, Post, sleep_or_stop, utcnow

POS = [
    "{t} looking strong into earnings, loading calls here",
    "Bullish on {t}, clean breakout above resistance and volume confirms",
    "{name} guidance was excellent, this rally has legs",
    "{t} is undervalued at these levels, buying the dip",
    "Upgrade on {t} this morning, momentum is back",
    "{name} buyback announcement, management clearly thinks it's cheap",
    "{t} ripping, shorts getting squeezed",
]
NEG = [
    "{t} is tanking, guidance miss and a downgrade incoming",
    "Bearish {t}, this looks like a selloff with more to come",
    "Dumping my {t} position, overvalued and the chart just broke",
    "{name} layoffs announced, not a good sign for growth",
    "{t} puts printing, this crash is not over",
    "{name} missed on revenue, margins compressing, avoid",
    "{t} dilution again, bagholders everywhere",
]
NEU = [
    "What does everyone think about {t} at these levels?",
    "{name} earnings next week, any expectations?",
    "Anyone following {t} options flow today?",
    "Adding {t} to the watchlist, waiting for a setup",
]
NARRATIVES = [
    ("recession fears", ["Recession fears are back, jobless claims jumped and the yield curve is screaming",
                         "Soft landing talk is dead, recession odds climbing fast", "Consumer is tapped out, recession coming"], -0.6),
    ("rate cuts", ["Rate cut hopes rising after a soft CPI print, risk assets love it",
                   "Fed pivot is here, cuts are coming and bonds are ripping", "Dovish Fed minutes, rate cut odds jumped"], 0.5),
    ("ai chips", ["AI chip demand is insane, semis leading the market again",
                  "Data center capex keeps climbing, chip names are the picks and shovels", "Nova semiconductors printing money on AI demand"], 0.6),
    ("oil spike", ["Oil spiking on supply fears, energy names ripping", "Crude above 90 again, inflation worries creeping back",
                   "OPEC cut headlines, Ridgeline Energy breaking out"], -0.1),
    ("tariffs", ["Tariff headlines again, trade war risk for industrials and autos",
                 "New tariffs on imports, supply chain costs going up for everyone", "Rheinmotor AG hit by tariff fears, autos down hard"], -0.5),
    ("bank stress", ["Regional bank stress, deposit flight talk is back", "Meridian Bancorp credit losses rising, bank stocks under pressure",
                     "Bank run fears spreading on social media, panic in financials"], -0.7),
    ("housing", ["Housing market slowing, mortgage rates too high for buyers", "Home sales collapsing, housing crisis talk everywhere",
                 "Builders cutting prices, housing slump deepening"], -0.4),
    ("earnings season", ["Earnings season kicking off, expectations are high", "Big tech earnings this week, market holding its breath",
                         "Beat and raise quarter for most names so far, bullish"], 0.2),
]
BOT_TEMPLATES = [
    "🚀🚀 ${t} TO THE MOON!!! BUY NOW BEFORE IT'S TOO LATE 🚀🚀 ${t} ${t} ${t}",
    "💎🙌 ${t} is the next 100x gem!!! join our group link in bio 💎🙌",
]
MARKETS = [
    ("FED-CUT", "Fed cuts rates at the next FOMC meeting", "Economics", 0.55),
    ("RECESSION-12M", "US recession begins within 12 months", "Economics", 0.30),
    ("SPX-UP-YEAR", "S&P 500 closes the year higher than it opened", "Finance", 0.62),
    ("CPI-ABOVE-3", "Next CPI print above 3.0% year over year", "Economics", 0.42),
]


@dataclass
class SecInfo:
    ticker: str
    name: str
    sector: str


class SyntheticGenerator:
    def __init__(self, securities: list[SecInfo], seed: int = 11, n_authors: int = 400, bot_share: float = 0.05, ic: float = 0.08):
        self.rng = np.random.default_rng(seed)
        self.secs = securities
        self.ic = ic
        self.authors = [f"user{i:04d}" for i in range(n_authors)]
        n_bots = int(n_authors * bot_share)
        self.bots = self.authors[:n_bots]
        self.humans = self.authors[n_bots:]
        self.attention = np.array([2.0 if s.sector == "Technology" else 0.6 if s.sector in ("Government", "Corporate IG", "Corporate HY") else 1.0 for s in securities])
        self.attention /= self.attention.sum()
        self.phases = self.rng.uniform(0, 2 * math.pi, len(NARRATIVES))
        self.markets = {mid: p0 for mid, _, _, p0 in MARKETS}
        self._counter = 0

    def _id(self) -> str:
        self._counter += 1
        return f"syn-{self._counter:09d}"

    def _mention(self, s: SecInfo) -> tuple[str, str]:
        if self.rng.random() < 0.6:
            return f"${s.ticker}", s.name
        return s.name.split()[0] if self.rng.random() < 0.5 else s.name, s.name

    def narrative_intensity(self, day_index: int) -> np.ndarray:
        base = 0.5 + 0.5 * np.sin(2 * math.pi * day_index / 90 + self.phases)
        burst = (self.rng.random(len(NARRATIVES)) < 0.04) * 3.0
        return np.clip(base + burst, 0.05, None)

    def posts_for_day(self, day: date, n: int, fwd_z: dict[str, float] | None, market_mood: float, day_index: int = 0,
                      spike_ticker: str | None = None) -> list[Post]:
        out: list[Post] = []
        n_ticker = int(n * 0.6)
        weights = self.attention.copy()
        if spike_ticker:
            i = next((k for k, s in enumerate(self.secs) if s.ticker == spike_ticker), None)
            if i is not None:
                weights[i] *= 5
                weights /= weights.sum()
        for _ in range(n_ticker):
            s = self.secs[self.rng.choice(len(self.secs), p=weights)]
            tilt = 3.0 * self.ic * (fwd_z or {}).get(s.ticker, 0.0) + 0.5 * market_mood
            p_pos = 1 / (1 + math.exp(-2 * tilt))
            u = self.rng.random()
            tpl = NEU if self.rng.random() < 0.2 else (POS if u < p_pos else NEG)
            mention, name = self._mention(s)
            text = self.rng.choice(tpl).format(t=mention, name=name)
            out.append(self._post(day, text, self.rng.choice(self.humans)))
        inten = self.narrative_intensity(day_index)
        probs = inten / inten.sum()
        for _ in range(n - n_ticker):
            k = self.rng.choice(len(NARRATIVES), p=probs)
            _, lines, _ = NARRATIVES[k]
            text = str(self.rng.choice(lines))
            if market_mood < -1.0 and self.rng.random() < 0.5:
                text += " Honestly scared of a crash here."
            out.append(self._post(day, text, self.rng.choice(self.humans)))
        # Bots: bursts of duplicated pump posts, and one coordinated campaign.
        for bot in self.bots:
            if self.rng.random() < 0.15:
                s = self.secs[self.rng.choice(len(self.secs), p=weights)]
                text = str(self.rng.choice(BOT_TEMPLATES)).format(t=s.ticker)
                t0 = datetime.combine(day, time(14, 0)) + timedelta(minutes=int(self.rng.integers(0, 400)))
                for j in range(int(self.rng.integers(5, 10))):
                    out.append(Post("synthetic", self._id(), bot, text, t0 + timedelta(seconds=40 * j), "en",
                                    followers=int(self.rng.integers(0, 3)), account_age_days=float(self.rng.integers(1, 20))))
        if len(self.bots) >= 6:
            s = self.secs[self.rng.choice(len(self.secs))]
            text = f"${s.ticker} breaking news!!! insiders buying, massive move coming, get in now ${s.ticker}"
            t0 = datetime.combine(day, time(16, 30))
            for j, bot in enumerate(self.bots[:8]):
                out.append(Post("synthetic", self._id(), bot, text, t0 + timedelta(seconds=90 * j), "en", followers=1, account_age_days=3.0))
        return out

    def _post(self, day: date, text: str, author: str) -> Post:
        ts = datetime.combine(day, time(13, 0)) + timedelta(seconds=int(self.rng.integers(0, 8 * 3600)))
        return Post("synthetic", self._id(), author, text, ts, "en",
                    followers=int(self.rng.integers(5, 5000)), account_age_days=float(self.rng.integers(60, 4000)))

    def quotes(self, at: datetime, mood: float = 0.0) -> list[MarketQuote]:
        out = []
        for mid, title, cat, p0 in MARKETS:
            p = self.markets[mid]
            p += 0.1 * (p0 - p) + self.rng.normal(0, 0.02) + (0.01 * mood if mid == "SPX-UP-YEAR" else -0.01 * mood if mid == "RECESSION-12M" else 0)
            self.markets[mid] = float(np.clip(p, 0.02, 0.98))
            out.append(MarketQuote("synthetic", mid, title, self.markets[mid], at, cat,
                                   volume=float(self.rng.integers(50_000, 2_000_000)), open_interest=float(self.rng.integers(10_000, 500_000)),
                                   close_time=at + timedelta(days=60)))
        return out


def _securities(session: Session) -> list[SecInfo]:
    return [SecInfo(t, n, s or "") for t, n, s in session.execute(select(Security.ticker, Security.name, Security.sector).order_by(Security.id)).all()]


def seed_social_history(session: Session, days: int = 365, posts_per_day: int = 80, seed: int = 11, ic: float = 0.03,
                        end: date | None = None, build_aggregates: bool = True) -> dict:
    """Generate `days` of daily posts aligned to the demo price history, run them through the
    pipeline, and build daily topic bubbles and sentiment bars."""
    from lantern.signals.pipeline import Pipeline

    secs = _securities(session)
    tickers = [s.ticker for s in secs]
    sec_ids = dict(session.execute(select(Security.ticker, Security.id)).all())
    rows = session.execute(select(Price.security_id, Price.date, Price.close).where(Price.security_id.in_(list(sec_ids.values())))).all()
    px = pd.DataFrame(rows, columns=["security_id", "date", "close"]).pivot(index="date", columns="security_id", values="close").sort_index()
    px.columns = [next(t for t, i in sec_ids.items() if i == c) for c in px.columns]
    rets = px.pct_change()
    fwd = rets.shift(-1)  # tomorrow's return, known to the generator only
    end = end or px.index.max()
    trading_days = [d for d in px.index if d <= end][-days:]
    mkt = rets.mean(axis=1)
    mkt_z = (mkt - mkt.mean()) / mkt.std()

    gen = SyntheticGenerator(secs, seed=seed, ic=ic)
    pipe = Pipeline(session_factory=lambda: _NonClosingSession(session))  # type: ignore[arg-type]
    total = 0
    for i, d in enumerate(trading_days):
        row = fwd.loc[d] if d in fwd.index else None
        fwd_z = {}
        if row is not None and row.notna().any():
            z = (row - row.mean()) / (row.std() or 1.0)
            fwd_z = {t: float(z[t]) for t in tickers if t in z.index and not np.isnan(z[t])}
        spike = str(gen.rng.choice(tickers)) if gen.rng.random() < 0.15 else None
        posts = gen.posts_for_day(d, posts_per_day, fwd_z, float(mkt_z.get(d, 0.0)), day_index=i, spike_ticker=spike)
        total += pipe.process_posts(posts)
        pipe.process_quotes(gen.quotes(datetime.combine(d, time(21, 0)), float(mkt_z.get(d, 0.0))))
        if build_aggregates:
            ws = datetime.combine(d, time.min)
            we = ws + timedelta(days=1)
            build_topics(session, ws, we, max_topics=10)
            build_sentiment_bars(session, ws, we)
    session.commit()
    return {"days": len(trading_days), "posts": total, "screened_out": pipe.counters["screened_out"],
            "start": trading_days[0].isoformat(), "end": trading_days[-1].isoformat()}


class _NonClosingSession:
    """Lets the pipeline reuse one session (it normally opens one per batch)."""

    def __init__(self, session: Session):
        self._s = session

    def __call__(self):
        return self

    def __enter__(self):
        return self._s

    def __exit__(self, *exc):
        return False


class SyntheticLiveSource:
    """Emits a realistic-looking live stream: ~`rate` posts per second plus market quotes."""

    name = "synthetic"

    def __init__(self, session_factory=None, rate: float = 3.0, seed: int | None = None, quote_seconds: float = 30.0):
        self.rate = rate
        self.quote_seconds = quote_seconds
        self.seed = seed if seed is not None else int(datetime.now().timestamp()) % 100_000
        self._session_factory = session_factory

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        if self._session_factory is not None:
            with self._session_factory() as s:
                secs = _securities(s)
        else:
            secs = [SecInfo("ACME", "Acme Systems", "Technology"), SecInfo("BANK", "Meridian Bancorp", "Financials")]
        gen = SyntheticGenerator(secs, seed=self.seed)
        gen._counter = int(datetime.now().timestamp() * 1000) % 10**9
        day_index = 0
        last_quote = 0.0
        mood = float(gen.rng.normal(0, 1))
        while not stop.is_set():
            now = utcnow()
            n = max(1, int(gen.rng.poisson(self.rate)))
            posts = gen.posts_for_day(now.date(), n, None, mood, day_index=day_index)
            for p in posts[:n]:  # bots are included in proportion
                p.created_at = now + timedelta(milliseconds=int(gen.rng.integers(0, 900)))
                await emit(p)
            if asyncio.get_running_loop().time() - last_quote >= self.quote_seconds:
                for q in gen.quotes(now, mood):
                    await emit(q)
                last_quote = asyncio.get_running_loop().time()
            mood = 0.98 * mood + float(gen.rng.normal(0, 0.1))
            day_index += 1
            if await sleep_or_stop(1.0, stop):
                return
