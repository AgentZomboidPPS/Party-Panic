"""From aggregates to tradeable signals, with the tools to test whether they carry information.

A signal is only an edge if it predicts forward returns out of sample. `information_coefficient`
and `long_short_backtest` are how you find out; `strategy_orders` is how you trade it on paper
through the OMS, with compliance in the loop.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

import numpy as np
import pandas as pd
from scipy.stats import spearmanr
from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.models import Order, OrderStatus, Price, Security, Side, Trade
from lantern.portfolio.positions import value_portfolio
from lantern.signals.models import SentimentBar
from lantern.trading import oms

# --------------------------------------------------------------------------- daily signals


def daily_signals(session: Session, start: date, end: date, lookback: int = 20, min_posts: int = 2) -> pd.DataFrame:
    """Long frame: one row per (date, security) with post-weighted sentiment and rolling z-scores."""
    rows = session.execute(
        select(SentimentBar.security_id, SentimentBar.ticker, SentimentBar.window_start, SentimentBar.n_posts, SentimentBar.sentiment_mean)
        .where(SentimentBar.window_start >= datetime.combine(start, datetime.min.time()),
               SentimentBar.window_start < datetime.combine(end + timedelta(days=1), datetime.min.time()))
    ).all()
    if not rows:
        return pd.DataFrame(columns=["date", "security_id", "ticker", "n_posts", "sentiment", "attention_z", "sentiment_z", "score"])
    df = pd.DataFrame(rows, columns=["security_id", "ticker", "window_start", "n_posts", "sentiment_mean"])
    df["date"] = pd.to_datetime(df["window_start"]).dt.normalize()
    df["w"] = df["n_posts"] * df["sentiment_mean"]
    g = df.groupby(["date", "security_id", "ticker"], as_index=False).agg(n_posts=("n_posts", "sum"), w=("w", "sum"))
    g["sentiment"] = g["w"] / g["n_posts"]
    g = g.drop(columns="w").sort_values(["security_id", "date"])

    def _z(col: pd.Series) -> pd.Series:
        m = col.shift(1).rolling(lookback, min_periods=5).mean()
        s = col.shift(1).rolling(lookback, min_periods=5).std()
        return (col - m) / s.replace(0, np.nan)

    g["attention_z"] = g.groupby("security_id")["n_posts"].transform(_z)
    g["sentiment_z"] = g.groupby("security_id")["sentiment"].transform(_z)
    g.loc[g["n_posts"] < min_posts, ["sentiment_z", "attention_z"]] = np.nan
    g["score"] = g["sentiment_z"]
    return g.reset_index(drop=True)


def signal_matrix(long: pd.DataFrame, column: str = "score") -> pd.DataFrame:
    if long.empty:
        return pd.DataFrame()
    return long.pivot(index="date", columns="security_id", values=column).sort_index()


def price_wide(session: Session, security_ids, start: date, end: date) -> pd.DataFrame:
    rows = session.execute(
        select(Price.security_id, Price.date, Price.close).where(
            Price.security_id.in_(list(security_ids)), Price.date >= start, Price.date <= end
        )
    ).all()
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows, columns=["security_id", "date", "close"])
    df["date"] = pd.to_datetime(df["date"])
    return df.pivot(index="date", columns="security_id", values="close").sort_index().ffill()


def forward_returns(prices: pd.DataFrame, horizon: int = 1) -> pd.DataFrame:
    """Return from close on day t to close on day t+horizon, indexed at t."""
    return prices.shift(-horizon) / prices - 1.0


# --------------------------------------------------------------------------- evaluation


def information_coefficient(signal: pd.DataFrame, fwd: pd.DataFrame, min_names: int = 5) -> dict:
    """Daily cross-sectional Spearman rank correlation between signal and forward return."""
    idx = signal.index.intersection(fwd.index)
    cols = signal.columns.intersection(fwd.columns)
    ics = []
    for d in idx:
        s, r = signal.loc[d, cols], fwd.loc[d, cols]
        mask = s.notna() & r.notna()
        if mask.sum() >= min_names:
            ic, _ = spearmanr(s[mask], r[mask])
            if not np.isnan(ic):
                ics.append((d, float(ic)))
    series = pd.Series(dict(ics), dtype=float).sort_index()
    n = len(series)
    mean = float(series.mean()) if n else 0.0
    std = float(series.std(ddof=1)) if n > 1 else 0.0
    return {
        "n_days": n,
        "mean_ic": mean,
        "std_ic": std,
        "t_stat": (mean / std * np.sqrt(n)) if std > 0 and n > 1 else 0.0,
        "hit_rate": float((series > 0).mean()) if n else 0.0,
        "ic_series": series,
    }


def long_short_backtest(signal: pd.DataFrame, fwd_1d: pd.DataFrame, quantile: float = 0.3, min_names: int = 5) -> dict:
    """Each day: long the top `quantile` of names by signal, short the bottom, equal weight,
    earn the next day's return. Dollar-neutral, daily rebalance, no costs (so: an upper bound)."""
    idx = signal.index.intersection(fwd_1d.index)
    cols = signal.columns.intersection(fwd_1d.columns)
    rets: list[tuple] = []
    turnover: list[float] = []
    prev_long: set = set()
    for d in idx:
        s, r = signal.loc[d, cols], fwd_1d.loc[d, cols]
        mask = s.notna() & r.notna()
        if mask.sum() < min_names:
            continue
        s, r = s[mask], r[mask]
        k = max(int(np.floor(len(s) * quantile)), 1)
        ranked = s.sort_values()
        short_names, long_names = ranked.index[:k], ranked.index[-k:]
        rets.append((d, float(r[long_names].mean() - r[short_names].mean())))
        cur = set(long_names)
        turnover.append(len(cur ^ prev_long) / (2 * k) if prev_long else 1.0)
        prev_long = cur
    series = pd.Series(dict(rets), dtype=float).sort_index()
    if series.empty:
        return {"n_days": 0, "sharpe": 0.0, "ann_return": 0.0, "ann_vol": 0.0, "max_drawdown": 0.0, "turnover": 0.0, "equity": series}
    equity = (1 + series).cumprod()
    dd = equity / equity.cummax() - 1
    vol = float(series.std(ddof=1)) if len(series) > 1 else 0.0
    return {
        "n_days": int(len(series)),
        "sharpe": float(series.mean() / vol * np.sqrt(252)) if vol > 0 else 0.0,
        "ann_return": float(series.mean() * 252),
        "ann_vol": float(vol * np.sqrt(252)),
        "max_drawdown": float(dd.min()),
        "turnover": float(np.mean(turnover)) if turnover else 0.0,
        "equity": equity,
    }


def evaluate(session: Session, start: date, end: date, horizon: int = 1, signal: str = "score", quantile: float = 0.3) -> dict:
    long = daily_signals(session, start, end)
    if long.empty:
        return {"error": "no sentiment bars in range"}
    sig = signal_matrix(long, signal)
    px = price_wide(session, sig.columns, start, end + timedelta(days=horizon * 3 + 5))
    if px.empty:
        return {"error": "no prices for signal universe"}
    ic = information_coefficient(sig, forward_returns(px, horizon))
    bt = long_short_backtest(sig, forward_returns(px, 1), quantile)
    coverage = long.groupby("date")["security_id"].nunique()
    return {
        "signal": signal,
        "horizon_days": horizon,
        "start": str(sig.index.min().date()),
        "end": str(sig.index.max().date()),
        "names_per_day": float(coverage.mean()),
        "ic": {k: v for k, v in ic.items() if k != "ic_series"},
        "long_short": {k: v for k, v in bt.items() if k != "equity"},
        "equity_curve": [{"date": d.date().isoformat(), "equity": float(v)} for d, v in bt["equity"].items()],
        "ic_curve": [{"date": d.date().isoformat(), "ic": float(v)} for d, v in ic["ic_series"].items()],
    }


# --------------------------------------------------------------------------- paper strategy

STRATEGY_ACTOR = "sentiment-strategy"


def _sleeve_holdings(session: Session, portfolio_id: int) -> dict[int, float]:
    """Net quantity per security bought by this strategy's own orders."""
    rows = session.execute(
        select(Trade.security_id, Trade.side, Trade.quantity)
        .join(Order, Order.id == Trade.order_id)
        .where(Trade.portfolio_id == portfolio_id, Order.created_by == STRATEGY_ACTOR)
    ).all()
    held: dict[int, float] = {}
    for sid, side, qty in rows:
        held[sid] = held.get(sid, 0.0) + (qty if side == Side.BUY.value else -qty)
    return {k: v for k, v in held.items() if abs(v) > 1e-9}


def strategy_orders(
    session: Session,
    portfolio_id: int,
    as_of: date | None = None,
    top_n: int = 5,
    sleeve: float = 0.10,
    min_score: float = 0.5,
    lookback_days: int = 40,
) -> list[Order]:
    """Paper trade the sentiment signal inside a sleeve of the portfolio.

    Buy the `top_n` names with score >= min_score to equal weight within `sleeve` of NAV; sell
    anything the strategy previously bought that is no longer in that set. Every order goes
    through the OMS, so compliance can and will reject trades that breach the mandate.
    """
    valued = value_portfolio(session, portfolio_id, as_of)
    as_of = valued.as_of
    long = daily_signals(session, as_of - timedelta(days=lookback_days), as_of)
    if long.empty:
        return []
    latest_day = long["date"].max()
    today = long[long["date"] == latest_day].dropna(subset=["score"])
    chosen = today[today["score"] >= min_score].sort_values("score", ascending=False).head(top_n)
    targets = set(chosen["security_id"].tolist())

    held = _sleeve_holdings(session, portfolio_id)
    created: list[Order] = []
    for sid, qty in held.items():
        if sid not in targets and qty > 0:
            created.append(oms.create_order(session, portfolio_id=portfolio_id, security_id=sid, side=Side.SELL,
                                            quantity=qty, actor=STRATEGY_ACTOR, as_of=as_of))
    if not targets:
        return created
    per_name = valued.total_value * sleeve / len(targets)
    from lantern.marketdata.prices import latest_prices

    prices = latest_prices(session, targets, as_of)
    secs = {s.id: s for s in session.execute(select(Security).where(Security.id.in_(targets))).scalars()}
    for sid in targets:
        if sid not in prices.index:
            continue
        sec = secs[sid]
        px = float(prices[sid]) * sec.multiplier
        if sid in valued.positions.index:
            fx = float(valued.positions.at[sid, "fx_rate"])
        else:
            from lantern.marketdata.fx import fx_rate

            fx = fx_rate(session, sec.currency, valued.base_currency, as_of)
        current_qty = held.get(sid, 0.0)
        target_qty = per_name / (px * fx)
        delta = target_qty - current_qty
        lot = 1000.0 if sec.multiplier != 1.0 else 1.0
        delta = float(np.floor(abs(delta) / lot) * lot) * np.sign(delta)
        if abs(delta) * px * fx < 0.001 * valued.total_value:
            continue
        created.append(oms.create_order(session, portfolio_id=portfolio_id, security_id=sid,
                                        side=Side.BUY if delta > 0 else Side.SELL, quantity=abs(delta),
                                        actor=STRATEGY_ACTOR, as_of=as_of))
    return created


def fill_approved_at_market(session: Session, orders: list[Order], as_of: date | None = None) -> int:
    """Paper execution: fill every approved order at the latest price (no slippage)."""
    from lantern.marketdata.prices import latest_price_date, latest_prices

    as_of = as_of or latest_price_date(session) or date.today()
    n = 0
    for o in orders:
        if o.status != OrderStatus.APPROVED.value:
            continue
        px = latest_prices(session, [o.security_id], as_of)
        if o.security_id in px.index:
            oms.fill_order(session, o.id, o.quantity, float(px[o.security_id]), actor=STRATEGY_ACTOR,
                           filled_at=datetime.combine(as_of, datetime.min.time().replace(hour=20)))
            n += 1
    return n
