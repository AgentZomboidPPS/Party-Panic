"""Brokers. A broker turns an order into a fill, or says why it could not.

`PaperBroker` is the only one here. A live broker is one more class with the same two
attributes and one method; it must use the broker's official API with a scoped, revocable key,
never an account password.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time
from typing import Protocol

from sqlalchemy.orm import Session

from lantern.marketdata.prices import latest_price_date, latest_prices
from lantern.models import Order, OrderType, Side
from lantern.signals.sources.base import utcnow


@dataclass
class BrokerFill:
    quantity: float
    price: float
    filled_at: datetime
    fees: float = 0.0
    broker_order_id: str | None = None


class BrokerReject(Exception):
    """The broker did not fill the order; the message says why."""


class Broker(Protocol):
    name: str
    live: bool  # True when fills move real money

    def submit(self, session: Session, order: Order) -> BrokerFill: ...


class PaperBroker:
    """Fills the whole order at the latest known price, plus optional slippage against you."""

    name = "paper"
    live = False

    def __init__(self, slippage_bps: float = 0.0):
        self.slippage_bps = slippage_bps

    def submit(self, session: Session, order: Order) -> BrokerFill:
        as_of = latest_price_date(session) or date.today()
        px = latest_prices(session, [order.security_id], as_of)
        if order.security_id not in px.index:
            raise BrokerReject("no price available to fill against")
        slip = self.slippage_bps / 10_000.0
        price = float(px[order.security_id]) * (1 + slip if order.side == Side.BUY.value else 1 - slip)
        if order.order_type == OrderType.LIMIT.value and order.limit_price is not None:
            if order.side == Side.BUY.value and price > order.limit_price:
                raise BrokerReject(f"market {price:.2f} is above the buy limit {order.limit_price:.2f}")
            if order.side == Side.SELL.value and price < order.limit_price:
                raise BrokerReject(f"market {price:.2f} is below the sell limit {order.limit_price:.2f}")
        now = utcnow()
        # With historical data the "latest price" can be days old: stamp the fill on that day so
        # the position shows up when the book is valued as of the data.
        filled_at = now if as_of >= now.date() else datetime.combine(as_of, time(20, 0))
        return BrokerFill(order.remaining_quantity, price, filled_at)
