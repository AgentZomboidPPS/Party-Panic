"""Assemble the full risk picture for one portfolio."""

from __future__ import annotations

from datetime import date, timedelta

import pandas as pd
from sqlalchemy.orm import Session

from lantern.config import settings
from lantern.marketdata.prices import price_matrix, returns_from_prices
from lantern.models import Security
from lantern.portfolio.positions import ValuedPositions, security_map, value_portfolio
from lantern.risk import factors as fm
from lantern.risk.fixed_income import bond_analytics
from lantern.risk.stress import PREDEFINED, Scenario, apply_scenario
from lantern.risk.var import (
    component_var,
    historical_var,
    monte_carlo_var,
    parametric_var,
    portfolio_return_series,
)


def asset_returns(
    session: Session, valued: ValuedPositions, lookback_days: int | None = None
) -> pd.DataFrame:
    lookback = lookback_days or settings.lookback_days
    px = price_matrix(
        session, valued.positions.index, valued.as_of, lookback, base_currency=valued.base_currency
    )
    return returns_from_prices(px)


def durations(session: Session, valued: ValuedPositions) -> tuple[pd.Series, list[dict]]:
    """Modified duration per fixed-income position, plus the full analytics rows."""
    secs = security_map(session, valued.positions.index)
    durs: dict[int, float] = {}
    rows: list[dict] = []
    for sid, sec in secs.items():
        if not sec.is_fixed_income():
            continue
        a = bond_analytics(sec, float(valued.positions.at[sid, "price"]), valued.as_of)
        if a is None:
            continue
        durs[sid] = a.modified_duration
        d = a.to_dict()
        d["security_id"] = sid
        d["market_value"] = float(valued.positions.at[sid, "market_value"])
        d["weight"] = float(valued.positions.at[sid, "weight"])
        rows.append(d)
    return pd.Series(durs, dtype=float), rows


def var_suite(
    session: Session,
    valued: ValuedPositions,
    confidence: float | None = None,
    horizon_days: int | None = None,
    lookback_days: int | None = None,
) -> dict:
    confidence = confidence or settings.var_confidence
    horizon = horizon_days or settings.var_horizon_days
    rets = asset_returns(session, valued, lookback_days)
    w = valued.weights()
    if rets.empty or len(valued.positions) == 0:
        return {"error": "insufficient price history", "methods": {}}
    cov = rets.cov()
    port = portfolio_return_series(rets, w)
    value = valued.total_value
    hist = historical_var(port, value, confidence, horizon)
    para = parametric_var(w, cov, value, confidence, horizon)
    mc = monte_carlo_var(
        w, cov, value, confidence, horizon, settings.mc_simulations, settings.mc_seed
    )
    comp = component_var(w, cov, value, confidence, horizon)
    comp.insert(0, "ticker", valued.positions["ticker"].reindex(comp.index))
    return {
        "as_of": valued.as_of.isoformat(),
        "confidence": confidence,
        "horizon_days": horizon,
        "observations": int(len(rets)),
        "portfolio_value": value,
        "annualised_vol": float(port.std() * (252**0.5)),
        "methods": {r.method: r.to_dict() for r in (hist, para, mc)},
        "component_var": comp.reset_index().to_dict(orient="records"),
    }


def stress_suite(
    session: Session, valued: ValuedPositions, scenarios: list[Scenario] | None = None
) -> list[dict]:
    durs, _ = durations(session, valued)
    results = [apply_scenario(valued, s, durs) for s in (scenarios or PREDEFINED)]
    return [r.to_dict(top=10) for r in results]


def factor_suite(session: Session, valued: ValuedPositions, lookback_days: int | None = None) -> dict:
    rets = asset_returns(session, valued, lookback_days)
    if rets.empty:
        return {"error": "insufficient price history"}
    start = rets.index.min().date() - timedelta(days=1)
    frets = fm.factor_returns(session, start, valued.as_of)
    if frets.empty:
        return {"error": "no factor returns loaded"}
    model = fm.estimate(rets, frets)
    w = valued.weights()
    decomp = fm.decompose(w, model)
    betas = model.betas.copy()
    betas.insert(0, "ticker", valued.positions["ticker"].reindex(betas.index))
    betas["r_squared"] = model.r_squared
    return {
        "as_of": valued.as_of.isoformat(),
        "factors": list(frets.columns),
        **decomp.to_dict(),
        "security_betas": betas.reset_index().to_dict(orient="records"),
    }


def risk_report(
    session: Session,
    portfolio_id: int,
    as_of: date | None = None,
    confidence: float | None = None,
    horizon_days: int | None = None,
) -> dict:
    valued = value_portfolio(session, portfolio_id, as_of)
    _, fi_rows = durations(session, valued)
    return {
        "portfolio": {
            "id": valued.portfolio_id,
            "name": valued.portfolio_name,
            "as_of": valued.as_of.isoformat(),
            "base_currency": valued.base_currency,
            "total_value": valued.total_value,
            "cash": valued.cash,
            "positions": int(len(valued.positions)),
        },
        "var": var_suite(session, valued, confidence, horizon_days),
        "stress": stress_suite(session, valued),
        "factors": factor_suite(session, valued),
        "fixed_income": fi_rows,
    }


def securities_by_ticker(session: Session, tickers: list[str]) -> dict[str, Security]:
    from sqlalchemy import select

    rows = session.execute(select(Security).where(Security.ticker.in_(tickers))).scalars()
    return {s.ticker: s for s in rows}
