"""Pydantic models for the REST API."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field

from lantern.models import AssetClass, OrderType, Severity, Side


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# --- reference data


class SecurityIn(BaseModel):
    ticker: str
    name: str
    asset_class: AssetClass
    currency: str = Field(min_length=3, max_length=3)
    sector: str | None = None
    country: str | None = None
    issuer: str | None = None
    multiplier: float = 1.0
    coupon_rate: float | None = None
    coupon_frequency: int | None = None
    maturity_date: date | None = None
    face_value: float | None = None


class SecurityOut(ORMModel):
    id: int
    ticker: str
    name: str
    asset_class: str
    currency: str
    sector: str | None
    country: str | None
    issuer: str | None
    multiplier: float
    coupon_rate: float | None
    coupon_frequency: int | None
    maturity_date: date | None
    face_value: float | None


class PriceIn(BaseModel):
    security_id: int
    date: date
    close: float


class PricesBulkIn(BaseModel):
    prices: list[PriceIn]


class PriceOut(ORMModel):
    security_id: int
    date: date
    close: float


class FxRateIn(BaseModel):
    base_currency: str
    quote_currency: str
    date: date
    rate: float


# --- portfolios


class BenchmarkWeightIn(BaseModel):
    security_id: int
    weight: float


class BenchmarkIn(BaseModel):
    name: str
    weights: list[BenchmarkWeightIn]


class BenchmarkOut(ORMModel):
    id: int
    name: str


class PortfolioIn(BaseModel):
    name: str
    base_currency: str = "USD"
    benchmark_id: int | None = None


class PortfolioOut(ORMModel):
    id: int
    name: str
    base_currency: str
    benchmark_id: int | None
    created_at: datetime


class CashFlowIn(BaseModel):
    date: date
    amount: float
    memo: str | None = None


class TradeIn(BaseModel):
    security_id: int
    side: Side
    quantity: float = Field(gt=0)
    price: float
    trade_date: date
    currency: str | None = None  # defaults to the security's currency
    fees: float = 0.0


class TradeOut(ORMModel):
    id: int
    portfolio_id: int
    security_id: int
    order_id: int | None
    side: str
    quantity: float
    price: float
    currency: str
    fees: float
    trade_date: date


class ProposedTradeIn(BaseModel):
    security_id: int
    side: Side
    quantity: float = Field(gt=0)
    price: float | None = None


class WhatIfIn(BaseModel):
    trades: list[ProposedTradeIn]
    as_of: date | None = None


# --- compliance


class RuleIn(BaseModel):
    portfolio_id: int | None = None
    name: str
    rule_type: str
    params: dict = Field(default_factory=dict)
    severity: Severity = Severity.HARD
    active: bool = True


class RuleOut(ORMModel):
    id: int
    portfolio_id: int | None
    name: str
    rule_type: str
    params: dict
    severity: str
    active: bool


# --- trading


class OrderIn(BaseModel):
    portfolio_id: int
    security_id: int
    side: Side
    quantity: float = Field(gt=0)
    order_type: OrderType = OrderType.MARKET
    limit_price: float | None = None
    actor: str = "api"


class FillIn(BaseModel):
    quantity: float = Field(gt=0)
    price: float = Field(gt=0)
    fees: float = 0.0
    actor: str = "api"


class FillOut(ORMModel):
    id: int
    quantity: float
    price: float
    filled_at: datetime


class OrderOut(ORMModel):
    id: int
    portfolio_id: int
    security_id: int
    side: str
    quantity: float
    order_type: str
    limit_price: float | None
    status: str
    filled_quantity: float
    avg_fill_price: float | None
    reject_reason: str | None
    compliance_summary: dict | None
    created_by: str
    created_at: datetime
    updated_at: datetime
    fills: list[FillOut] = []


# --- risk


class ScenarioIn(BaseModel):
    name: str
    description: str = ""
    shocks: dict[str, dict[str, float]] = Field(default_factory=dict)
    rates_bp: float = 0.0


class AuditOut(ORMModel):
    id: int
    at: datetime
    actor: str
    entity_type: str
    entity_id: int | None
    action: str
    detail: dict | None
