"""Runs rules against a portfolio, before a trade (what-if) or after (holdings as they stand)."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.compliance.rules import REGISTRY, Breach, RuleSpec
from lantern.models import CheckStage, ComplianceCheck, ComplianceRule, Severity
from lantern.portfolio.positions import ValuedPositions, value_portfolio
from lantern.portfolio.whatif import ProposedTrade, apply_trades

EPS = 1e-9


def load_rules(session: Session, portfolio_id: int) -> list[RuleSpec]:
    """Active rules for the portfolio plus firm-wide rules (portfolio_id is null)."""
    rows = session.execute(
        select(ComplianceRule).where(
            ComplianceRule.active.is_(True),
            (ComplianceRule.portfolio_id == portfolio_id) | (ComplianceRule.portfolio_id.is_(None)),
        )
    ).scalars()
    return [RuleSpec.from_orm(r) for r in rows]


def evaluate(rules: list[RuleSpec], valued: ValuedPositions) -> list[Breach]:
    breaches: list[Breach] = []
    for spec in rules:
        fn = REGISTRY.get(spec.rule_type)
        if fn is None:
            # A rule nobody can evaluate must not silently pass.
            breaches.append(
                Breach(spec.id, spec.name, spec.rule_type, Severity.HARD, "rule", None, None, 1.0,
                       f"Unknown rule type {spec.rule_type!r}; rule cannot be evaluated")
            )
            continue
        breaches.extend(fn(spec, valued))
    return breaches


@dataclass
class CheckResult:
    stage: CheckStage
    portfolio_id: int
    as_of: date
    passed: bool  # no hard breach introduced/worsened (pre-trade) or present (post-trade)
    blocked: bool  # pre-trade only: the order must be rejected
    breaches: list[Breach]  # state after the trade (or current state, post-trade)
    new_breaches: list[Breach] = field(default_factory=list)  # pre-trade: new or worsened
    warnings: list[Breach] = field(default_factory=list)  # soft breaches among new_breaches
    pre_existing: list[Breach] = field(default_factory=list)  # already breached before the trade

    def to_dict(self) -> dict:
        return {
            "stage": self.stage.value,
            "portfolio_id": self.portfolio_id,
            "as_of": self.as_of.isoformat(),
            "passed": self.passed,
            "blocked": self.blocked,
            "breaches": [b.to_dict() for b in self.breaches],
            "new_breaches": [b.to_dict() for b in self.new_breaches],
            "warnings": [b.to_dict() for b in self.warnings],
            "pre_existing": [b.to_dict() for b in self.pre_existing],
        }


def _record(session: Session, result: CheckResult, order_id: int | None) -> None:
    session.add(
        ComplianceCheck(
            portfolio_id=result.portfolio_id,
            order_id=order_id,
            stage=result.stage.value,
            as_of=result.as_of,
            passed=result.passed,
            blocked=result.blocked,
            breaches=[b.to_dict() for b in (result.new_breaches or result.breaches)],
        )
    )
    session.flush()


def post_trade_check(
    session: Session, portfolio_id: int, as_of: date | None = None, record: bool = True
) -> CheckResult:
    valued = value_portfolio(session, portfolio_id, as_of)
    rules = load_rules(session, portfolio_id)
    breaches = evaluate(rules, valued)
    hard = [b for b in breaches if b.severity == Severity.HARD]
    result = CheckResult(
        stage=CheckStage.POST_TRADE,
        portfolio_id=portfolio_id,
        as_of=valued.as_of,
        passed=not hard,
        blocked=False,
        breaches=breaches,
        warnings=[b for b in breaches if b.severity == Severity.SOFT],
    )
    if record:
        _record(session, result, None)
    return result


def pre_trade_check(
    session: Session,
    portfolio_id: int,
    trades: list[ProposedTrade],
    as_of: date | None = None,
    order_id: int | None = None,
    record: bool = True,
) -> CheckResult:
    """Compare breaches before and after the proposed trades.

    A hard breach that is introduced, or an existing one that gets worse, blocks the order.
    Pre-existing breaches the trade does not worsen are reported but do not block, so a
    portfolio already over a limit can still trade its way back.
    """
    before = value_portfolio(session, portfolio_id, as_of)
    after = apply_trades(session, before, trades)
    rules = load_rules(session, portfolio_id)

    before_map = {b.key: b for b in evaluate(rules, before)}
    after_breaches = evaluate(rules, after)

    new_or_worse: list[Breach] = []
    pre_existing: list[Breach] = []
    for b in after_breaches:
        prior = before_map.get(b.key)
        if prior is None or b.excess > prior.excess + EPS:
            new_or_worse.append(b)
        else:
            pre_existing.append(b)

    blocked = any(b.severity == Severity.HARD for b in new_or_worse)
    result = CheckResult(
        stage=CheckStage.PRE_TRADE,
        portfolio_id=portfolio_id,
        as_of=before.as_of,
        passed=not blocked,
        blocked=blocked,
        breaches=after_breaches,
        new_breaches=new_or_worse,
        warnings=[b for b in new_or_worse if b.severity == Severity.SOFT],
        pre_existing=pre_existing,
    )
    if record:
        _record(session, result, order_id)
    return result
