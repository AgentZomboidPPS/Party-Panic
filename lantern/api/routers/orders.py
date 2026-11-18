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


@router.post("/{order_id}/execute")
def execute(order_id: int, db: DB, slippage_bps: float = 0.0, actor: str = "api") -> dict:
    """Fill an approved order with the paper broker, subject to trading limits and the kill switch."""
    from lantern.execution.brokers import PaperBroker
    from lantern.execution.guard import execute as _execute

    return _execute(db, order_id, PaperBroker(slippage_bps), actor=actor).to_dict()


trading_router = APIRouter(prefix="/trading", tags=["trading"])


@trading_router.get("/status")
def trading_status(db: DB) -> dict:
    from dataclasses import asdict

    from lantern.execution.guard import TradingLimits, halt_state

    h = halt_state(db)
    db.commit()
    lim = asdict(TradingLimits.from_settings())
    lim["allowed_symbols"] = sorted(lim["allowed_symbols"])
    return {"halted": h.halted, "halt_reason": h.reason, "halted_by": h.updated_by, "limits": lim}


@trading_router.post("/halt")
def trading_halt(db: DB, reason: str = "manual halt", actor: str = "api") -> dict:
    from lantern.execution.guard import set_halt

    return {"halted": set_halt(db, True, actor, reason).halted, "reason": reason}


@trading_router.post("/resume")
def trading_resume(db: DB, actor: str = "api") -> dict:
    from lantern.execution.guard import set_halt

    return {"halted": set_halt(db, False, actor).halted}
