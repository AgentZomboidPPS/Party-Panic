from __future__ import annotations

from datetime import date

from fastapi import APIRouter

from lantern.api.deps import DB
from lantern.portfolio.positions import value_portfolio
from lantern.risk import report
from lantern.risk.stress import PREDEFINED, Scenario
from lantern.schemas import ScenarioIn

router = APIRouter(prefix="/portfolios/{portfolio_id}/risk", tags=["risk"])


@router.get("/report")
def full_report(portfolio_id: int, db: DB, as_of: date | None = None,
                confidence: float | None = None, horizon_days: int | None = None) -> dict:
    return report.risk_report(db, portfolio_id, as_of, confidence, horizon_days)


@router.get("/var")
def var(portfolio_id: int, db: DB, as_of: date | None = None, confidence: float | None = None,
        horizon_days: int | None = None, lookback_days: int | None = None) -> dict:
    valued = value_portfolio(db, portfolio_id, as_of)
    return report.var_suite(db, valued, confidence, horizon_days, lookback_days)


@router.get("/stress")
def stress(portfolio_id: int, db: DB, as_of: date | None = None) -> list[dict]:
    valued = value_portfolio(db, portfolio_id, as_of)
    return report.stress_suite(db, valued)


@router.post("/stress")
def custom_stress(portfolio_id: int, scenarios: list[ScenarioIn], db: DB, as_of: date | None = None) -> list[dict]:
    valued = value_portfolio(db, portfolio_id, as_of)
    return report.stress_suite(
        db, valued, [Scenario(s.name, s.description, s.shocks, s.rates_bp) for s in scenarios]
    )


@router.get("/factors")
def factors(portfolio_id: int, db: DB, as_of: date | None = None, lookback_days: int | None = None) -> dict:
    valued = value_portfolio(db, portfolio_id, as_of)
    return report.factor_suite(db, valued, lookback_days)


@router.get("/fixed-income")
def fixed_income(portfolio_id: int, db: DB, as_of: date | None = None) -> list[dict]:
    valued = value_portfolio(db, portfolio_id, as_of)
    _, rows = report.durations(db, valued)
    return rows


scenarios_router = APIRouter(tags=["risk"])


@scenarios_router.get("/scenarios")
def list_scenarios() -> list[dict]:
    return [s.to_dict() for s in PREDEFINED]
