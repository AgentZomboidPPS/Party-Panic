from __future__ import annotations

from datetime import date

from sqlalchemy import Date, Float, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from spectre.db import Base


class YieldPoint(Base):
    """One maturity on one day of the Treasury par yield curve. `value` is in percent."""

    __tablename__ = "yield_curve"
    __table_args__ = (UniqueConstraint("date", "tenor", name="uq_yield_point"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    tenor: Mapped[str] = mapped_column(String(8), index=True)
    years: Mapped[float] = mapped_column(Float)
    value: Mapped[float] = mapped_column(Float)


class MacroSeries(Base):
    """A daily economic series by its FRED id (credit spreads, policy rate, breakevens...)."""

    __tablename__ = "macro_series"
    __table_args__ = (UniqueConstraint("series", "date", name="uq_macro_point"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    series: Mapped[str] = mapped_column(String(32), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    value: Mapped[float] = mapped_column(Float)
