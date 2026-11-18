"""The daily report: what happened, why, what is held, and what needs attention."""

from datetime import date, datetime

from sqlalchemy import select

from spectre.models import Order
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
        assert "Holding 1 positions" in text and "Needs attention: nothing." in text
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
