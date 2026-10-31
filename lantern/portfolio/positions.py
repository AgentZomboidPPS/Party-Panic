"""Positions derived from the trade ledger, valued at the latest prices in base currency."""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import date

import pandas as pd
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from lantern.marketdata.fx import fx_rate
from lantern.marketdata.prices import latest_price_date, latest_prices
from lantern.models import CashFlow, Portfolio, Security, Side, Trade

POSITION_COLUMNS = [
    "ticker",
    "name",
    "asset_class",
    "sector",
    "country",
    "currency",
    "issuer",
    "quantity",
    "price",
    "multiplier",
    "fx_rate",
    "market_value",
    "weight",
]

EPS = 1e-9


@dataclass
class ValuedPositions:
    portfolio_id: int
    portfolio_name: str
    as_of: date
    base_currency: str
    positions: pd.DataFrame  # indexed by security_id, columns = POSITION_COLUMNS
    cash: float

    @property
    def securities_value(self) -> float:
        return float(self.positions["market_value"].sum()) if len(self.positions) else 0.0

    @property
    def total_value(self) -> float:
        return self.securities_value + self.cash

    @property
    def cash_weight(self) -> float:
        return self.cash / self.total_value if self.total_value else 0.0

    def weights(self) -> pd.Series:
        """Security weights relative to total portfolio value (cash included in denominator)."""
        return self.positions["weight"].astype(float)

    def copy(self) -> ValuedPositions:
        return replace(self, positions=self.positions.copy())

    def to_dict(self) -> dict:
        rows = self.positions.reset_index().rename(columns={"index": "security_id"})
        return {
            "portfolio_id": self.portfolio_id,
            "portfolio_name": self.portfolio_name,
            "as_of": self.as_of.isoformat(),
            "base_currency": self.base_currency,
            "cash": self.cash,
            "cash_weight": self.cash_weight,
            "securities_value": self.securities_value,
            "total_value": self.total_value,
            "positions": rows.to_dict(orient="records"),
        }


def empty_positions_frame() -> pd.DataFrame:
    df = pd.DataFrame(columns=POSITION_COLUMNS)
    df.index.name = "security_id"
    return df


def securities_value_of(df: pd.DataFrame) -> float:
    if len(df) == 0:
        return 0.0
    return float((df["quantity"] * df["price"] * df["multiplier"] * df["fx_rate"]).sum())


def reweight(df: pd.DataFrame, total_value: float) -> pd.DataFrame:
    df = df.copy()
    df["market_value"] = df["quantity"] * df["price"] * df["multiplier"] * df["fx_rate"]
    df["weight"] = df["market_value"] / total_value if total_value else 0.0
    return df


def holdings(session: Session, portfolio_id: int, as_of: date) -> pd.Series:
    """Net quantity per security from all trades dated on or before `as_of`."""
    signed = case((Trade.side == Side.BUY.value, Trade.quantity), else_=-Trade.quantity)
    rows = session.execute(
        select(Trade.security_id, func.sum(signed))
        .where(Trade.portfolio_id == portfolio_id, Trade.trade_date <= as_of)
        .group_by(Trade.security_id)
    ).all()
    s = pd.Series({sid: float(q) for sid, q in rows}, dtype=float)
    return s[s.abs() > EPS]


def cash_balance(session: Session, portfolio_id: int, as_of: date, base_currency: str) -> float:
    """External cash flows minus the cost of every trade, in base currency."""
    flows = session.execute(
        select(func.coalesce(func.sum(CashFlow.amount), 0.0)).where(
            CashFlow.portfolio_id == portfolio_id, CashFlow.date <= as_of
        )
    ).scalar_one()
    cash = float(flows)
    trades = session.execute(
        select(Trade, Security.multiplier)
        .join(Security, Security.id == Trade.security_id)
        .where(Trade.portfolio_id == portfolio_id, Trade.trade_date <= as_of)
    ).all()
    for trade, multiplier in trades:
        fx = fx_rate(session, trade.currency, base_currency, trade.trade_date)
        cash -= (trade.signed_quantity * trade.price * multiplier + trade.fees) * fx
    return cash


def security_map(session: Session, security_ids) -> dict[int, Security]:
    ids = list(security_ids)
    if not ids:
        return {}
    return {
        s.id: s
        for s in session.execute(select(Security).where(Security.id.in_(ids))).scalars()
    }


def position_row(sec: Security, quantity: float, price: float, fx: float) -> dict:
    return {
        "ticker": sec.ticker,
        "name": sec.name,
        "asset_class": sec.asset_class,
        "sector": sec.sector or "Unclassified",
        "country": sec.country or "Unclassified",
        "currency": sec.currency,
        "issuer": sec.issuer or sec.name,
        "quantity": float(quantity),
        "price": float(price),
        "multiplier": float(sec.multiplier),
        "fx_rate": float(fx),
        "market_value": 0.0,
        "weight": 0.0,
    }


def value_portfolio(session: Session, portfolio_id: int, as_of: date | None = None) -> ValuedPositions:
    portfolio = session.get(Portfolio, portfolio_id)
    if portfolio is None:
        raise LookupError(f"Portfolio {portfolio_id} not found")
    if as_of is None:
        as_of = latest_price_date(session) or date.today()

    qty = holdings(session, portfolio_id, as_of)
    secs = security_map(session, qty.index)
    prices = latest_prices(session, qty.index, as_of)

    rows: dict[int, dict] = {}
    for sid, q in qty.items():
        sec = secs[sid]
        if sid not in prices.index:
            raise LookupError(f"No price for {sec.ticker} on or before {as_of}")
        fx = fx_rate(session, sec.currency, portfolio.base_currency, as_of)
        rows[sid] = position_row(sec, q, prices[sid], fx)

    df = pd.DataFrame.from_dict(rows, orient="index", columns=POSITION_COLUMNS) if rows else empty_positions_frame()
    df.index.name = "security_id"
    cash = cash_balance(session, portfolio_id, as_of, portfolio.base_currency)
    df = reweight(df, securities_value_of(df) + cash)

    return ValuedPositions(
        portfolio_id=portfolio.id,
        portfolio_name=portfolio.name,
        as_of=as_of,
        base_currency=portfolio.base_currency,
        positions=df,
        cash=cash,
    )
