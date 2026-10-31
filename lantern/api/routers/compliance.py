from __future__ import annotations

from datetime import date

from fastapi import APIRouter
from sqlalchemy import select

from lantern import audit
from lantern.api.deps import DB
from lantern.compliance import engine
from lantern.compliance.rules import rule_types
from lantern.models import ComplianceCheck, ComplianceRule
from lantern.portfolio.whatif import ProposedTrade
from lantern.schemas import RuleIn, RuleOut, WhatIfIn

router = APIRouter(tags=["compliance"])


@router.get("/compliance/rule-types")
def list_rule_types() -> dict[str, str]:
    return rule_types()


@router.get("/compliance/rules", response_model=list[RuleOut])
def list_rules(db: DB, portfolio_id: int | None = None, include_firm_wide: bool = True):
    q = select(ComplianceRule).order_by(ComplianceRule.id)
    if portfolio_id is not None:
        cond = ComplianceRule.portfolio_id == portfolio_id
        if include_firm_wide:
            cond = cond | ComplianceRule.portfolio_id.is_(None)
        q = q.where(cond)
    return list(db.execute(q).scalars())


@router.post("/compliance/rules", response_model=RuleOut, status_code=201)
def create_rule(body: RuleIn, db: DB):
    if body.rule_type not in rule_types():
        raise ValueError(f"Unknown rule type {body.rule_type!r}")
    data = body.model_dump()
    data["severity"] = body.severity.value
    r = ComplianceRule(**data)
    db.add(r)
    db.flush()
    audit.record(db, actor="api", entity_type="compliance_rule", entity_id=r.id, action="created",
                 detail=data)
    db.commit()
    return r


@router.patch("/compliance/rules/{rule_id}", response_model=RuleOut)
def update_rule(rule_id: int, db: DB, active: bool | None = None, severity: str | None = None):
    r = db.get(ComplianceRule, rule_id)
    if r is None:
        raise LookupError(f"Rule {rule_id} not found")
    changes = {}
    if active is not None:
        r.active = active
        changes["active"] = active
    if severity is not None:
        r.severity = severity
        changes["severity"] = severity
    audit.record(db, actor="api", entity_type="compliance_rule", entity_id=r.id, action="updated",
                 detail=changes)
    db.commit()
    return r


@router.get("/portfolios/{portfolio_id}/compliance")
def post_trade(portfolio_id: int, db: DB, as_of: date | None = None, record: bool = False) -> dict:
    result = engine.post_trade_check(db, portfolio_id, as_of, record=record)
    if record:
        db.commit()
    return result.to_dict()


@router.post("/portfolios/{portfolio_id}/compliance/pre-trade")
def pre_trade(portfolio_id: int, body: WhatIfIn, db: DB) -> dict:
    """Dry run: what would compliance say about these trades? Nothing is booked or recorded."""
    trades = [ProposedTrade(t.security_id, t.side, t.quantity, t.price) for t in body.trades]
    return engine.pre_trade_check(db, portfolio_id, trades, body.as_of, record=False).to_dict()


@router.get("/portfolios/{portfolio_id}/compliance/history")
def history(portfolio_id: int, db: DB, limit: int = 50) -> list[dict]:
    rows = db.execute(
        select(ComplianceCheck)
        .where(ComplianceCheck.portfolio_id == portfolio_id)
        .order_by(ComplianceCheck.id.desc())
        .limit(limit)
    ).scalars()
    return [
        {
            "id": c.id, "order_id": c.order_id, "stage": c.stage, "as_of": c.as_of.isoformat(),
            "run_at": c.run_at.isoformat() if c.run_at else None, "passed": c.passed,
            "blocked": c.blocked, "breaches": c.breaches,
        }
        for c in rows
    ]
