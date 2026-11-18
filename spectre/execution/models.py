from __future__ import annotations

from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, Float, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from spectre.db import Base


class TradingControl(Base):
    """One row: the kill switch. Stored in the database so it holds across every process."""

    __tablename__ = "trading_control"

    id: Mapped[int] = mapped_column(primary_key=True)
    halted: Mapped[bool] = mapped_column(Boolean, default=False)
    reason: Mapped[str | None] = mapped_column(Text)
    updated_at: Mapped[datetime | None] = mapped_column(DateTime)
    updated_by: Mapped[str | None] = mapped_column(String(100))


class OptionMark(Base):
    """Latest quote and greeks of an option contract. One row per contract, overwritten on each sync.

    Risk views need the greeks: an option's sensitivity to its underlying is not in its price.
    """

    __tablename__ = "option_marks"

    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"), primary_key=True)
    underlying: Mapped[str] = mapped_column(String(32), index=True)
    option_type: Mapped[str] = mapped_column(String(4))
    strike: Mapped[float] = mapped_column(Float)
    expiration: Mapped[date] = mapped_column(Date)
    as_of: Mapped[datetime] = mapped_column(DateTime)
    bid: Mapped[float | None] = mapped_column(Float)
    ask: Mapped[float | None] = mapped_column(Float)
    mark: Mapped[float | None] = mapped_column(Float)
    implied_volatility: Mapped[float | None] = mapped_column(Float)
    delta: Mapped[float | None] = mapped_column(Float)
    gamma: Mapped[float | None] = mapped_column(Float)
    theta: Mapped[float | None] = mapped_column(Float)
    vega: Mapped[float | None] = mapped_column(Float)
    underlying_price: Mapped[float | None] = mapped_column(Float)
