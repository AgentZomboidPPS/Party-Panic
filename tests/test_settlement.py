"""Settlement: when trades settle, what is settled cash and what is still in flight, and the
good-faith rule a cash account lives by."""

from datetime import date

import pytest
from sqlalchemy import select

from spectre.compliance.engine import post_trade_check, pre_trade_check
from spectre.db import init_db, make_engine, make_session_factory
from spectre.models import CashFlow, ComplianceRule, Portfolio, Price, Security, Side, Trade
from spectre.portfolio import settlement as st
from spectre.portfolio.positions import value_portfolio
from spectre.portfolio.whatif import ProposedTrade

MON, TUE, WED, THU, FRI = (date(2026, 11, 16 + i) for i in range(5))
NEXT_MON = date(2026, 11, 23)


# --------------------------------------------------------------------------- calendar


def test_exchange_holidays_are_worked_out_for_any_year():
    h26 = st.market_holidays(2026)
    assert h26 == {date(2026, 1, 1), date(2026, 1, 19), date(2026, 2, 16), date(2026, 4, 3), date(2026, 5, 25),
                   date(2026, 6, 19), date(2026, 7, 3), date(2026, 9, 7), date(2026, 11, 26), date(2026, 12, 25)}
    assert date(2026, 7, 3) in h26, "the Fourth falls on a Saturday, so the Friday is taken"
    assert date(2027, 6, 18) in st.market_holidays(2027) and date(2027, 7, 5) in st.market_holidays(2027)
    assert date(2021, 12, 31) not in st.market_holidays(2022) and date(2022, 1, 1) not in st.market_holidays(2022), \
        "a Saturday New Year's Day is simply lost"
    assert date(2021, 6, 18) not in st.market_holidays(2021), "Juneteenth became a market holiday in 2022"
    assert date(2024, 3, 29) in st.market_holidays(2024) and date(2025, 4, 18) in st.market_holidays(2025), "Good Friday"
    assert st.is_business_day(MON) and not st.is_business_day(date(2026, 11, 21)) and not st.is_business_day(date(2026, 11, 26))


def test_each_kind_of_asset_settles_on_its_own_clock():
    assert st.settlement_date("Equity", WED) == THU and st.settlement_date("Fund", WED) == THU
    assert st.settlement_date("Option", WED) == THU
    assert st.settlement_date("Crypto", WED) == WED and st.settlement_date("Crypto", date(2026, 11, 21)) == date(2026, 11, 21)
    assert st.settlement_date("Equity", FRI) == NEXT_MON, "over the weekend"
    assert st.settlement_date("Equity", date(2026, 11, 25)) == date(2026, 11, 27), "over Thanksgiving"
    # The cycle has shortened twice.
    assert st.settlement_date("Equity", date(2024, 5, 24)) == date(2024, 5, 29), "T+2, over Memorial Day"
    assert st.settlement_date("Equity", date(2024, 5, 28)) == date(2024, 5, 29), "the first T+1 day"
    assert st.settlement_date("Equity", date(2017, 8, 1)) == date(2017, 8, 4), "T+3 before September 2017"
    assert st.settlement_date("Fixed Income", date(2020, 3, 2), "Government") == date(2020, 3, 3)
    assert st.settlement_date("Fixed Income", date(2020, 3, 2), "Corporate IG") == date(2020, 3, 4)


# --------------------------------------------------------------------------- the ledger replayed


@pytest.fixture
def acct():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        pf = Portfolio(name="Cash account", base_currency="USD")
        secs = {t: Security(ticker=t, name=t, asset_class=k, currency="USD", multiplier=m)
                for t, k, m in (("AAA", "Equity", 1.0), ("BBB", "Equity", 1.0), ("CCC", "Equity", 1.0), ("BTC", "Crypto", 1.0),
                                ("AAA261218C00100000", "Option", 100.0))}
        s.add_all([pf, *secs.values()])
        s.flush()
        s.add(CashFlow(portfolio_id=pf.id, date=MON, amount=10_000))
        for sec in secs.values():
            for day in (MON, TUE, WED, THU, FRI):
                s.add(Price(security_id=sec.id, date=day, close=5.0 if sec.multiplier == 100 else 100.0))
        s.commit()

        def trade(ticker, side, qty, price, day, fees=0.0):
            s.add(Trade(portfolio_id=pf.id, security_id=secs[ticker].id, side=side, quantity=qty, price=price, currency="USD",
                        fees=fees, trade_date=day))
            s.commit()

        yield s, pf.id, secs, trade


def test_cash_is_split_into_settled_and_in_flight(acct):
    s, pid, _, trade = acct
    trade("AAA", "BUY", 60, 100.0, MON)  # 6,000, paid Tuesday
    monday = st.simulate(s, pid, MON)
    assert monday.cash == 4_000 and monday.settled_cash == 10_000 and monday.payable == 6_000 and monday.receivable == 0
    assert monday.funds_available == 4_000, "the 6,000 is spoken for even though it has not left yet"
    assert monday.pending == [{"settles_on": "2026-11-17", "ticker": "AAA", "side": "BUY", "quantity": 60, "amount": -6_000,
                              "traded_on": "2026-11-16", "proposed": False}]

    trade("AAA", "SELL", 60, 110.0, TUE, fees=1.0)  # 6,599 arrives Wednesday
    tuesday = st.simulate(s, pid, TUE)
    assert tuesday.settled_cash == 4_000 and tuesday.receivable == 6_599 and tuesday.payable == 0
    assert tuesday.cash == pytest.approx(10_599) == value_portfolio(s, pid, TUE).cash, "the two views always add up to the ledger"
    assert tuesday.funds_available == 4_000, "sale money cannot be counted as settled until it is"
    wednesday = st.simulate(s, pid, WED)
    assert wednesday.settled_cash == wednesday.funds_available == pytest.approx(10_599) and wednesday.pending == []


def test_coins_settle_at_once(acct):
    s, pid, _, trade = acct
    trade("BTC", "BUY", 50, 100.0, MON)
    trade("BTC", "SELL", 50, 104.0, MON)
    state = st.simulate(s, pid, MON)
    assert state.settled_cash == state.funds_available == 10_200 and state.pending == [] and state.restricted == []


def test_buying_with_unsettled_proceeds_puts_the_new_holding_on_hold(acct):
    s, pid, _, trade = acct
    trade("AAA", "BUY", 100, 100.0, MON)  # all 10,000 of settled money
    trade("AAA", "SELL", 100, 100.0, WED)  # proceeds arrive Thursday
    trade("BBB", "BUY", 40, 100.0, WED)  # 4,000, paid for entirely out of money still in flight
    state = st.simulate(s, pid, WED)
    assert state.funds_available == -4_000 and state.receivable == 10_000
    assert state.restricted == [{"ticker": "BBB", "quantity": 40, "sell_freely_on": "2026-11-19"}]
    assert state.restricted_quantity("BBB") == 40 and state.free_on("BBB") == THU and state.violations == []
    assert st.simulate(s, pid, THU).restricted == [], "once the sale has settled the holding is free"


def test_a_holding_paid_for_with_settled_money_can_be_sold_the_same_day(acct):
    s, pid, _, trade = acct
    trade("AAA", "BUY", 50, 100.0, MON)
    trade("AAA", "SELL", 50, 101.0, MON)  # a round trip on settled money is fine
    trade("BBB", "BUY", 50, 100.0, MON)  # the other 5,000 of settled money: also fine
    state = st.simulate(s, pid, MON)
    assert state.violations == [] and state.restricted == [] and state.funds_available == 0


def test_selling_early_is_recorded_as_a_good_faith_violation(acct):
    s, pid, _, trade = acct
    trade("AAA", "BUY", 100, 100.0, MON)
    trade("AAA", "SELL", 100, 100.0, WED)
    trade("BBB", "BUY", 40, 100.0, WED)
    trade("BBB", "SELL", 40, 101.0, WED)  # sold before Wednesday's AAA sale has settled
    state = st.simulate(s, pid, FRI)
    (v,) = state.violations
    assert (v.date, v.ticker, v.quantity, v.bought_on, v.funds_settle_on) == (WED, "BBB", 40, WED, THU)
    assert "BBB" in v.describe() and len(state.recent_violations()) == 1
    assert st.simulate(s, pid, date(2028, 1, 3)).recent_violations() == [], "it drops off the count after twelve months"


def test_later_purchases_wait_for_later_proceeds(acct):
    s, pid, _, trade = acct
    trade("AAA", "BUY", 50, 100.0, MON)
    trade("CCC", "BUY", 50, 100.0, MON)  # settled money is now fully used
    trade("AAA", "SELL", 50, 100.0, TUE)  # 5,000 arrives Wednesday
    trade("BBB", "BUY", 50, 100.0, TUE)  # leans on Tuesday's sale
    trade("CCC", "SELL", 50, 100.0, WED)  # 5,000 arrives Thursday
    trade("AAA", "BUY", 30, 100.0, WED)  # Tuesday's proceeds settled this morning but BBB already claimed them
    state = st.simulate(s, pid, WED)
    assert {(r["ticker"], r["sell_freely_on"]) for r in state.restricted} == {("AAA", "2026-11-19")}
    assert st.simulate(s, pid, TUE).restricted == [{"ticker": "BBB", "quantity": 50, "sell_freely_on": "2026-11-18"}]


def test_a_fee_paid_in_coin_is_not_a_sale(acct):
    s, pid, secs, trade = acct
    trade("AAA", "BUY", 100, 100.0, MON)
    trade("AAA", "SELL", 100, 100.0, WED)
    trade("BTC", "BUY", 10, 100.0, WED)  # bought with unsettled proceeds: on hold until Thursday
    trade("BTC", "SELL", 0.025, 100.0, WED, fees=2.5)  # the broker's fee, taken in coin: brings in nothing
    state = st.simulate(s, pid, WED)
    assert state.violations == [] and state.restricted_quantity("BTC") == pytest.approx(9.975)


# --------------------------------------------------------------------------- the rules


def _rule(s, pid, kind):
    s.add(ComplianceRule(portfolio_id=pid, name=kind, rule_type=kind, params={}))
    s.commit()


def test_the_good_faith_rule_blocks_only_the_sale_that_would_break_it(acct):
    s, pid, secs, trade = acct
    _rule(s, pid, "no_good_faith_violations")
    trade("AAA", "BUY", 100, 100.0, MON)
    trade("AAA", "SELL", 100, 100.0, WED)
    assert not pre_trade_check(s, pid, [ProposedTrade(secs["BBB"].id, Side.BUY, 40)], WED, record=False).blocked, \
        "spending unsettled proceeds is allowed"
    trade("BBB", "BUY", 40, 100.0, WED)

    early = pre_trade_check(s, pid, [ProposedTrade(secs["BBB"].id, Side.SELL, 40)], WED, record=False)
    assert early.blocked and early.new_breaches[0].scope == "BBB" and "2026-11-19" in early.new_breaches[0].message
    assert not pre_trade_check(s, pid, [ProposedTrade(secs["BBB"].id, Side.SELL, 40)], THU, record=False).blocked, "a day later it is fine"
    assert post_trade_check(s, pid, WED, record=False).passed, "holding it is no breach"
    assert st.sale_restrictions(s, pid, WED) == {"BBB": (40, THU)}

    s.execute(select(ComplianceRule)).scalars().one().active = False
    s.commit()
    assert st.sale_restrictions(s, pid, WED) == {}, "no rule, nothing for a strategy to wait for"


def test_the_stricter_rule_only_lets_settled_money_be_spent(acct):
    s, pid, secs, trade = acct
    _rule(s, pid, "settled_funds_only")
    trade("AAA", "BUY", 100, 100.0, MON)
    trade("AAA", "SELL", 100, 100.0, WED)
    res = pre_trade_check(s, pid, [ProposedTrade(secs["BBB"].id, Side.BUY, 40)], WED, record=False)
    assert res.blocked and res.new_breaches[0].scope == "cash" and "4,000.00" in res.new_breaches[0].message
    assert not pre_trade_check(s, pid, [ProposedTrade(secs["BBB"].id, Side.BUY, 40)], THU, record=False).blocked
    assert not pre_trade_check(s, pid, [ProposedTrade(secs["CCC"].id, Side.BUY, 1, price=0.0)], WED, record=False).blocked


def test_fills_are_stamped_with_their_settlement_date_and_old_trades_can_be_backfilled(acct):
    from spectre.execution.brokers import PaperBroker
    from spectre.execution.guard import TradingLimits, execute
    from spectre.trading import oms

    s, pid, secs, trade = acct
    trade("AAA", "BUY", 10, 100.0, FRI)  # booked the old way, with no settlement date
    assert st.backfill_settlement_dates(s) == 1 and st.backfill_settlement_dates(s) == 0
    assert s.execute(select(Trade.settle_date)).scalar_one() == NEXT_MON

    o = oms.create_order(s, portfolio_id=pid, security_id=secs["BTC"].id, side=Side.BUY, quantity=1)
    execute(s, o.id, PaperBroker(), TradingLimits(max_order_notional=1e6, max_daily_notional=1e6, max_position_weight=1.0))
    coin = s.execute(select(Trade).where(Trade.security_id == secs["BTC"].id)).scalar_one()
    assert coin.settle_date == coin.trade_date
