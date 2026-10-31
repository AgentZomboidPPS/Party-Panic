"""Deterministic demo universe.

Prices are generated from a known linear factor model (market, rates, credit, size, EURUSD),
so the factor-model estimates and risk numbers can be checked against the truth that produced
them. Everything is seeded; the same seed gives the same database.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

import numpy as np
import pandas as pd
from sqlalchemy import insert
from sqlalchemy.orm import Session

from lantern.models import (
    AssetClass,
    Benchmark,
    BenchmarkWeight,
    CashFlow,
    ComplianceRule,
    FactorReturn,
    FxRate,
    Portfolio,
    Price,
    Security,
    Severity,
    Side,
    Trade,
)
from lantern.trading import oms

FACTORS = ["MKT", "RATES", "CREDIT", "SIZE", "EURUSD"]
FACTOR_MEAN = {"MKT": 0.0004, "RATES": 0.0, "CREDIT": 0.0, "SIZE": 0.0, "EURUSD": 0.0}
# Daily vols: equities ~17% ann., yields ~4.5bp/day, IG spreads ~4bp/day, EURUSD ~7% ann.
FACTOR_VOL = {"MKT": 0.011, "RATES": 0.00045, "CREDIT": 0.0004, "SIZE": 0.005, "EURUSD": 0.0045}


@dataclass
class SecSpec:
    ticker: str
    name: str
    asset_class: AssetClass
    currency: str
    sector: str
    country: str
    issuer: str
    start_price: float
    idio_vol: float
    mkt_beta: float = 0.0
    size_beta: float = 0.0
    duration: float = 0.0
    spread_duration: float = 0.0
    drift: float = 0.0
    multiplier: float = 1.0
    coupon_rate: float | None = None
    maturity_years: float | None = None
    freq: int | None = None


EQ = AssetClass.EQUITY
FI = AssetClass.FIXED_INCOME

UNIVERSE: list[SecSpec] = [
    # US equities
    SecSpec("ACME", "Acme Systems", EQ, "USD", "Technology", "US", "Acme Systems", 180, 0.014, 1.25, -0.2, drift=0.0002),
    SecSpec("BYTE", "Bytefield Software", EQ, "USD", "Technology", "US", "Bytefield Software", 95, 0.018, 1.35, 0.3),
    SecSpec("NOVA", "Nova Semiconductors", EQ, "USD", "Technology", "US", "Nova Semiconductors", 60, 0.022, 1.50, 0.4, drift=0.0003),
    SecSpec("HLTH", "Helix Health", EQ, "USD", "Health Care", "US", "Helix Health", 140, 0.011, 0.75, -0.1),
    SecSpec("PHRM", "Pharmos Labs", EQ, "USD", "Health Care", "US", "Pharmos Labs", 42, 0.016, 0.85, 0.5),
    SecSpec("BANK", "Meridian Bancorp", EQ, "USD", "Financials", "US", "Meridian Bancorp", 55, 0.013, 1.10, 0.0),
    SecSpec("INSR", "Keystone Insurance", EQ, "USD", "Financials", "US", "Keystone Insurance", 88, 0.010, 0.80, -0.1),
    SecSpec("SHOP", "Cartwheel Retail", EQ, "USD", "Consumer Discretionary", "US", "Cartwheel Retail", 120, 0.015, 1.15, 0.2),
    SecSpec("FOOD", "Harvest Foods", EQ, "USD", "Consumer Staples", "US", "Harvest Foods", 70, 0.008, 0.55, -0.2),
    SecSpec("OILX", "Ridgeline Energy", EQ, "USD", "Energy", "US", "Ridgeline Energy", 48, 0.017, 0.90, 0.1),
    SecSpec("UTIL", "Northgrid Utilities", EQ, "USD", "Utilities", "US", "Northgrid Utilities", 65, 0.009, 0.45, -0.3, duration=2.0),
    SecSpec("INDS", "Ironworks Industrial", EQ, "USD", "Industrials", "US", "Ironworks Industrial", 102, 0.012, 1.05, 0.1),
    SecSpec("SMKE", "Ashfield Tobacco", EQ, "USD", "Consumer Staples", "US", "Ashfield Tobacco", 38, 0.010, 0.50, -0.2),
    # European equities (priced in EUR)
    SecSpec("LUXE", "Maison Luxe", EQ, "EUR", "Consumer Discretionary", "FR", "Maison Luxe", 410, 0.013, 1.00, -0.2),
    SecSpec("AUTO", "Rheinmotor AG", EQ, "EUR", "Consumer Discretionary", "DE", "Rheinmotor AG", 76, 0.015, 1.10, 0.1),
    SecSpec("PHAR", "Nordpharm NV", EQ, "EUR", "Health Care", "NL", "Nordpharm NV", 58, 0.012, 0.80, 0.0),
    # Fixed income (quoted per 100 face, quantity is face amount)
    SecSpec("UST2Y", "US Treasury 4.25% 2y", FI, "USD", "Government", "US", "US Treasury", 99.5, 0.0004,
            duration=1.9, multiplier=0.01, coupon_rate=0.0425, maturity_years=2.2, freq=2),
    SecSpec("UST10Y", "US Treasury 4.00% 10y", FI, "USD", "Government", "US", "US Treasury", 97.0, 0.0006,
            duration=8.0, multiplier=0.01, coupon_rate=0.04, maturity_years=9.6, freq=2),
    SecSpec("CORP-IG", "Ironworks Industrial 5.10% 2031", FI, "USD", "Corporate IG", "US", "Ironworks Industrial", 101.0, 0.0008,
            duration=5.5, spread_duration=5.5, multiplier=0.01, coupon_rate=0.051, maturity_years=5.7, freq=2),
    SecSpec("CORP-HY", "Ridgeline Energy 7.75% 2029", FI, "USD", "Corporate HY", "US", "Ridgeline Energy", 98.0, 0.0015,
            # HY spreads move ~3x IG spreads, so the loading on the IG-spread factor is ~3x duration.
            mkt_beta=0.15, duration=3.5, spread_duration=10.0, multiplier=0.01, coupon_rate=0.0775, maturity_years=3.9, freq=2),
    # Fund
    SecSpec("GLDF", "Bullion Trust ETF", AssetClass.FUND, "USD", "Commodities", "US", "Bullion Trust", 185, 0.009, 0.10, 0.0, drift=0.0002),
]


def _business_end() -> date:
    d = date.today() - timedelta(days=1)
    while d.weekday() >= 5:
        d -= timedelta(days=1)
    return d


def generate_market(
    start: date, end: date, seed: int
) -> tuple[pd.DataFrame, pd.DataFrame, pd.Series]:
    """Returns (factor returns, prices by ticker in local currency, EURUSD level)."""
    rng = np.random.default_rng(seed)
    dates = pd.bdate_range(start, end)
    T = len(dates)
    F = pd.DataFrame({f: rng.normal(FACTOR_MEAN[f], FACTOR_VOL[f], T) for f in FACTORS}, index=dates)
    eurusd = pd.Series(1.08 * np.exp(np.cumsum(F["EURUSD"].to_numpy())), index=dates)

    prices: dict[str, np.ndarray] = {}
    for s in UNIVERSE:
        # Returns are log returns. Add half the variance so the noise is mean-zero in price terms
        # (otherwise high-volatility names drift down for no economic reason).
        variance = (
            (s.mkt_beta * FACTOR_VOL["MKT"]) ** 2
            + (s.size_beta * FACTOR_VOL["SIZE"]) ** 2
            + (s.duration * FACTOR_VOL["RATES"]) ** 2
            + (s.spread_duration * FACTOR_VOL["CREDIT"]) ** 2
            + s.idio_vol**2
        )
        r = (
            s.drift
            + 0.5 * variance
            + s.mkt_beta * F["MKT"].to_numpy()
            + s.size_beta * F["SIZE"].to_numpy()
            - s.duration * F["RATES"].to_numpy()
            - s.spread_duration * F["CREDIT"].to_numpy()
            + rng.normal(0.0, s.idio_vol, T)
        )
        prices[s.ticker] = s.start_price * np.exp(np.cumsum(r))
    return F, pd.DataFrame(prices, index=dates), eurusd


def _round_lot(x: float, lot: float) -> float:
    return float(np.floor(x / lot) * lot)


class _Book:
    """Helper that records trades at the generated price on the trade date."""

    def __init__(self, session: Session, prices: pd.DataFrame, eurusd: pd.Series, secs: dict[str, Security]):
        self.session, self.prices, self.eurusd, self.secs = session, prices, eurusd, secs

    def fx(self, ccy: str, on: date) -> float:
        return float(self.eurusd.loc[pd.Timestamp(on)]) if ccy == "EUR" else 1.0

    def price(self, ticker: str, on: date) -> float:
        return float(self.prices.at[pd.Timestamp(on), ticker])

    def trade(self, pf: Portfolio, ticker: str, side: Side, quantity: float, on: date) -> Trade:
        sec = self.secs[ticker]
        t = Trade(
            portfolio_id=pf.id, security_id=sec.id, side=side.value, quantity=quantity,
            price=self.price(ticker, on), currency=sec.currency, fees=0.0, trade_date=on,
        )
        self.session.add(t)
        return t

    def buy_notional(self, pf: Portfolio, ticker: str, notional_usd: float, on: date) -> Trade:
        sec = self.secs[ticker]
        px = self.price(ticker, on) * sec.multiplier * self.fx(sec.currency, on)
        lot = 1000.0 if sec.multiplier != 1.0 else 10.0
        return self.trade(pf, ticker, Side.BUY, _round_lot(notional_usd / px, lot), on)


BALANCED_TARGETS = {
    "ACME": 0.06, "BYTE": 0.05, "NOVA": 0.05,
    "HLTH": 0.035, "PHRM": 0.035, "BANK": 0.035, "INSR": 0.035, "SHOP": 0.035,
    "FOOD": 0.035, "OILX": 0.035, "UTIL": 0.035, "INDS": 0.035,
    "LUXE": 0.03, "AUTO": 0.03, "PHAR": 0.03,
    "UST2Y": 0.08, "UST10Y": 0.14, "CORP-IG": 0.12, "CORP-HY": 0.05,
}
GROWTH_TARGETS = {
    "ACME": 0.14, "BYTE": 0.12, "NOVA": 0.12, "HLTH": 0.10, "PHRM": 0.08, "SHOP": 0.10,
    "INDS": 0.08, "BANK": 0.06, "FOOD": 0.05, "UTIL": 0.04, "INSR": 0.04, "OILX": 0.03,
}


def seed_demo(
    session: Session, start: date | None = None, end: date | None = None, seed: int = 8
) -> dict:
    end = end or _business_end()
    start = start or (end - timedelta(days=3 * 365 + 10))
    F, prices, eurusd = generate_market(start, end, seed)
    dates = list(prices.index.date)

    # --- reference data
    secs: dict[str, Security] = {}
    for s in UNIVERSE:
        sec = Security(
            ticker=s.ticker, name=s.name, asset_class=s.asset_class.value, currency=s.currency,
            sector=s.sector, country=s.country, issuer=s.issuer, multiplier=s.multiplier,
            coupon_rate=s.coupon_rate, coupon_frequency=s.freq, face_value=100.0 if s.coupon_rate else None,
            # Maturities are set from the end of history so every bond is still alive on the as-of date.
            maturity_date=(end + timedelta(days=int(s.maturity_years * 365.25))) if s.maturity_years else None,
        )
        session.add(sec)
        secs[s.ticker] = sec
    session.flush()

    session.execute(
        insert(Price),
        [
            {"security_id": secs[t].id, "date": d, "close": float(prices.at[pd.Timestamp(d), t])}
            for t in prices.columns
            for d in dates
        ],
    )
    session.execute(
        insert(FxRate),
        [{"base_currency": "EUR", "quote_currency": "USD", "date": d, "rate": float(eurusd.loc[pd.Timestamp(d)])} for d in dates],
    )
    session.execute(
        insert(FactorReturn),
        [{"factor": f, "date": d, "value": float(F.at[pd.Timestamp(d), f])} for f in FACTORS for d in dates],
    )

    # --- benchmarks
    equities15 = [s.ticker for s in UNIVERSE if s.asset_class == EQ and s.ticker != "SMKE"]
    us12 = [t for t in equities15 if secs[t].currency == "USD"]
    bench_6040 = Benchmark(name="Global 60/40")
    bench_us = Benchmark(name="US Equity Index")
    session.add_all([bench_6040, bench_us])
    session.flush()
    for t in equities15:
        session.add(BenchmarkWeight(benchmark_id=bench_6040.id, security_id=secs[t].id, weight=0.04))
    for t, w in {"UST2Y": 0.10, "UST10Y": 0.15, "CORP-IG": 0.10, "CORP-HY": 0.05}.items():
        session.add(BenchmarkWeight(benchmark_id=bench_6040.id, security_id=secs[t].id, weight=w))
    for t in us12:
        session.add(BenchmarkWeight(benchmark_id=bench_us.id, security_id=secs[t].id, weight=1 / 12))

    # --- portfolios
    balanced = Portfolio(name="Global Balanced Fund", base_currency="USD", benchmark_id=bench_6040.id)
    growth = Portfolio(name="US Equity Growth", base_currency="USD", benchmark_id=bench_us.id)
    session.add_all([balanced, growth])
    session.flush()

    book = _Book(session, prices, eurusd, secs)
    d0 = dates[5]
    session.add(CashFlow(portfolio_id=balanced.id, date=dates[0], amount=100_000_000, memo="Initial subscription"))
    for t, w in BALANCED_TARGETS.items():
        book.buy_notional(balanced, t, w * 100_000_000, d0)
    session.add(CashFlow(portfolio_id=growth.id, date=dates[0], amount=50_000_000, memo="Initial subscription"))
    for t, w in GROWTH_TARGETS.items():
        book.buy_notional(growth, t, w * 50_000_000, d0)

    # Later activity so the ledger has some history.
    n = len(dates)
    book.buy_notional(balanced, "ACME", 1_500_000, dates[min(130, n - 1)])
    book.trade(balanced, "UST2Y", Side.SELL, 2_000_000, dates[min(135, n - 1)])
    session.add(CashFlow(portfolio_id=balanced.id, date=dates[min(260, n - 1)], amount=10_000_000, memo="Subscription"))
    book.buy_notional(balanced, "GLDF", 3_000_000, dates[min(262, n - 1)])
    session.add(CashFlow(portfolio_id=balanced.id, date=dates[min(400, n - 1)], amount=-5_000_000, memo="Redemption"))
    book.buy_notional(balanced, "NOVA", 2_000_000, dates[min(520, n - 1)])
    book.buy_notional(growth, "HLTH", 1_000_000, dates[min(300, n - 1)])

    # --- compliance rules
    rules = [
        ComplianceRule(portfolio_id=None, name="Restricted list", rule_type="restricted_list",
                       params={"tickers": ["SMKE"]}, severity=Severity.HARD.value),
        ComplianceRule(portfolio_id=None, name="No shorts", rule_type="no_short_positions", params={}, severity=Severity.HARD.value),
        ComplianceRule(portfolio_id=None, name="No overdraft", rule_type="no_negative_cash", params={}, severity=Severity.HARD.value),
        ComplianceRule(portfolio_id=balanced.id, name="Max 10% per issue (ex govts)", rule_type="max_position_weight",
                       params={"limit": 0.10, "exclude_asset_classes": ["Fixed Income"]}, severity=Severity.HARD.value),
        ComplianceRule(portfolio_id=balanced.id, name="Max 30% per sector", rule_type="max_group_weight",
                       params={"dimension": "sector", "limit": 0.30}, severity=Severity.SOFT.value),
        ComplianceRule(portfolio_id=balanced.id, name="Equity <= 70%", rule_type="max_group_weight",
                       params={"dimension": "asset_class", "bucket": "Equity", "limit": 0.70}, severity=Severity.HARD.value),
        ComplianceRule(portfolio_id=balanced.id, name="Fixed income >= 25%", rule_type="min_group_weight",
                       params={"dimension": "asset_class", "bucket": "Fixed Income", "limit": 0.25}, severity=Severity.SOFT.value),
        ComplianceRule(portfolio_id=balanced.id, name="Cash >= 1%", rule_type="min_cash_weight",
                       params={"limit": 0.01}, severity=Severity.SOFT.value),
        ComplianceRule(portfolio_id=balanced.id, name="Max 20% per issuer (ex sovereigns)", rule_type="max_issuer_weight",
                       params={"limit": 0.20, "exclude_sectors": ["Government"]}, severity=Severity.HARD.value),
        ComplianceRule(portfolio_id=growth.id, name="Max 15% per position", rule_type="max_position_weight",
                       params={"limit": 0.15}, severity=Severity.HARD.value),
        ComplianceRule(portfolio_id=growth.id, name="Max 45% per sector", rule_type="max_group_weight",
                       params={"dimension": "sector", "limit": 0.45}, severity=Severity.SOFT.value),
    ]
    session.add_all(rules)
    session.commit()

    # --- live orders through the OMS so the blotter has something to show
    o1 = oms.create_order(session, portfolio_id=balanced.id, security_id=secs["HLTH"].id, side=Side.BUY,
                          quantity=5_000, actor="demo")
    o2 = oms.create_order(session, portfolio_id=balanced.id, security_id=secs["SMKE"].id, side=Side.BUY,
                          quantity=10_000, actor="demo")
    o3 = oms.create_order(session, portfolio_id=growth.id, security_id=secs["BYTE"].id, side=Side.BUY,
                          quantity=2_000, actor="demo")
    if o3.status == "APPROVED":
        oms.fill_order(session, o3.id, 2_000, book.price("BYTE", end), actor="demo",
                       filled_at=datetime(end.year, end.month, end.day, 15, 30, tzinfo=UTC))

    return {
        "start": start.isoformat(),
        "end": end.isoformat(),
        "securities": len(secs),
        "price_rows": int(prices.size),
        "portfolios": {"Global Balanced Fund": balanced.id, "US Equity Growth": growth.id},
        "benchmarks": {"Global 60/40": bench_6040.id, "US Equity Index": bench_us.id},
        "rules": len(rules),
        "orders": {"approved_unfilled": o1.id, "rejected": o2.id, "filled": o3.id},
    }
