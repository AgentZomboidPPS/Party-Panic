"""The execution gate: limits, kill switch, paper fills, and the rules for a live broker."""

from datetime import datetime

import pytest
from sqlalchemy import select

from spectre.execution.brokers import BrokerFill, BrokerReject, PaperBroker
from spectre.execution.guard import TradingLimits, check, execute, halt_state, set_halt
from spectre.models import AuditEvent, OrderStatus, OrderType, Side
from spectre.portfolio.positions import value_portfolio
from spectre.trading import oms
from tests.conftest import D1

# The `mini` book (see conftest): 1,022,000 total, 594,000 cash, AAA last price 110.
ROOMY = TradingLimits(max_order_notional=50_000, max_daily_notional=100_000, max_orders_per_day=5, max_position_weight=0.30)


class FakeLiveBroker:
    name = "fake-live"
    live = True

    def __init__(self):
        self.sent = []

    def submit(self, session, order):
        self.sent.append(order.id)
        return BrokerFill(order.remaining_quantity, 110.0, datetime(D1.year, D1.month, D1.day, 15, 0), broker_order_id="B-1")


def _order(mini, qty=100, side=Side.BUY, **kw):
    return oms.create_order(mini["session"], portfolio_id=mini["pf"].id, security_id=mini["aaa"].id, side=side,
                            quantity=qty, **kw)


def test_paper_execution_fills_and_updates_the_ledger(mini):
    s = mini["session"]
    o = _order(mini, 100)
    r = execute(s, o.id, PaperBroker(), ROOMY)
    assert r.outcome == "executed" and r.price == pytest.approx(110.0) and r.quantity == 100
    assert o.status == OrderStatus.FILLED.value
    v = value_portfolio(s, mini["pf"].id, D1)
    assert v.positions.at[mini["aaa"].id, "quantity"] == 1100 and v.cash == pytest.approx(594_000 - 11_000)
    actions = [e.action for e in s.execute(select(AuditEvent).where(AuditEvent.entity_id == o.id)).scalars()]
    assert "executed" in actions


def test_slippage_works_against_you(mini):
    buy = execute(mini["session"], _order(mini, 10).id, PaperBroker(slippage_bps=50), ROOMY)
    sell = execute(mini["session"], _order(mini, 10, Side.SELL).id, PaperBroker(slippage_bps=50), ROOMY)
    assert buy.price == pytest.approx(110 * 1.005) and sell.price == pytest.approx(110 * 0.995)


def test_kill_switch_blocks_everything_until_resumed(mini):
    s = mini["session"]
    o = _order(mini, 10)
    set_halt(s, True, actor="owner", reason="something looks wrong")
    r = execute(s, o.id, PaperBroker(), ROOMY)
    assert r.outcome == "blocked" and "halted: something looks wrong" in r.reasons[0]
    assert o.status == OrderStatus.APPROVED.value, "a blocked order is untouched"
    set_halt(s, False, actor="owner")
    assert not halt_state(s).halted
    assert execute(s, o.id, PaperBroker(), ROOMY).outcome == "executed"


def test_order_size_daily_total_and_count_limits(mini):
    s = mini["session"]
    tight = TradingLimits(max_order_notional=5_000, max_daily_notional=8_000, max_orders_per_day=2, max_position_weight=0.5)
    big = _order(mini, 100)  # 11,000
    r = execute(s, big.id, PaperBroker(), tight)
    assert r.outcome == "blocked" and "per-order limit is 5,000" in " ".join(r.reasons)

    assert execute(s, _order(mini, 40).id, PaperBroker(), tight).outcome == "executed"  # 4,400
    r = execute(s, _order(mini, 40).id, PaperBroker(), tight)  # would make 8,800 > 8,000
    assert r.outcome == "blocked" and "daily limit is 8,000" in " ".join(r.reasons)
    assert execute(s, _order(mini, 20).id, PaperBroker(), tight).outcome == "executed"  # 2,200 -> 6,600
    r = execute(s, _order(mini, 1).id, PaperBroker(), tight)
    assert r.outcome == "blocked" and "2 orders already executed today" in " ".join(r.reasons)


def test_position_size_and_symbol_list(mini):
    s = mini["session"]
    limits = TradingLimits(max_order_notional=1e9, max_daily_notional=1e9, max_position_weight=0.12)
    # AAA is 110,000 of 1,022,000 (10.8%); +200 shares = 132,000 (12.9%)
    r = execute(s, _order(mini, 200).id, PaperBroker(), limits)
    assert r.outcome == "blocked" and "would be 12.9% of the portfolio" in " ".join(r.reasons)
    assert execute(s, _order(mini, 200, Side.SELL).id, PaperBroker(), limits).outcome == "executed", "sells are not capped"
    only_eee = TradingLimits(max_order_notional=1e9, max_daily_notional=1e9, allowed_symbols=frozenset({"EEE"}))
    r = execute(s, _order(mini, 1).id, PaperBroker(), only_eee)
    assert r.outcome == "blocked" and "not on the allowed-symbols list" in " ".join(r.reasons)


def test_only_compliance_approved_orders_can_execute(mini):
    s = mini["session"]
    o = _order(mini, 10)
    oms.cancel_order(s, o.id)
    r = execute(s, o.id, PaperBroker(), ROOMY)
    assert r.outcome == "blocked" and "only compliance-approved" in r.reasons[0]
    with pytest.raises(oms.OrderError):
        execute(s, 99999, PaperBroker(), ROOMY)


def test_paper_broker_respects_limit_prices(mini):
    s = mini["session"]
    o = _order(mini, 10, order_type=OrderType.LIMIT, limit_price=105.0)  # market is 110
    r = execute(s, o.id, PaperBroker(), ROOMY)
    assert r.outcome == "blocked" and "above the buy limit" in r.reasons[0]
    with pytest.raises(BrokerReject):
        PaperBroker().submit(s, o)


def test_live_broker_needs_live_mode_and_a_named_approver(mini):
    s = mini["session"]
    broker = FakeLiveBroker()
    o = _order(mini, 10)

    paper_mode = TradingLimits(mode="paper", max_order_notional=50_000, max_daily_notional=100_000)
    r = execute(s, o.id, broker, paper_mode, approved_by="tim")
    assert r.outcome == "blocked" and "trading mode is 'paper'" in " ".join(r.reasons)

    live_mode = TradingLimits(mode="live", max_order_notional=50_000, max_daily_notional=100_000)
    r = execute(s, o.id, broker, live_mode)
    assert r.outcome == "awaiting_approval" and broker.sent == [], "nothing reaches a live broker without sign-off"

    r = execute(s, o.id, broker, live_mode, approved_by="tim")
    assert r.outcome == "executed" and broker.sent == [o.id]
    ev = s.execute(select(AuditEvent).where(AuditEvent.entity_id == o.id, AuditEvent.action == "executed")).scalar_one()
    assert ev.detail["approved_by"] == "tim" and ev.detail["live"] is True and ev.detail["broker_order_id"] == "B-1"


def test_defaults_are_small_and_paper(mini):
    d = TradingLimits.from_settings()
    assert d.mode == "paper" and d.require_approval and d.max_order_notional <= 1_000
    o = _order(mini, 100)  # 11,000 against a 1,000 default
    assert check(mini["session"], o, d, PaperBroker())
