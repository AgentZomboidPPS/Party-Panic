"""The day in one page: what the portfolio is worth, what the bot did and why, what it holds,
how much risk it carries, and anything that needs a person to look at it."""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre import audit
from spectre.compliance.engine import post_trade_check
from spectre.models import AuditEvent, Order, Portfolio, Security
from spectre.portfolio.performance import performance
from spectre.portfolio.positions import average_costs, value_portfolio
from spectre.portfolio.settlement import is_business_day, simulate


def _utc_day(day: date) -> tuple[datetime, datetime]:
    start = datetime.combine(day, time.min)
    return start, start + timedelta(days=1)


def session_is_over(now: datetime | None = None, market_open: bool | None = None) -> bool:
    """Has today's US stock session finished? Never on a weekend or exchange holiday. With the
    broker's clock (`market_open`) it is over once the market is shut late in the UTC day;
    without it, from five past nine in the evening UTC, which is after the close all year."""
    now = now or datetime.now(UTC).replace(tzinfo=None)
    if not is_business_day(now.date()):
        return False
    if market_open is None:
        return now.time() >= time(21, 5)
    return not market_open and now.time() >= time(20, 0)


def already_reported(session: Session, portfolio_id: int, day: date) -> bool:
    rows = session.execute(
        select(AuditEvent.detail).where(AuditEvent.entity_type == "portfolio", AuditEvent.entity_id == portfolio_id,
                                        AuditEvent.action == "daily_report")
    ).scalars()
    return any((d or {}).get("day") == day.isoformat() for d in rows)


def mark_reported(session: Session, portfolio_id: int, day: date) -> None:
    audit.record(session, actor="report", entity_type="portfolio", entity_id=portfolio_id, action="daily_report",
                 detail={"day": day.isoformat()})
    session.commit()


def daily_report(session: Session, portfolio_id: int, day: date | None = None, client=None) -> dict:
    day = day or datetime.now(UTC).date()
    pf = session.get(Portfolio, portfolio_id)
    if pf is None:
        raise LookupError(f"Portfolio {portfolio_id} not found")
    start, end = _utc_day(day)
    v = value_portfolio(session, portfolio_id)
    perf = performance(session, portfolio_id)

    # What it did: every order created that day, with the reason the bot recorded for it.
    orders = session.execute(
        select(Order, Security.ticker).join(Security, Security.id == Order.security_id)
        .where(Order.portfolio_id == portfolio_id).order_by(Order.id)
    ).all()
    todays = [(o, t) for o, t in orders if start <= o.created_at.replace(tzinfo=None) < end]
    ids = [o.id for o, _ in todays]
    reasons: dict[int, str] = {}
    blocked: dict[int, str] = {}
    if ids:
        for ev in session.execute(select(AuditEvent).where(AuditEvent.entity_type == "order", AuditEvent.entity_id.in_(ids))).scalars():
            if ev.action == "decision":
                reasons[ev.entity_id] = (ev.detail or {}).get("why", "")
            elif ev.action in ("execution_blocked", "broker_rejected"):
                d = ev.detail or {}
                blocked[ev.entity_id] = d.get("reason") or "; ".join(d.get("reasons", []))
    done, missed = [], []
    for o, ticker in todays:
        row = {"at": o.created_at.replace(tzinfo=None).strftime("%H:%M"), "side": o.side, "ticker": ticker,
               "quantity": o.filled_quantity or o.quantity, "price": o.avg_fill_price, "why": reasons.get(o.id, "")}
        if o.filled_quantity > 0:
            done.append(row)
        else:
            missed.append({**row, "outcome": o.status, "detail": o.reject_reason or blocked.get(o.id, "")})

    costs = average_costs(session, portfolio_id)
    holdings = []
    for sid, r in v.positions.iterrows():
        cost = costs.get(int(sid))
        holdings.append({"ticker": r["ticker"], "asset_class": r["asset_class"], "quantity": float(r["quantity"]),
                         "value": float(r["market_value"]), "weight": float(r["weight"]),
                         "open_pnl_pct": float(r["price"]) / cost - 1 if cost else None})
    holdings.sort(key=lambda h: -h["value"])

    from spectre.risk.report import var_suite

    risk = var_suite(session, v)
    para = (risk.get("methods") or {}).get("parametric")
    state = simulate(session, portfolio_id)
    comp = post_trade_check(session, portfolio_id, record=False)

    attention: list[str] = []
    if not comp.passed:
        attention.append("compliance: " + "; ".join(b.message for b in comp.breaches if b.severity.value == "HARD")[:300])
    if state.recent_violations():
        attention.append(f"{len(state.recent_violations())} good-faith violation(s) in the last 12 months")
    if risk.get("not_modelled"):
        attention.append("not in the risk numbers: " + ", ".join(risk["not_modelled"]))
    signal = None
    if client is not None:
        try:
            from spectre.execution.alpaca import reconcile
            from spectre.signals.intraday import check

            rec = reconcile(session, client, portfolio_id)
            if not rec["clean"]:
                attention.append("the ledger and the broker disagree: run `spectre alpaca-reconcile`")
            signal = check(session, client)
        except Exception as exc:  # the report is still worth having without the broker's side
            attention.append(f"could not reach the broker for the reconciliation and signal check ({type(exc).__name__})")

    return {
        "day": day.isoformat(), "portfolio_id": portfolio_id, "portfolio": pf.name, "nav": v.total_value, "cash": v.cash,
        "day_change": perf["day_change"], "put_in": perf["put_in"], "pnl": perf["pnl"], "return": perf["return"],
        "benchmark_return": perf["benchmark"]["return"], "sleeves": perf["sleeves"],
        "orders_filled": done, "orders_not_filled": missed, "holdings": holdings,
        "exposure_pct": (risk.get("exposure") or {}).get("net_pct"), "var": para["var"] if para else None,
        "var_pct": para["var_pct"] if para else None, "on_hold": state.restricted,
        "settling": {"arriving": state.receivable, "owed": state.payable},
        "signal": {"windows": signal["windows"], "verdict": signal["verdict"]} if signal else None,
        "attention": attention,
    }


def render(r: dict) -> str:
    """The report as plain text, short enough to read in a message."""

    def money(x: float | None, sign: bool = True) -> str:
        return "-" if x is None else f"{x:+,.0f}" if sign else f"{x:,.0f}"

    def pct(x: float | None) -> str:
        return "-" if x is None else f"{x:+.2%}"

    def qty(q: float) -> str:
        return f"{q:,.0f}" if float(q).is_integer() else f"{q:,.6f}".rstrip("0")

    day = date.fromisoformat(r["day"])
    out = [f"KAIROS daily report, {day:%A %d %B %Y} ({r['portfolio']})", ""]
    out.append(f"Worth {r['nav']:,.0f}. Today {money(r['day_change'])}; since the start {money(r['pnl'])} ({pct(r['return'])}) "
               f"against {pct(r['benchmark_return'])} for the S&P 500.")
    if r["sleeves"]:
        out.append("Since the start by sleeve: " + "; ".join(f"{s['sleeve'].lower()} {money(s['total'])}" for s in r["sleeves"]) + ".")
    out.append("")
    if r["orders_filled"]:
        out.append(f"What it did ({len(r['orders_filled'])} orders filled, times in UTC):")
        for o in r["orders_filled"]:
            price = f"{o['price']:,.2f}" if o["price"] else "-"
            out.append(f"  {o['at']}  {o['side']:<4} {qty(o['quantity'])} {o['ticker']} @ {price}" + (f"  ({o['why']})" if o["why"] else ""))
    else:
        out.append("It did not trade today.")
    if r["orders_not_filled"]:
        out.append(f"{len(r['orders_not_filled'])} orders did not go through:")
        for o in r["orders_not_filled"][:6]:
            out.append(f"  {o['at']}  {o['side']:<4} {qty(o['quantity'])} {o['ticker']}: {o['outcome'].lower()}"
                       + (f" ({o['detail'][:110]})" if o["detail"] else ""))
    out.append("")
    out.append(f"Holding {len(r['holdings'])} positions and {r['cash']:,.0f} in cash:")
    for h in r["holdings"]:
        out.append(f"  {h['ticker']:<22} {h['value']:>9,.0f}  {h['weight']:>6.1%}  " + (pct(h["open_pnl_pct"]) if h["open_pnl_pct"] is not None else ""))
    out.append("")
    risk = []
    if r["exposure_pct"] is not None:
        risk.append(f"market exposure {r['exposure_pct']:.0%} of its value")
    if r["var"] is not None:
        risk.append(f"a bad day (1 in 100) would cost about {r['var']:,.0f} ({r['var_pct']:.1%})")
    if risk:
        out.append("Risk: " + "; ".join(risk) + ".")
    if r["on_hold"]:
        out.append("On hold until the money that paid for them settles: "
                   + ", ".join(f"{h['ticker']} (from {h['sell_freely_on']})" for h in r["on_hold"]) + ".")
    if r["signal"]:
        out.append(f"Signal check: {r['signal']['verdict']}")
    out.append("")
    out.append("Needs attention: " + ("; ".join(r["attention"]) if r["attention"] else "nothing."))
    return "\n".join(out)
