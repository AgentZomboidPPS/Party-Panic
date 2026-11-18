"""KAIROS, the trend bot: lean into what the crowd is leaning into right now, on paper, inside hard limits.

The rule is deliberately simple and easy to audit:

1. Look at the last `lookback_minutes` of screened posts.
2. For each security, give every author one vote (their average stance), so one loud account
   cannot move the result. `net` = share of bullish authors minus share of bearish authors.
3. `score` = net x log(1 + authors): conviction weighted by how many people are talking, with
   a small boost when the name also appears in a trending search.
4. Hold the top few names whose score clears `enter`; sell anything held whose score has
   fallen to `exit` or below. Long only, equal weight inside the invested share: whole shares
   for stocks and funds, millionths of a coin for crypto.
5. With `stop_loss` set, sell a holding whose price has fallen that far below its average
   cost, whatever the crowd says and even with no fresh read on it. Nothing sold today is
   bought back today.

The same rule runs separately for each kind of asset it is pointed at (`asset_classes`): the
stock book during market hours, the coin book around the clock, each with its own allowance.

Every order goes through the OMS (compliance) and then the execution guard (limits, kill
switch). Nothing here has a proven edge: it is a starting rule to measure, not a money machine.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field, replace
from datetime import datetime, timedelta

import pandas as pd
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from spectre.execution.brokers import Broker, PaperBroker
from spectre.execution.guard import TradingLimits, execute
from spectre.marketdata.prices import latest_price_date, latest_prices
from spectre.marketdata.universe import lot_size
from spectre.models import Security, Side, Trade
from spectre.portfolio.positions import average_costs, value_portfolio
from spectre.portfolio.settlement import sale_restrictions
from spectre.signals.aggregate import BEAR_T, BULL_T
from spectre.signals.models import SearchTrend, SocialPost
from spectre.trading import oms

BOT_ACTOR = "kairos"
TREND_BOOST = 1.25
STOCKS: tuple[str, ...] = ("Equity", "Fund")
CRYPTO: tuple[str, ...] = ("Crypto",)
MIN_ORDER = {"Crypto": 10.0}  # dollars: a coin order smaller than this is dust
OVER_ALLOWANCE = 0.05  # how far past its allowance (as a share of the portfolio) a book may drift before it is trimmed
CASH_SLACK = 0.99  # market orders fill a little away from the last price: never size to the last dollar
MIN_TOPUP = 0.05  # a purchase smaller than this share of a full position is not worth an order (or its fee)


def withdraw_unfilled(session: Session, order) -> None:
    """A bot order that did not fill, or only partly, is withdrawn rather than left open: the
    next cycle decides afresh on fresh data, and the blotter does not fill up with stale orders."""
    if order.status in ("APPROVED", "PARTIALLY_FILLED"):
        oms.cancel_order(session, order.id, actor=BOT_ACTOR, reason="not filled in the cycle that created it")


def _lots(amount: float, price: float, lot: float) -> float:
    """The largest quantity, in whole lots, that `amount` buys at `price`."""
    if amount <= 0 or price <= 0:
        return 0.0
    return round(math.floor(amount / price / lot) * lot, 9)


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
    asset_class: str = "Equity"

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
    listed = session.execute(select(Security.ticker, Security.id, Security.asset_class).where(Security.asset_class != "Option")).all()
    sec_ids = {t: i for t, i, _ in listed}
    kinds = {t: k for t, _, k in listed}

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
                asset_class=kinds[ticker],
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
    asset_classes: tuple[str, ...] = STOCKS,
    stop_loss: float | None = None,
) -> BotReport:
    """One decision cycle for one kind of asset: read the crowd, decide targets, trade the difference.
    `invest` is the share of the whole portfolio this book may hold; `stop_loss` (0.08 = 8%) is
    how far below its average cost a holding may fall before it is sold regardless."""
    broker = broker or PaperBroker()
    limits = limits or TradingLimits.from_settings()
    signals = [s for s in live_signals(session, lookback_minutes, min_posts, min_authors, at) if s.asset_class in asset_classes]
    by_sid = {s.security_id: s for s in signals}
    valued = value_portfolio(session, portfolio_id)
    nav, cash = valued.total_value, valued.cash
    book = valued.positions[valued.positions["asset_class"].isin(asset_classes)]
    held = {int(sid): float(q) for sid, q in book["quantity"].items() if q > 1e-9}
    # `invest` caps the whole book. Names that fall out of the top N are kept while the crowd
    # still likes them, so without this cap the book would creep past it.
    room = nav * invest - float(book["market_value"].clip(lower=0).sum())

    targets = [s for s in signals if s.score >= enter and s.price][:top_n]
    report = BotReport(
        at=(at or datetime.now()).isoformat(timespec="seconds"), portfolio_id=portfolio_id, nav=nav, cash=cash,
        signals=signals, targets=[s.ticker for s in targets], dry_run=dry_run,
    )

    def trade(sig: TrendSignal, side: Side, qty: float, why: str) -> bool:
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
                if res.quantity:
                    action["quantity"] = res.quantity  # what actually filled
                withdraw_unfilled(session, order)
        report.actions.append(action)
        return action["outcome"] in ("executed", "dry run")

    on_hold = sale_restrictions(session, portfolio_id)

    def sell(sig: TrendSignal, why: str) -> None:
        nonlocal cash, room
        lot = lot_size(sig.asset_class)
        locked, free_on = on_hold.get(sig.ticker, (0.0, None))
        qty = min(held[sig.security_id] - locked, _lots(limits.max_order_notional, sig.price, lot))
        if locked > 0 and qty < lot:
            # Bought with the proceeds of a sale that has not settled: selling now would be a
            # good-faith violation, so wait for the money to arrive.
            report.actions.append({"ticker": sig.ticker, "side": "SELL", "quantity": locked, "price": sig.price, "outcome": "skipped",
                                   "why": f"{why}; held until {free_on}, when the money that paid for it settles"})
            return
        if qty >= lot and trade(sig, Side.SELL, qty, why):
            done = report.actions[-1]["quantity"]
            cash += done * sig.price
            room += done * sig.price
            gone.add(sig.security_id)

    # Exits first: they free cash and reduce risk.
    gone: set[int] = set()
    costs = average_costs(session, portfolio_id) if stop_loss else {}
    for sid in held:
        sig = by_sid.get(sid)
        price, cost = float(book.at[sid, "price"]), costs.get(sid)
        if stop_loss and cost and price <= cost * (1 - stop_loss):
            # A stop does not wait for the crowd: it uses the latest price, read or no read.
            row = book.loc[sid]
            stand_in = sig or TrendSignal(row["ticker"], sid, 0, 0, 0.0, 0.0, 0.0, 0.0, False, price, 0.0, row["asset_class"])
            sell(replace(stand_in, price=price), f"{1 - price / cost:.1%} below its average cost of {cost:,.2f}: stop")
            continue
        if sig is None or sig.price is None or sig.score > exit_below:
            continue  # no fresh read on this name: hold rather than trade on silence
        sell(sig, f"score {sig.score:+.2f} fell to the exit level")

    # Still well over the allowance (it was lowered, or prices ran): let go of the weakest
    # reads outside the top names until the book fits again.
    keep = {s.security_id for s in targets}
    extras = sorted((by_sid[sid] for sid in held if sid in by_sid and sid not in keep and sid not in gone and by_sid[sid].price),
                    key=lambda s: s.score)
    for sig in extras:
        if room >= -OVER_ALLOWANCE * nav:
            break
        sell(sig, f"book is over its {invest:.0%} allowance and {sig.ticker} is the weakest read outside the top {top_n}")

    # Nothing sold today is bought back today: a stop re-entered ten minutes later is not a
    # stop, and flip-flopping on one name is how a cash account runs into settlement trouble.
    # (Slivers booked for a fee paid in coin are not orders and do not count.)
    resting = gone | set(session.execute(
        select(Trade.security_id).where(Trade.portfolio_id == portfolio_id, Trade.side == Side.SELL.value,
                                        Trade.trade_date >= valued.as_of, Trade.order_id.is_not(None))
    ).scalars())
    per_name = nav * invest / max(top_n, 1)
    for sig in targets:
        if sig.security_id in resting:
            continue
        lot = lot_size(sig.asset_class)
        current = held.get(sig.security_id, 0.0) * sig.price
        want = min(per_name - current, room, limits.max_order_notional, max(cash, 0.0) * CASH_SLACK)
        qty = _lots(want, sig.price, lot)
        if qty < lot or qty * sig.price < max(MIN_ORDER.get(sig.asset_class, 0.0), MIN_TOPUP * per_name):
            continue
        if trade(sig, Side.BUY, qty, f"score {sig.score:+.2f}, {sig.n_authors} authors, net {sig.net:+.0%}"):
            done = report.actions[-1]["quantity"]
            cash -= done * sig.price
            room -= done * sig.price
    return report
