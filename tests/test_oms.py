from datetime import UTC, datetime

import pytest
from sqlalchemy import select

from lantern.models import AuditEvent, ComplianceRule, OrderStatus, OrderType, Severity, Side, Trade
from lantern.portfolio.positions import value_portfolio
from lantern.trading import oms
from tests.conftest import D1

FILLED_AT = datetime(D1.year, D1.month, D1.day, 15, 0, tzinfo=UTC)


def test_order_lifecycle_updates_ledger(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    o = oms.create_order(s, portfolio_id=pf.id, security_id=aaa.id, side=Side.BUY, quantity=100, actor="pm")
    assert o.status == OrderStatus.APPROVED.value
    assert o.compliance_summary["passed"] is True

    oms.fill_order(s, o.id, 60, 111.0, actor="trader", filled_at=FILLED_AT)
    assert o.status == OrderStatus.PARTIALLY_FILLED.value
    assert o.remaining_quantity == pytest.approx(40)

    oms.fill_order(s, o.id, 40, 112.0, actor="trader", filled_at=FILLED_AT)
    assert o.status == OrderStatus.FILLED.value
    assert o.avg_fill_price == pytest.approx((60 * 111 + 40 * 112) / 100)

    v = value_portfolio(s, pf.id, D1)
    assert v.positions.at[aaa.id, "quantity"] == 1100
    assert v.cash == pytest.approx(594_000 - 60 * 111 - 40 * 112)
    trades = s.execute(select(Trade).where(Trade.order_id == o.id)).scalars().all()
    assert len(trades) == 2

    actions = [e.action for e in s.execute(select(AuditEvent).where(AuditEvent.entity_id == o.id)).scalars()]
    assert actions[0] == "created"
    assert any(a.endswith("->FILLED") for a in actions)


def test_overfill_rejected(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    o = oms.create_order(s, portfolio_id=pf.id, security_id=aaa.id, side=Side.BUY, quantity=100)
    with pytest.raises(oms.OrderError, match="exceeds remaining"):
        oms.fill_order(s, o.id, 101, 110.0)


def test_compliance_rejects_order_and_records_reason(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    s.add(ComplianceRule(portfolio_id=pf.id, name="Max 12%", rule_type="max_position_weight",
                         params={"limit": 0.12}, severity=Severity.HARD.value))
    s.commit()
    o = oms.create_order(s, portfolio_id=pf.id, security_id=aaa.id, side=Side.BUY, quantity=500)
    assert o.status == OrderStatus.REJECTED.value
    assert "AAA" in o.reject_reason and "12.00%" in o.reject_reason
    with pytest.raises(oms.OrderError, match="only approved"):
        oms.fill_order(s, o.id, 1, 110.0)


def test_limit_order_fill_price_is_enforced(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    o = oms.create_order(s, portfolio_id=pf.id, security_id=aaa.id, side=Side.BUY, quantity=100,
                         order_type=OrderType.LIMIT, limit_price=105.0)
    assert o.status == OrderStatus.APPROVED.value
    with pytest.raises(oms.OrderError, match="above limit"):
        oms.fill_order(s, o.id, 100, 106.0)
    oms.fill_order(s, o.id, 100, 104.5, filled_at=FILLED_AT)
    assert o.status == OrderStatus.FILLED.value


def test_cancel(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    o = oms.create_order(s, portfolio_id=pf.id, security_id=aaa.id, side=Side.SELL, quantity=10)
    oms.cancel_order(s, o.id, reason="changed mind")
    assert o.status == OrderStatus.CANCELLED.value
    with pytest.raises(oms.OrderError):
        oms.cancel_order(s, o.id)


def test_validation(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    with pytest.raises(oms.OrderError, match="positive"):
        oms.create_order(s, portfolio_id=pf.id, security_id=aaa.id, side=Side.BUY, quantity=0)
    with pytest.raises(oms.OrderError, match="limit price"):
        oms.create_order(s, portfolio_id=pf.id, security_id=aaa.id, side=Side.BUY, quantity=1,
                         order_type=OrderType.LIMIT)
    with pytest.raises(oms.OrderError, match="not found"):
        oms.create_order(s, portfolio_id=pf.id, security_id=9999, side=Side.BUY, quantity=1)
