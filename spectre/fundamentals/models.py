from __future__ import annotations

from datetime import date

from sqlalchemy import Boolean, Date, Float, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from spectre.db import Base


class Fundamental(Base):
    """One metric for one fiscal quarter of one company."""

    __tablename__ = "fundamentals"
    __table_args__ = (UniqueConstraint("security_id", "metric", "period_end", name="uq_fundamental"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"), index=True)
    ticker: Mapped[str] = mapped_column(String(32), index=True)
    metric: Mapped[str] = mapped_column(String(32), index=True)
    period_start: Mapped[date] = mapped_column(Date)
    period_end: Mapped[date] = mapped_column(Date, index=True)
    value: Mapped[float] = mapped_column(Float)
    fiscal_year: Mapped[int | None] = mapped_column(Integer)
    fiscal_period: Mapped[str | None] = mapped_column(String(4))
    form: Mapped[str | None] = mapped_column(String(8))
    filed: Mapped[date | None] = mapped_column(Date)
    derived: Mapped[bool] = mapped_column(Boolean, default=False)  # computed by subtraction, not reported directly
