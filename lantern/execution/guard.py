"""Trading limits, the kill switch, and the single function that routes an order to a broker."""

from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from lantern import audit
from lantern.config import settings
from lantern.execution.brokers import Broker, BrokerReject
from lantern.execution.models import TradingControl
from lantern.marketdata.prices import latest_price_date, latest_prices
from lantern.models import Order, OrderStatus, Security, Side, Trade
from lantern.portfolio.positions import value_portfolio
from lantern.signals.sources.base import utcnow
from lantern.trading import oms


@dataclass(frozen=True)
class TradingLimits:
    mode: str = "paper"
    max_order_notional: float = 1_000.0
    max_daily_notional: float = 5_000.0
    max_orders_per_day: int = 20
    max_position_weight: float = 0.20
    require_approval: bool = True
    allowed_symbols: frozenset[str] = field(default_factory=frozenset)  # empty = any

    @classmethod
    def from_settings(cls) -> TradingLimits:
        symbols = frozenset(s.strip().upper() for s in settings.trading_allowed_symbols.split(",") if s.strip())
        return cls(
            mode=settings.trading_mode,
            max_order_notional=settings.trading_max_order_notional,
            max_daily_notional=settings.trading_max_daily_notional,
            max_orders_per_day=settings.trading_max_orders_per_day,
            max_position_weight=settings.trading_max_position_weight,
            require_approval=settings.trading_require_approval,
            allowed_symbols=symbols,
        )


@dataclass
class ExecutionResult:
    order_id: int
    outcome: str  # "executed" | "blocked" | "awaiting_approval"
    reasons: list[str] = field(default_factory=list)
    broker: str | None = None
    quantity: float | None = None
    price: float | None = None

    def to_dict(self) -> dict:
        return {"order_id": self.order_id, "outcome": self.outcome, "reasons": self.reasons, "broker": self.broker,
                "quantity": self.quantity, "price": self.price}


# --------------------------------------------------------------------------- kill switch


def halt_state(session: Session) -> TradingControl:
    row = session.get(TradingControl, 1)
    if row is None:
        row = TradingControl(id=1, halted=False)
        session.add(row)
        session.flush()
    return row


def set_halt(session: Session, halted: bool, actor: str, reason: str | None = None) -> TradingControl:
    row = halt_state(session)
    row.halted, row.reason, row.updated_at, row.updated_by = halted, reason, utcnow(), actor
    audit.record(session, actor=actor, entity_type="trading_control", entity_id=1,
                 action="halted" if halted else "resumed", detail={"reason": reason})
    session.commit()
    return row


# --------------------------------------------------------------------------- checks


def _traded_today(session: Session, portfolio_id: int, day) -> tuple[float, int]:
    """Notional and number of orders already executed through the OMS today."""
    rows = session.execute(
        select(func.coalesce(func.sum(Trade.quantity * Trade.price * Security.multiplier), 0.0),
               func.count(func.distinct(Trade.order_id)))
        .join(Security, Security.id == Trade.security_id)
        .where(Trade.portfolio_id == portfolio_id, Trade.trade_date == day, Trade.order_id.is_not(None))
    ).one()
    return float(rows[0]), int(rows[1])


def check(session: Session, order: Order, limits: TradingLimits, broker: Broker) -> list[str]:
    """Every reason this order may not be sent. An empty list means it may."""
    reasons: list[str] = []
    if halt_state(session).halted:
        reasons.append(f"trading is halted: {halt_state(session).reason or 'no reason given'}")
    if order.status not in (OrderStatus.APPROVED.value, OrderStatus.PARTIALLY_FILLED.value):
        reasons.append(f"order is {order.status}; only compliance-approved orders can be executed")
        return reasons
    if broker.live and limits.mode != "live":
        reasons.append("broker is live but trading mode is 'paper'; set LANTERN_TRADING_MODE=live to allow real orders")

    sec = session.get(Security, order.security_id)
    if limits.allowed_symbols and sec.ticker.upper() not in limits.allowed_symbols:
        reasons.append(f"{sec.ticker} is not on the allowed-symbols list")

    as_of = latest_price_date(session) or utcnow().date()
    px = latest_prices(session, [order.security_id], as_of)
    ref = order.limit_price
    if ref is None and order.security_id in px.index:
        ref = float(px[order.security_id])
    if ref is None:
        reasons.append(f"no reference price for {sec.ticker}")
        return reasons
    notional = order.remaining_quantity * ref * sec.multiplier
    if notional > limits.max_order_notional + 1e-9:
        reasons.append(f"order is {notional:,.0f}; the per-order limit is {limits.max_order_notional:,.0f}")

    today = max(as_of, utcnow().date()) if as_of >= utcnow().date() else as_of
    done_notional, done_orders = _traded_today(session, order.portfolio_id, today)
    if done_notional + notional > limits.max_daily_notional + 1e-9:
        reasons.append(
            f"would bring today's total to {done_notional + notional:,.0f}; "
            f"the daily limit is {limits.max_daily_notional:,.0f}"
        )
    if done_orders + 1 > limits.max_orders_per_day:
        reasons.append(f"{done_orders} orders already executed today; the limit is {limits.max_orders_per_day}")

    if order.side == Side.BUY.value:
        valued = value_portfolio(session, order.portfolio_id, as_of)
        held = 0.0
        if order.security_id in valued.positions.index:
            held = float(valued.positions.at[order.security_id, "market_value"])
        if valued.total_value > 0:
            weight = (held + notional) / valued.total_value
            if weight > limits.max_position_weight + 1e-9:
                reasons.append(
                    f"{sec.ticker} would be {weight:.1%} of the portfolio; "
                    f"the limit is {limits.max_position_weight:.0%}"
                )
    return reasons


# --------------------------------------------------------------------------- routing


def execute(
    session: Session,
    order_id: int,
    broker: Broker,
    limits: TradingLimits | None = None,
    approved_by: str | None = None,
    actor: str = "executor",
) -> ExecutionResult:
    """Send one order to a broker if, and only if, every gate is open. Always audited."""
    limits = limits or TradingLimits.from_settings()
    order = session.get(Order, order_id)
    if order is None:
        raise oms.OrderError(f"Order {order_id} not found")

    reasons = check(session, order, limits, broker)
    if reasons:
        audit.record(session, actor=actor, entity_type="order", entity_id=order.id, action="execution_blocked",
                     detail={"broker": broker.name, "reasons": reasons})
        session.commit()
        return ExecutionResult(order.id, "blocked", reasons, broker.name)

    if broker.live and limits.require_approval and not approved_by:
        audit.record(session, actor=actor, entity_type="order", entity_id=order.id, action="awaiting_approval",
                     detail={"broker": broker.name})
        session.commit()
        return ExecutionResult(order.id, "awaiting_approval",
                               ["live orders need a named person to approve each one"], broker.name)

    try:
        fill = broker.submit(session, order)
    except BrokerReject as exc:
        audit.record(session, actor=actor, entity_type="order", entity_id=order.id, action="broker_rejected",
                     detail={"broker": broker.name, "reason": str(exc)})
        session.commit()
        return ExecutionResult(order.id, "blocked", [f"broker: {exc}"], broker.name)

    oms.fill_order(session, order.id, fill.quantity, fill.price, actor=actor, filled_at=fill.filled_at, fees=fill.fees)
    audit.record(session, actor=actor, entity_type="order", entity_id=order.id, action="executed",
                 detail={"broker": broker.name, "live": broker.live, "approved_by": approved_by,
                         "quantity": fill.quantity, "price": fill.price, "broker_order_id": fill.broker_order_id})
    session.commit()
    return ExecutionResult(order.id, "executed", [], broker.name, fill.quantity, fill.price)
