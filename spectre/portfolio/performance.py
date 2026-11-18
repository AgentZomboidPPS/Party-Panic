"""Is it making money? A record of what the portfolio was worth over time, set against the
S&P 500 over the same stretch, and a breakdown of where the profit or loss came from.

Three sleeves: stocks and funds, options, coins. For each: profit already banked by selling
(`realised`), profit or loss still open at today's prices (`unrealised`) and fees paid. Fees
charged outside any one trade (a broker's regulatory fees, found in reconciliation) are a
separate line. The parts add up exactly to the portfolio's value less the money put in.

The return shown is profit over money put in. With a single deposit that is the true return;
with several it understates or overstates a little, since later money had less time to work.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from spectre.marketdata.fx import fx_rate
from spectre.marketdata.prices import latest_price_date, latest_prices
from spectre.models import CashFlow, Fill, NavSnapshot, Order, Security, Side, Trade
from spectre.portfolio.positions import EPS, ValuedPositions, value_portfolio
from spectre.signals.models import PriceTick

BENCHMARK = "SPY"
SLEEVES = ("Stocks and funds", "Options", "Coins", "Other")
_COLUMN = {"Stocks and funds": "stocks", "Options": "options", "Coins": "coins", "Other": "other"}


def sleeve_of(asset_class: str) -> str:
    return {"Equity": "Stocks and funds", "Fund": "Stocks and funds", "Option": "Options", "Crypto": "Coins"}.get(
        asset_class, "Other")


def _now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def _benchmark_price(session: Session) -> float | None:
    sid = session.execute(select(Security.id).where(Security.ticker == BENCHMARK)).scalar_one_or_none()
    if sid is None:
        return None
    day = latest_price_date(session)
    if day is None:
        return None
    px = latest_prices(session, [sid], day)
    return float(px[sid]) if sid in px.index else None


def record_snapshot(session: Session, portfolio_id: int, at: datetime | None = None,
                    min_gap_minutes: float = 4.0) -> NavSnapshot | None:
    """Write down what the portfolio is worth right now. Skipped if one was written moments ago."""
    at = at or _now()
    last = session.execute(
        select(func.max(NavSnapshot.at)).where(NavSnapshot.portfolio_id == portfolio_id)
    ).scalar_one_or_none()
    if last is not None and at - last < timedelta(minutes=min_gap_minutes):
        return None
    v = value_portfolio(session, portfolio_id)
    by = {name: 0.0 for name in SLEEVES}
    for row in v.positions.itertuples():
        by[sleeve_of(row.asset_class)] += float(row.market_value)
    snap = NavSnapshot(portfolio_id=portfolio_id, at=at, nav=v.total_value, cash=v.cash, benchmark=_benchmark_price(session),
                       **{_COLUMN[k]: val for k, val in by.items()})
    session.add(snap)
    session.commit()
    return snap


def sleeve_pnl(session: Session, valued: ValuedPositions) -> list[dict]:
    """Realised and unrealised profit and fees for each sleeve, from the ledger and today's prices."""
    out = {name: {"sleeve": name, "market_value": 0.0, "realised": 0.0, "unrealised": 0.0, "fees": 0.0,
                  "closed_trades": 0, "winners": 0} for name in SLEEVES}
    held: dict[int, float] = {}
    cost: dict[int, float] = {}
    scale: dict[int, tuple[str, float]] = {}  # security -> (sleeve, multiplier)
    sales: dict[int, tuple[str, float]] = {}  # sale order -> (sleeve, profit banked by it)
    rows = session.execute(
        select(Trade, Security).join(Security, Security.id == Trade.security_id)
        .where(Trade.portfolio_id == valued.portfolio_id, Trade.trade_date <= valued.as_of)
        .order_by(Trade.trade_date, Trade.id)
    ).all()
    for t, sec in rows:
        fx = fx_rate(session, t.currency, valued.base_currency, t.trade_date)
        sleeve = out[sleeve_of(sec.asset_class)]
        scale[sec.id] = (sleeve["sleeve"], sec.multiplier * fx)
        have = held.get(sec.id, 0.0)
        sleeve["fees"] += t.fees * fx
        if t.side == Side.BUY.value:
            cost[sec.id] = (cost.get(sec.id, 0.0) * have + t.price * t.quantity) / (have + t.quantity)
            held[sec.id] = have + t.quantity
        else:
            gain = (t.price - cost.get(sec.id, t.price)) * t.quantity * sec.multiplier * fx
            sleeve["realised"] += gain
            if t.order_id is not None:  # a real sale, not a sliver booked for a fee paid in kind
                # One sale is one order, however many pieces it was filled in.
                name, so_far = sales.get(t.order_id, (sleeve["sleeve"], 0.0))
                sales[t.order_id] = (name, so_far + gain)
            held[sec.id] = have - t.quantity
            if held[sec.id] <= EPS:
                held.pop(sec.id)
                cost.pop(sec.id, None)
    for name, gain in sales.values():
        out[name]["closed_trades"] += 1
        out[name]["winners"] += gain > 0
    open_cost = {name: 0.0 for name in SLEEVES}
    for sid, qty in held.items():
        name, mult = scale[sid]
        open_cost[name] += qty * cost[sid] * mult
    for row in valued.positions.itertuples():
        out[sleeve_of(row.asset_class)]["market_value"] += float(row.market_value)
    for name, s in out.items():
        s["unrealised"] = s["market_value"] - open_cost[name]
        s["total"] = s["realised"] + s["unrealised"] - s["fees"]
    return [s for s in out.values() if s["market_value"] or s["realised"] or s["fees"] or s["closed_trades"]]


def _inception(session: Session, portfolio_id: int) -> datetime | None:
    """When the portfolio first traded (the moment before which it was all cash)."""
    first = session.execute(
        select(func.min(Fill.filled_at)).join(Order, Order.id == Fill.order_id).where(Order.portfolio_id == portfolio_id)
    ).scalar_one_or_none()
    return first.replace(tzinfo=None) if first is not None else None


def _benchmark_at(session: Session, when: datetime) -> float | None:
    sid = session.execute(select(Security.id).where(Security.ticker == BENCHMARK)).scalar_one_or_none()
    if sid is None:
        return None
    return session.execute(
        select(PriceTick.price).where(PriceTick.security_id == sid, PriceTick.observed_at <= when)
        .order_by(PriceTick.observed_at.desc()).limit(1)
    ).scalar_one_or_none()


def performance(session: Session, portfolio_id: int, max_points: int = 400) -> dict:
    v = value_portfolio(session, portfolio_id)
    flows = session.execute(select(CashFlow.kind, CashFlow.amount, CashFlow.date).where(
        CashFlow.portfolio_id == portfolio_id, CashFlow.date <= v.as_of)).all()
    put_in = sum(a for k, a, _ in flows if k == "EXTERNAL")
    other_cash = sum(a for k, a, _ in flows if k != "EXTERNAL")
    pnl = v.total_value - put_in
    sleeves = sleeve_pnl(session, v)

    snaps = session.execute(
        select(NavSnapshot).where(NavSnapshot.portfolio_id == portfolio_id).order_by(NavSnapshot.at)
    ).scalars().all()
    start = _inception(session, portfolio_id)
    base = (_benchmark_at(session, start) if start else None) or next((s.benchmark for s in snaps if s.benchmark), None)
    points: list[dict] = []
    if start is not None and put_in and (not snaps or start < snaps[0].at):
        points.append({"at": start.isoformat(timespec="seconds"), "nav": put_in, "return": 0.0,
                       "benchmark_return": 0.0 if base else None})
    for s in snaps:
        points.append({"at": s.at.isoformat(timespec="seconds"), "nav": s.nav,
                       "return": s.nav / put_in - 1 if put_in else None,
                       "benchmark_return": s.benchmark / base - 1 if s.benchmark and base else None})
    if len(points) > max_points:  # thin a long record evenly, always keeping the newest point
        step = len(points) / max_points
        points = [points[int(i * step)] for i in range(max_points - 1)] + [points[-1]]

    peak, drawdown = None, 0.0
    for pt in points:
        peak = pt["nav"] if peak is None else max(peak, pt["nav"])
        drawdown = min(drawdown, pt["nav"] / peak - 1)
    today = _now().date()
    before_today = [s for s in snaps if s.at.date() < today]
    day_base = before_today[-1].nav if before_today else (put_in if start is not None and start.date() == today else None)
    now_bench = _benchmark_price(session)
    bench_return = now_bench / base - 1 if now_bench and base else None
    ret = pnl / put_in if put_in else None
    closed = sum(s["closed_trades"] for s in sleeves)
    return {
        "portfolio_id": portfolio_id, "as_of": v.as_of.isoformat(), "since": start.isoformat(timespec="seconds") if start else None,
        "nav": v.total_value, "put_in": put_in, "pnl": pnl, "return": ret,
        "benchmark": {"ticker": BENCHMARK, "return": bench_return},
        "excess_return": ret - bench_return if ret is not None and bench_return is not None else None,
        "day_change": v.total_value - day_base if day_base is not None else None,
        "max_drawdown": drawdown,
        "sleeves": sleeves, "account_fees_and_adjustments": other_cash,
        "closed_trades": closed, "winners": sum(s["winners"] for s in sleeves),
        "snapshots": len(snaps), "series": points,
    }


def buying_brake(session: Session, portfolio_id: int, max_drawdown: float = 0.10, max_daily_loss: float = 0.03,
                 now: datetime | None = None) -> str | None:
    """A reason to stop buying, or None.

    Two brakes on the whole account, both read off the record of its value: it is more than
    `max_drawdown` below the most it has ever been worth, or it is more than `max_daily_loss`
    down since the last value recorded before today. Either one stops new purchases only:
    selling, and the stop-losses, carry on, since those reduce risk. Nothing has to be reset;
    the brake releases by itself when the account is back inside the limit (or, for the daily
    one, the next day). 0 switches a brake off."""
    now = now or _now()
    nav = value_portfolio(session, portfolio_id).total_value
    put_in = session.execute(
        select(func.coalesce(func.sum(CashFlow.amount), 0.0)).where(CashFlow.portfolio_id == portfolio_id, CashFlow.kind == "EXTERNAL")
    ).scalar_one()
    snaps = session.execute(
        select(NavSnapshot.at, NavSnapshot.nav).where(NavSnapshot.portfolio_id == portfolio_id).order_by(NavSnapshot.at)
    ).all()
    peak = max([put_in, nav] + [n for _, n in snaps])
    if max_drawdown and peak > 0 and nav <= peak * (1 - max_drawdown):
        return f"the account is {1 - nav / peak:.1%} below its high of {peak:,.0f} (the limit is {max_drawdown:.0%})"
    earlier = [n for at, n in snaps if at.date() < now.date()]
    start = _inception(session, portfolio_id)
    day_start = earlier[-1] if earlier else (put_in if start is not None and start.date() == now.date() else None)
    if max_daily_loss and day_start and nav <= day_start * (1 - max_daily_loss):
        return f"the account is {1 - nav / day_start:.1%} down today (the limit is {max_daily_loss:.0%})"
    return None
