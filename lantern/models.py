"""The shared book of record.

Every module (portfolio, risk, compliance, trading) reads from these tables. Positions are
never stored: they are derived from the trade ledger and cash flows, so there is exactly one
source of truth for what a portfolio holds.
"""

from __future__ import annotations

import enum
from datetime import UTC, date, datetime

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from lantern.db import Base


def utcnow() -> datetime:
    return datetime.now(UTC)


# --------------------------------------------------------------------------- enums


class AssetClass(str, enum.Enum):
    EQUITY = "Equity"
    FIXED_INCOME = "Fixed Income"
    FUND = "Fund"
    COMMODITY = "Commodity"
    CASH = "Cash"


class Side(str, enum.Enum):
    BUY = "BUY"
    SELL = "SELL"


class OrderType(str, enum.Enum):
    MARKET = "MARKET"
    LIMIT = "LIMIT"


class OrderStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    PARTIALLY_FILLED = "PARTIALLY_FILLED"
    FILLED = "FILLED"
    CANCELLED = "CANCELLED"


class Severity(str, enum.Enum):
    HARD = "HARD"  # blocks the order
    SOFT = "SOFT"  # warns, order proceeds


class CheckStage(str, enum.Enum):
    PRE_TRADE = "PRE_TRADE"
    POST_TRADE = "POST_TRADE"


# --------------------------------------------------------------------------- reference data


class Security(Base):
    __tablename__ = "securities"

    id: Mapped[int] = mapped_column(primary_key=True)
    ticker: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(200))
    asset_class: Mapped[str] = mapped_column(String(32))
    currency: Mapped[str] = mapped_column(String(3))
    sector: Mapped[str | None] = mapped_column(String(64))
    country: Mapped[str | None] = mapped_column(String(2))
    issuer: Mapped[str | None] = mapped_column(String(200))
    # Market value = quantity * price * multiplier. Bonds quote per 100 face, so 0.01.
    multiplier: Mapped[float] = mapped_column(Float, default=1.0)

    # Fixed-income terms (null for everything else)
    coupon_rate: Mapped[float | None] = mapped_column(Float)
    coupon_frequency: Mapped[int | None] = mapped_column(Integer)
    maturity_date: Mapped[date | None] = mapped_column(Date)
    face_value: Mapped[float | None] = mapped_column(Float)

    prices: Mapped[list[Price]] = relationship(back_populates="security", cascade="all, delete-orphan")

    def is_fixed_income(self) -> bool:
        return self.asset_class == AssetClass.FIXED_INCOME.value


class Price(Base):
    __tablename__ = "prices"
    __table_args__ = (UniqueConstraint("security_id", "date", name="uq_price_security_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id", ondelete="CASCADE"), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    close: Mapped[float] = mapped_column(Float)

    security: Mapped[Security] = relationship(back_populates="prices")


class FxRate(Base):
    """1 unit of `base_currency` = `rate` units of `quote_currency`."""

    __tablename__ = "fx_rates"
    __table_args__ = (UniqueConstraint("base_currency", "quote_currency", "date", name="uq_fx"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    base_currency: Mapped[str] = mapped_column(String(3))
    quote_currency: Mapped[str] = mapped_column(String(3))
    date: Mapped[date] = mapped_column(Date, index=True)
    rate: Mapped[float] = mapped_column(Float)


class FactorReturn(Base):
    """Daily returns of risk factors used by the factor model (market, rates, credit, ...)."""

    __tablename__ = "factor_returns"
    __table_args__ = (UniqueConstraint("factor", "date", name="uq_factor_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    factor: Mapped[str] = mapped_column(String(32), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    value: Mapped[float] = mapped_column(Float)


# --------------------------------------------------------------------------- portfolios


class Benchmark(Base):
    __tablename__ = "benchmarks"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), unique=True)
    weights: Mapped[list[BenchmarkWeight]] = relationship(
        back_populates="benchmark", cascade="all, delete-orphan"
    )


class BenchmarkWeight(Base):
    __tablename__ = "benchmark_weights"
    __table_args__ = (UniqueConstraint("benchmark_id", "security_id", name="uq_bench_sec"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    benchmark_id: Mapped[int] = mapped_column(ForeignKey("benchmarks.id", ondelete="CASCADE"))
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"))
    weight: Mapped[float] = mapped_column(Float)

    benchmark: Mapped[Benchmark] = relationship(back_populates="weights")
    security: Mapped[Security] = relationship()


class Portfolio(Base):
    __tablename__ = "portfolios"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(200), unique=True)
    base_currency: Mapped[str] = mapped_column(String(3), default="USD")
    benchmark_id: Mapped[int | None] = mapped_column(ForeignKey("benchmarks.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    benchmark: Mapped[Benchmark | None] = relationship()


class CashFlow(Base):
    """External cash movements in the portfolio's base currency (subscriptions, redemptions)."""

    __tablename__ = "cash_flows"

    id: Mapped[int] = mapped_column(primary_key=True)
    portfolio_id: Mapped[int] = mapped_column(ForeignKey("portfolios.id"), index=True)
    date: Mapped[date] = mapped_column(Date, index=True)
    amount: Mapped[float] = mapped_column(Float)
    memo: Mapped[str | None] = mapped_column(String(200))


# --------------------------------------------------------------------------- trading


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True)
    portfolio_id: Mapped[int] = mapped_column(ForeignKey("portfolios.id"), index=True)
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"), index=True)
    side: Mapped[str] = mapped_column(String(4))
    quantity: Mapped[float] = mapped_column(Float)
    order_type: Mapped[str] = mapped_column(String(8), default=OrderType.MARKET.value)
    limit_price: Mapped[float | None] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(20), default=OrderStatus.PENDING.value, index=True)
    filled_quantity: Mapped[float] = mapped_column(Float, default=0.0)
    avg_fill_price: Mapped[float | None] = mapped_column(Float)
    reject_reason: Mapped[str | None] = mapped_column(Text)
    compliance_summary: Mapped[dict | None] = mapped_column(JSON)
    created_by: Mapped[str] = mapped_column(String(100), default="system")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )

    security: Mapped[Security] = relationship()
    portfolio: Mapped[Portfolio] = relationship()
    fills: Mapped[list[Fill]] = relationship(back_populates="order", cascade="all, delete-orphan")

    @property
    def remaining_quantity(self) -> float:
        return max(self.quantity - self.filled_quantity, 0.0)


class Fill(Base):
    __tablename__ = "fills"

    id: Mapped[int] = mapped_column(primary_key=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), index=True)
    quantity: Mapped[float] = mapped_column(Float)
    price: Mapped[float] = mapped_column(Float)
    filled_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    order: Mapped[Order] = relationship(back_populates="fills")


class Trade(Base):
    """The ledger. Every fill, and every imported historical transaction, lands here."""

    __tablename__ = "trades"
    __table_args__ = (Index("ix_trade_portfolio_date", "portfolio_id", "trade_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    portfolio_id: Mapped[int] = mapped_column(ForeignKey("portfolios.id"), index=True)
    security_id: Mapped[int] = mapped_column(ForeignKey("securities.id"), index=True)
    order_id: Mapped[int | None] = mapped_column(ForeignKey("orders.id"))
    side: Mapped[str] = mapped_column(String(4))
    quantity: Mapped[float] = mapped_column(Float)
    price: Mapped[float] = mapped_column(Float)
    currency: Mapped[str] = mapped_column(String(3))
    fees: Mapped[float] = mapped_column(Float, default=0.0)
    trade_date: Mapped[date] = mapped_column(Date)
    settle_date: Mapped[date | None] = mapped_column(Date)

    security: Mapped[Security] = relationship()

    @property
    def signed_quantity(self) -> float:
        return self.quantity if self.side == Side.BUY.value else -self.quantity


# --------------------------------------------------------------------------- compliance & audit


class ComplianceRule(Base):
    """A rule scoped to one portfolio, or firm-wide when portfolio_id is null."""

    __tablename__ = "compliance_rules"

    id: Mapped[int] = mapped_column(primary_key=True)
    portfolio_id: Mapped[int | None] = mapped_column(ForeignKey("portfolios.id"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    rule_type: Mapped[str] = mapped_column(String(64))
    params: Mapped[dict] = mapped_column(JSON, default=dict)
    severity: Mapped[str] = mapped_column(String(8), default=Severity.HARD.value)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class ComplianceCheck(Base):
    __tablename__ = "compliance_checks"

    id: Mapped[int] = mapped_column(primary_key=True)
    portfolio_id: Mapped[int] = mapped_column(ForeignKey("portfolios.id"), index=True)
    order_id: Mapped[int | None] = mapped_column(ForeignKey("orders.id"))
    stage: Mapped[str] = mapped_column(String(16))
    as_of: Mapped[date] = mapped_column(Date)
    run_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    passed: Mapped[bool] = mapped_column(Boolean)
    blocked: Mapped[bool] = mapped_column(Boolean, default=False)
    breaches: Mapped[list] = mapped_column(JSON, default=list)


class AuditEvent(Base):
    __tablename__ = "audit_events"

    id: Mapped[int] = mapped_column(primary_key=True)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(100))
    entity_type: Mapped[str] = mapped_column(String(64), index=True)
    entity_id: Mapped[int | None] = mapped_column(Integer, index=True)
    action: Mapped[str] = mapped_column(String(64))
    detail: Mapped[dict | None] = mapped_column(JSON)
