"""KAIROS, the trend bot: lean into what the crowd is leaning into right now, on paper, inside hard limits.

The rule is deliberately simple and easy to audit:

1. Look at the last `lookback_minutes` of screened posts.
2. For each security, give every author one vote (their average stance), so one loud account
   cannot move the result. `net` = share of bullish authors minus share of bearish authors.
3. `score` = net x log(1 + authors): conviction weighted by how many people are talking, with
   a small boost when the name also appears in a trending search.
4. Hold the top few names whose score clears `enter`; sell anything held whose score has
   fallen to `exit` or below. Long only, whole shares, equal weight inside the invested share.

Every order goes through the OMS (compliance) and then the execution guard (limits, kill
switch). Nothing here has a proven edge: it is a starting rule to measure, not a money machine.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta

import pandas as pd
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from spectre.execution.brokers import Broker, PaperBroker
from spectre.execution.guard import TradingLimits, execute
from spectre.marketdata.prices import latest_price_date, latest_prices
from spectre.models import Security, Side
from spectre.portfolio.positions import value_portfolio
from spectre.signals.aggregate import BEAR_T, BULL_T
from spectre.signals.models import SearchTrend, SocialPost
from spectre.trading import oms

BOT_ACTOR = "kairos"
TREND_BOOST = 1.25


@dataclass
class TrendSignal:
    ticker: str
    security_id: int
    n_posts: int
    n_authors: int
    bull_share: float
    bear_share: float
    net: float
    labelled_share: float  # share of posts where the author declared a stance themselves
    trending: bool
    price: float | None
    score: float

    def to_dict(self) -> dict:
        return asdict(self)


def live_signals(
    session: Session,
    lookback_minutes: int = 60,
    min_posts: int = 5,
    min_authors: int = 4,
    at: datetime | None = None,
) -> list[TrendSignal]:
    """Per-security crowd stance over the last `lookback_minutes` of data, strongest first."""
    end = at or session.execute(select(func.max(SocialPost.posted_at))).scalar_one_or_none()
    if end is None:
        return []
    start = end - timedelta(minutes=lookback_minutes)
    rows = session.execute(
        select(SocialPost.author_hash, SocialPost.sentiment, SocialPost.tickers, SocialPost.source_sentiment).where(
            SocialPost.posted_at > start, SocialPost.posted_at <= end, SocialPost.screened_out.is_(False)
        )
    ).all()
    if not rows:
        return []
    df = pd.DataFrame(rows, columns=["author", "sentiment", "tickers", "label"]).explode("tickers").dropna(subset=["tickers"])
    if df.empty:
        return []
    df = df.rename(columns={"tickers": "ticker"})
    sec_ids = dict(session.execute(select(Security.ticker, Security.id)).all())

    last_trend = session.execute(select(func.max(SearchTrend.last_seen))).scalar_one_or_none()
    trending: set[str] = set()
    if last_trend is not None:
        for (tickers,) in session.execute(
            select(SearchTrend.tickers).where(SearchTrend.last_seen >= last_trend - timedelta(hours=24))
        ):
            trending.update(tickers or [])

    as_of = latest_price_date(session) or end.date()
    prices = latest_prices(session, [sec_ids[t] for t in df["ticker"].unique() if t in sec_ids], as_of)

    out: list[TrendSignal] = []
    for ticker, g in df.groupby("ticker"):
        if ticker not in sec_ids:
            continue
        votes = g.groupby("author")["sentiment"].mean()  # one author, one vote
        n_posts, n_authors = int(len(g)), int(len(votes))
        if n_posts < min_posts or n_authors < min_authors:
            continue
        bull, bear = float((votes > BULL_T).mean()), float((votes < BEAR_T).mean())
        net = bull - bear
        sid = sec_ids[ticker]
        is_trending = ticker in trending
        out.append(
            TrendSignal(
                ticker=ticker, security_id=sid, n_posts=n_posts, n_authors=n_authors, bull_share=bull, bear_share=bear,
                net=net, labelled_share=float(g["label"].notna().mean()), trending=is_trending,
                price=float(prices[sid]) if sid in prices.index else None,
                score=net * math.log1p(n_authors) * (TREND_BOOST if is_trending else 1.0),
            )
        )
    return sorted(out, key=lambda s: -s.score)


@dataclass
class BotReport:
    at: str
    portfolio_id: int
    nav: float
    cash: float
    signals: list[TrendSignal]
    targets: list[str]
    actions: list[dict] = field(default_factory=list)
    dry_run: bool = False

    def to_dict(self) -> dict:
        d = asdict(self)
        d["signals"] = [s.to_dict() for s in self.signals]
        return d


def run_once(
    session: Session,
    portfolio_id: int,
    broker: Broker | None = None,
    limits: TradingLimits | None = None,
    top_n: int = 5,
    invest: float = 0.5,
    enter: float = 0.2,
    exit_below: float = 0.0,
    lookback_minutes: int = 60,
    min_posts: int = 5,
    min_authors: int = 4,
    dry_run: bool = False,
    at: datetime | None = None,
) -> BotReport:
    """One decision cycle: read the crowd, decide targets, trade the difference."""
    broker = broker or PaperBroker()
    limits = limits or TradingLimits.from_settings()
    signals = live_signals(session, lookback_minutes, min_posts, min_authors, at)
    by_sid = {s.security_id: s for s in signals}
    valued = value_portfolio(session, portfolio_id)
    nav, cash = valued.total_value, valued.cash
    held = {int(sid): float(q) for sid, q in valued.positions["quantity"].items() if q > 0}

    targets = [s for s in signals if s.score >= enter and s.price][:top_n]
    report = BotReport(
        at=(at or datetime.now()).isoformat(timespec="seconds"), portfolio_id=portfolio_id, nav=nav, cash=cash,
        signals=signals, targets=[s.ticker for s in targets], dry_run=dry_run,
    )

    def trade(sig: TrendSignal, side: Side, qty: float, why: str) -> None:
        action = {"ticker": sig.ticker, "side": side.value, "quantity": qty, "price": sig.price, "why": why}
        if dry_run:
            action["outcome"] = "dry run"
        else:
            order = oms.create_order(session, portfolio_id=portfolio_id, security_id=sig.security_id, side=side,
                                     quantity=qty, actor=BOT_ACTOR)
            if order.status != "APPROVED":
                action.update(outcome="rejected by compliance", detail=order.reject_reason)
            else:
                res = execute(session, order.id, broker, limits, actor=BOT_ACTOR)
                action.update(outcome=res.outcome, detail="; ".join(res.reasons), order_id=order.id, fill_price=res.price)
        report.actions.append(action)

    # Exits first: they free cash and reduce risk.
    for sid, qty in held.items():
        sig = by_sid.get(sid)
        if sig is None or sig.price is None or sig.score > exit_below:
            continue  # no fresh read on this name: hold rather than trade on silence
        sell_qty = min(qty, math.floor(limits.max_order_notional / sig.price))
        if sell_qty >= 1:
            trade(sig, Side.SELL, float(sell_qty), f"score {sig.score:+.2f} fell to the exit level")
            if report.actions[-1].get("outcome") in ("executed", "dry run"):
                cash += sell_qty * sig.price

    per_name = nav * invest / max(top_n, 1)
    for sig in targets:
        current = held.get(sig.security_id, 0.0) * sig.price
        want = min(per_name - current, limits.max_order_notional, max(cash, 0.0))
        qty = math.floor(want / sig.price)
        if qty < 1:
            continue
        trade(sig, Side.BUY, float(qty), f"score {sig.score:+.2f}, {sig.n_authors} authors, net {sig.net:+.0%}")
        if report.actions[-1].get("outcome") in ("executed", "dry run"):
            cash -= qty * sig.price
    return report
