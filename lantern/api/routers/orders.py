from __future__ import annotations

from fastapi import APIRouter

from lantern.api.deps import DB
from lantern.models import Order, OrderStatus
from lantern.schemas import FillIn, OrderIn, OrderOut
from lantern.trading import oms

router = APIRouter(prefix="/orders", tags=["trading"])


@router.get("", response_model=list[OrderOut])
def blotter(db: DB, portfolio_id: int | None = None, status: OrderStatus | None = None, limit: int = 200):
    return oms.blotter(db, portfolio_id, status, limit)


@router.post("", response_model=OrderOut, status_code=201)
def create(body: OrderIn, db: DB):
    """Create an order. It is run through pre-trade compliance and comes back APPROVED or REJECTED."""
    return oms.create_order(
        db,
        portfolio_id=body.portfolio_id,
        security_id=body.security_id,
        side=body.side,
        quantity=body.quantity,
        order_type=body.order_type,
        limit_price=body.limit_price,
        actor=body.actor,
    )


@router.get("/{order_id}", response_model=OrderOut)
def get(order_id: int, db: DB):
    o = db.get(Order, order_id)
    if o is None:
        raise LookupError(f"Order {order_id} not found")
    return o


@router.post("/{order_id}/fills", response_model=OrderOut)
def fill(order_id: int, body: FillIn, db: DB):
    oms.fill_order(db, order_id, body.quantity, body.price, actor=body.actor, fees=body.fees)
    return db.get(Order, order_id)


@router.post("/{order_id}/cancel", response_model=OrderOut)
def cancel(order_id: int, db: DB, reason: str | None = None, actor: str = "api"):
    return oms.cancel_order(db, order_id, actor=actor, reason=reason)
