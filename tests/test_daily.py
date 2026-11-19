"""The daily report: what happened, why, what is held, and what needs attention."""

from datetime import date, datetime

from sqlalchemy import select

from spectre.marketdata.prices import upsert_prices
from spectre.models import Order, Security, Side, Trade
from spectre.portfolio import daily
from spectre.signals.strategy import run_once
from tests.test_strategy import LIMITS, T0, book  # noqa: F401  (the fixture)


def test_the_report_says_what_was_done_and_why(book):  # noqa: F811
    factory, pid, _ = book
    with factory() as s:
        run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)  # buys 13 NVDA; the reason is kept with the order
        day = s.execute(select(Order.created_at)).scalar_one().date()
        r = daily.daily_report(s, pid, day)
        (buy,) = r["orders_filled"]
        assert (buy["side"], buy["ticker"], buy["quantity"], buy["price"]) == ("BUY", "NVDA", 13, 150.0)
        assert buy["why"].startswith("score +") and "authors" in buy["why"]
        assert r["orders_not_filled"] == [] and r["nav"] == 10_000 and r["put_in"] == 10_000
        assert [h["ticker"] for h in r["holdings"]] == ["NVDA"] and r["holdings"][0]["open_pnl_pct"] == 0
        assert r["attention"] == [] and r["signal"] is None, "no broker given: no reconciliation, no signal check"

        text = daily.render(r)
        assert "KAIROS daily report" in text and "BUY  13 NVDA @ 150.00  (score +" in text
        assert "Holding 1 position and" in text and "Needs attention: nothing." in text

        # Selling a coin rounds to the smallest amount that trades and can leave a sliver worth
        # a cent or two (live: 0.000000254 of a bitcoin). That is not a holding worth listing.
        btc = s.execute(select(Security).where(Security.ticker == "BTC")).scalar_one()
        s.add(Trade(portfolio_id=pid, security_id=btc.id, side=Side.BUY.value, quantity=2.54e-7, price=62_000.0,
                    currency="USD", trade_date=day))
        upsert_prices(s, [{"security_id": btc.id, "date": day, "close": 62_000.0}])
        s.commit()
        r = daily.daily_report(s, pid, day)
        assert [h["ticker"] for h in r["holdings"]] == ["NVDA"] and "BTC" not in daily.render(r)
        assert daily.render(daily.daily_report(s, pid, date(2020, 1, 1))).count("It did not trade today.") == 1


def test_an_order_that_did_not_go_through_is_listed_with_the_reason(book):  # noqa: F811
    from spectre.execution.brokers import BrokerReject

    class Never:
        name, live = "never", False

        def submit(self, session, order):
            raise BrokerReject("no fill")

    factory, pid, _ = book
    with factory() as s:
        run_once(s, pid, broker=Never(), limits=LIMITS, top_n=2, invest=0.5)
        day = s.execute(select(Order.created_at)).scalar_one().date()
        r = daily.daily_report(s, pid, day)
        (miss,) = r["orders_not_filled"]
        assert miss["outcome"] == "CANCELLED" and "no fill" in miss["detail"] and r["orders_filled"] == []
        assert "1 orders did not go through" in daily.render(r) and "no fill" in daily.render(r)


def test_the_session_is_over_only_after_the_close_on_a_trading_day():
    wednesday, saturday, thanksgiving = datetime(2026, 11, 18), datetime(2026, 11, 21), datetime(2026, 11, 26)
    assert not daily.session_is_over(wednesday.replace(hour=20, minute=30), market_open=True), "winter: still open at 20:30 UTC"
    assert daily.session_is_over(wednesday.replace(hour=21, minute=1), market_open=False)
    assert daily.session_is_over(datetime(2026, 7, 15, 20, 5), market_open=False), "summer: the close is an hour earlier in UTC"
    assert not daily.session_is_over(wednesday.replace(hour=13), market_open=False), "not yet open is not over"
    assert not daily.session_is_over(saturday.replace(hour=22), market_open=False)
    assert not daily.session_is_over(thanksgiving.replace(hour=22), market_open=False)
    assert daily.session_is_over(wednesday.replace(hour=21, minute=5)) and not daily.session_is_over(wednesday.replace(hour=20, minute=59))


def test_one_report_a_day(book):  # noqa: F811
    factory, pid, _ = book
    with factory() as s:
        assert not daily.already_reported(s, pid, T0.date())
        daily.mark_reported(s, pid, T0.date())
        assert daily.already_reported(s, pid, T0.date()) and not daily.already_reported(s, pid, date(2026, 11, 19))


def test_every_cycle_is_written_to_the_journal_with_its_reasons(book):  # noqa: F811
    from datetime import timedelta

    from spectre.signals import journal

    factory, pid, _ = book
    t0 = datetime(2026, 11, 18, 15, 0)
    with factory() as s:
        r = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)
        journal.record_cycle(s, pid, [("stocks", a) for a in r.actions], ["stock market open"], r.targets, at=t0)
        skipped = {"ticker": "BTC", "side": "SELL", "quantity": 0.05, "price": 62_000.0, "outcome": "skipped",
                   "why": "score -0.08 fell to the exit level; held until 2026-11-19"}
        blocked = {"ticker": "AMD", "side": "BUY", "quantity": 3, "price": 520.0, "outcome": "blocked", "why": "score +1.2",
                   "detail": "broker: not filled within 20s; cancelled", "order_id": 99}
        journal.record_cycle(s, pid, [("coins", skipped), ("stocks", blocked)], [], at=t0 + timedelta(minutes=10))
        journal.record_cycle(s, pid, [], [], ["NVDA", "ETH"], at=t0 + timedelta(minutes=20))

        feed = journal.recent(s, pid)
        assert feed["last_looked_at"] == "2026-11-18T15:20:00", "a cycle that did nothing still counts as having looked"
        rows = feed["decisions"]
        assert [(d["book"], d["ticker"], d["outcome"]) for d in rows] == [
            ("stocks", "AMD", "blocked"), ("coins", "BTC", "skipped"), ("stocks", "NVDA", "executed"), ("system", None, "note")]
        assert rows[0]["why"] == "score +1.2 — broker: not filled within 20s; cancelled", "the reason and what stopped it"
        assert rows[2]["quantity"] == 13 and rows[2]["price"] == 150.0 and rows[2]["why"].startswith("score +") and rows[2]["order_id"]
        idle = journal.recent(s, pid, include_idle=True)["decisions"][0]
        assert idle["outcome"] == "idle" and "NVDA, ETH" in idle["why"]
        assert journal.recent(s, 999)["last_looked_at"] is None


def test_the_api_serves_the_journal_and_what_each_holding_cost(book):  # noqa: F811
    from fastapi.testclient import TestClient

    from spectre.api.app import create_app
    from spectre.signals import journal

    factory, pid, _ = book
    with factory() as s:
        r = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)  # 13 NVDA at 150
        journal.record_cycle(s, pid, [("stocks", a) for a in r.actions], [])
        from tests.test_strategy import _set_price

        _set_price(s, "NVDA", 156.0)
        web = TestClient(create_app(engine=s.get_bind()))
        feed = web.get(f"/portfolios/{pid}/activity").json()
        assert feed["minutes_since"] < 1 and feed["decisions"][0]["ticker"] == "NVDA"
        (pos,) = web.get(f"/portfolios/{pid}/positions").json()["positions"]
        assert pos["average_cost"] == 150.0 and pos["open_pnl"] == 13 * 6.0 and round(pos["open_pnl_pct"], 4) == 0.04


def test_needs_attention_lists_what_a_person_should_look_at(book):  # noqa: F811
    from spectre.execution.guard import set_halt
    from spectre.signals import journal
    from tests.test_strategy import _set_price

    factory, pid, _ = book
    with factory() as s:
        assert daily.needs_attention(s, pid) == ["the bot has never run on this portfolio"]
        assert daily.needs_attention(s, pid, liveness=False) == [], "all is well: nothing to say"

        run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)  # 13 NVDA at 150 in a 10,000 account
        journal.record_cycle(s, pid, [], [])
        assert daily.needs_attention(s, pid) == []

        journal.record_cycle(s, pid, [], [], at=datetime(2026, 11, 18, 15, 0))
        s.execute(journal.BotDecision.__table__.delete().where(journal.BotDecision.at > datetime(2026, 11, 18, 16, 0)))
        s.commit()
        (stale,) = daily.needs_attention(s, pid)
        assert "last looked" in stale and "every ten" in stale

        set_halt(s, True, "tester", "checking")
        _set_price(s, "NVDA", 100.0)  # 13 x -50 = -650: 6.5% down on the day it started
        lines = daily.needs_attention(s, pid, liveness=False)
        assert lines[0].startswith("trading is halted (checking)") and "buying is paused: the account is 6.5% down today" in lines[1]
        assert "buying is paused" in daily.render(daily.daily_report(s, pid))


def test_the_portfolio_kairos_is_trading_is_marked_so_the_dashboard_opens_on_it():
    from fastapi.testclient import TestClient

    from spectre.api.app import create_app
    from spectre.db import init_db, make_engine, make_session_factory
    from spectre.models import Portfolio
    from spectre.signals import journal

    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        s.add_all([Portfolio(name="old paper book", base_currency="USD"), Portfolio(name="live", base_currency="USD")])
        s.commit()
        web = TestClient(create_app(engine=e))
        assert [p["is_live"] for p in web.get("/portfolios").json()] == [False, False]
        journal.record_cycle(s, 2, [], [])
        assert [(p["name"], p["is_live"]) for p in web.get("/portfolios").json()] == [("old paper book", False), ("live", True)]
