"""Order management: create -> pre-trade compliance -> approve/reject -> fill -> ledger.

Every state change writes an audit event. Fills create Trade rows, which is the only way
positions ever change through the OMS.
"""

from __future__ import annotations

from datetime import UTC, date, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern import audit
from lantern.compliance.engine import pre_trade_check
from lantern.marketdata.prices import latest_price_date, latest_prices
from lantern.models import Fill, Order, OrderStatus, OrderType, Portfolio, Security, Side, Trade
from lantern.portfolio.whatif import ProposedTrade

EPS = 1e-9


class OrderError(Exception):
    pass


def _set_status(session: Session, order: Order, status: OrderStatus, actor: str, detail: dict | None = None) -> None:
    prev = order.status
    order.status = status.value
    audit.record(
        session,
        actor=actor,
        entity_type="order",
        entity_id=order.id,
        action=f"status:{prev}->{status.value}",
        detail=detail,
    )


def create_order(
    session: Session,
    *,
    portfolio_id: int,
    security_id: int,
    side: Side,
    quantity: float,
    order_type: OrderType = OrderType.MARKET,
    limit_price: float | None = None,
    actor: str = "system",
    as_of: date | None = None,
) -> Order:
    if quantity <= 0:
        raise OrderError("Order quantity must be positive")
    if order_type == OrderType.LIMIT and limit_price is None:
        raise OrderError("Limit orders need a limit price")
    if session.get(Portfolio, portfolio_id) is None:
        raise OrderError(f"Portfolio {portfolio_id} not found")
    security = session.get(Security, security_id)
    if security is None:
        raise OrderError(f"Security {security_id} not found")

    order = Order(
        portfolio_id=portfolio_id,
        security_id=security_id,
        side=side.value,
        quantity=float(quantity),
        order_type=order_type.value,
        limit_price=limit_price,
        status=OrderStatus.PENDING.value,
        created_by=actor,
    )
    session.add(order)
    session.flush()
    audit.record(
        session, actor=actor, entity_type="order", entity_id=order.id, action="created",
        detail={"side": side.value, "quantity": quantity, "security": security.ticker,
                "order_type": order_type.value, "limit_price": limit_price},
    )

    as_of = as_of or latest_price_date(session) or date.today()
    ref_price = limit_price
    if ref_price is None:
        px = latest_prices(session, [security_id], as_of)
        ref_price = float(px[security_id]) if security_id in px.index else None
    if ref_price is None:
        order.reject_reason = f"No reference price for {security.ticker} on or before {as_of}"
        _set_status(session, order, OrderStatus.REJECTED, actor, {"reason": order.reject_reason})
        session.commit()
        return order

    check = pre_trade_check(
        session, portfolio_id,
        [ProposedTrade(security_id, side, float(quantity), ref_price)],
        as_of=as_of, order_id=order.id,
    )
    order.compliance_summary = check.to_dict()
    if check.blocked:
        reasons = [b.message for b in check.new_breaches if b.severity.value == "HARD"]
        order.reject_reason = "; ".join(reasons)
        _set_status(session, order, OrderStatus.REJECTED, actor, {"breaches": reasons})
    else:
        warnings = [b.message for b in check.warnings]
        _set_status(session, order, OrderStatus.APPROVED, actor, {"warnings": warnings})
    session.commit()
    return order


def fill_order(
    session: Session,
    order_id: int,
    quantity: float,
    price: float,
    actor: str = "system",
    filled_at: datetime | None = None,
    fees: float = 0.0,
) -> Fill:
    order = session.get(Order, order_id)
    if order is None:
        raise OrderError(f"Order {order_id} not found")
    if order.status not in (OrderStatus.APPROVED.value, OrderStatus.PARTIALLY_FILLED.value):
        raise OrderError(f"Order {order_id} is {order.status}; only approved orders can be filled")
    if quantity <= 0:
        raise OrderError("Fill quantity must be positive")
    if quantity > order.remaining_quantity + EPS:
        raise OrderError(
            f"Fill of {quantity} exceeds remaining {order.remaining_quantity} on order {order_id}"
        )
    if order.order_type == OrderType.LIMIT.value and order.limit_price is not None:
        if order.side == Side.BUY.value and price > order.limit_price + EPS:
            raise OrderError(f"Buy fill at {price} is above limit {order.limit_price}")
        if order.side == Side.SELL.value and price < order.limit_price - EPS:
            raise OrderError(f"Sell fill at {price} is below limit {order.limit_price}")

    filled_at = filled_at or datetime.now(UTC)
    fill = Fill(order_id=order.id, quantity=float(quantity), price=float(price), filled_at=filled_at)
    session.add(fill)

    security = session.get(Security, order.security_id)
    trade = Trade(
        portfolio_id=order.portfolio_id,
        security_id=order.security_id,
        order_id=order.id,
        side=order.side,
        quantity=float(quantity),
        price=float(price),
        currency=security.currency,
        fees=float(fees),
        trade_date=filled_at.date(),
    )
    session.add(trade)

    prev_filled = order.filled_quantity
    new_filled = prev_filled + float(quantity)
    order.avg_fill_price = (
        ((order.avg_fill_price or 0.0) * prev_filled + price * quantity) / new_filled
    )
    order.filled_quantity = new_filled
    status = OrderStatus.FILLED if order.remaining_quantity <= EPS else OrderStatus.PARTIALLY_FILLED
    _set_status(session, order, status, actor, {"fill_quantity": quantity, "price": price})
    session.commit()
    return fill


def cancel_order(session: Session, order_id: int, actor: str = "system", reason: str | None = None) -> Order:
    order = session.get(Order, order_id)
    if order is None:
        raise OrderError(f"Order {order_id} not found")
    if order.status in (OrderStatus.FILLED.value, OrderStatus.REJECTED.value, OrderStatus.CANCELLED.value):
        raise OrderError(f"Order {order_id} is {order.status} and cannot be cancelled")
    _set_status(session, order, OrderStatus.CANCELLED, actor, {"reason": reason})
    session.commit()
    return order


def blotter(
    session: Session, portfolio_id: int | None = None, status: OrderStatus | None = None, limit: int = 200
) -> list[Order]:
    q = select(Order).order_by(Order.id.desc()).limit(limit)
    if portfolio_id is not None:
        q = q.where(Order.portfolio_id == portfolio_id)
    if status is not None:
        q = q.where(Order.status == status.value)
    return list(session.execute(q).scalars())
