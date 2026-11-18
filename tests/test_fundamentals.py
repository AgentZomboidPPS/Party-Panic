"""Fundamentals: reducing SEC filing facts to clean quarters and comparing them.

The payload below is shaped like the SEC's company-facts JSON (facts -> us-gaap -> concept ->
units -> list of {start, end, val, fy, fp, form, filed}) with invented numbers. The adapter has
not yet been run against the live service; these tests cover the period arithmetic.
"""

from datetime import date

import pytest

from spectre.db import init_db, make_engine, make_session_factory
from spectre.fundamentals import edgar
from spectre.fundamentals.compare import company_report
from spectre.models import Security


def row(start, end, val, form="10-Q", filed=None, fy=None, fp=None):
    return {"start": start, "end": end, "val": val, "form": form, "filed": filed or end, "fy": fy, "fp": fp}


# A calendar-year company. FY2025 and FY2026 Q1-Q3.
FACTS = {
    "cik": 1, "entityName": "Example Corp",
    "facts": {"us-gaap": {
        # Older years used the old concept name; the adapter must stitch the two together.
        "Revenues": {"units": {"USD": [
            row("2025-01-01", "2025-03-31", 100.0, fy=2025, fp="Q1"),
            row("2025-04-01", "2025-06-30", 110.0, fy=2025, fp="Q2"),
        ]}},
        "RevenueFromContractWithCustomerExcludingAssessedTax": {"units": {"USD": [
            row("2025-07-01", "2025-09-30", 120.0, fy=2025, fp="Q3"),
            row("2025-01-01", "2025-09-30", 330.0, fy=2025, fp="Q3"),          # nine months, same filing
            row("2025-01-01", "2025-12-31", 470.0, "10-K", "2026-02-10", 2025, "FY"),  # Q4 = 470 - 330 = 140
            row("2026-01-01", "2026-03-31", 150.0, fy=2026, fp="Q1"),
            row("2026-04-01", "2026-06-30", 160.0, fy=2026, fp="Q2", filed="2026-07-28"),
            row("2026-04-01", "2026-06-30", 162.0, fy=2026, fp="Q2", filed="2026-10-27"),  # restated later
            row("2026-07-01", "2026-09-30", 180.0, fy=2026, fp="Q3", filed="2026-10-27"),
        ]}},
        "GrossProfit": {"units": {"USD": [
            row("2025-07-01", "2025-09-30", 60.0), row("2026-04-01", "2026-06-30", 89.1), row("2026-07-01", "2026-09-30", 108.0),
        ]}},
        "NetIncomeLoss": {"units": {"USD": [
            row("2025-07-01", "2025-09-30", -5.0), row("2026-04-01", "2026-06-30", 16.2), row("2026-07-01", "2026-09-30", 27.0),
        ]}},
        # Cash flow is only ever reported year to date.
        "NetCashProvidedByUsedInOperatingActivities": {"units": {"USD": [
            row("2026-01-01", "2026-03-31", 30.0), row("2026-01-01", "2026-06-30", 70.0), row("2026-01-01", "2026-09-30", 125.0),
        ]}},
        # A full year with three stated quarters and no nine-month figure: Q4 = FY - (Q1 + Q2 + Q3).
        "EarningsPerShareDiluted": {"units": {"USD/shares": [
            row("2025-01-01", "2025-03-31", 1.00), row("2025-04-01", "2025-06-30", 1.10), row("2025-07-01", "2025-09-30", 1.20),
            row("2025-01-01", "2025-12-31", 4.80, "10-K", "2026-02-10"),
        ]}},
        "Assets": {"units": {"USD": [{"end": "2026-09-30", "val": 999.0, "form": "10-Q", "filed": "2026-10-27"}]}},
    }},
}


def test_stated_quarters_concept_stitching_and_restatements():
    q = {x.end: x for x in edgar.quarters(FACTS, "revenue")}
    assert [x.value for x in edgar.quarters(FACTS, "revenue")] == [100, 110, 120, 140, 150, 162, 180]
    assert q[date(2026, 6, 30)].value == 162.0, "the later filing restates the earlier one"
    assert q[date(2025, 3, 31)].derived is False and q[date(2025, 3, 31)].fiscal_period == "Q1"


def test_fourth_quarter_is_derived_from_the_annual_figure():
    q4 = next(x for x in edgar.quarters(FACTS, "revenue") if x.end == date(2025, 12, 31))
    assert q4.value == pytest.approx(140.0) and q4.derived and q4.start == date(2025, 10, 1) and q4.form == "10-K"
    eps = {x.end: x for x in edgar.quarters(FACTS, "eps_diluted")}
    assert eps[date(2025, 12, 31)].value == pytest.approx(4.80 - 3.30) and eps[date(2025, 12, 31)].derived


def test_year_to_date_only_metrics_are_differenced():
    cf = edgar.quarters(FACTS, "operating_cash_flow")
    assert [(x.end.month, x.value, x.derived) for x in cf] == [(3, 30.0, False), (6, 40.0, True), (9, 55.0, True)]


def test_missing_metric_and_instant_facts_are_ignored():
    assert edgar.quarters(FACTS, "operating_income") == []
    assert edgar.quarters({"facts": {}}, "revenue") == []


def test_client_refuses_to_run_without_a_declared_contact(monkeypatch):
    monkeypatch.setattr(edgar.settings, "sec_user_agent", "")
    with pytest.raises(ValueError, match="SPECTRE_SEC_USER_AGENT"):
        edgar.EdgarClient()
    with pytest.raises(ValueError):
        edgar.EdgarClient("a tool with no email")


def test_store_and_compare_latest_quarter():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        sec = Security(ticker="EXMP", name="Example Corp", asset_class="Equity", currency="USD")
        s.add(sec)
        s.flush()
        assert edgar.store(s, sec, FACTS) == 7 + 3 + 3 + 3 + 4
        assert edgar.store(s, sec, FACTS) == 20, "storing again updates in place"
        s.commit()
        r = company_report(s, sec.id, "EXMP")

    rev = r["metrics"]["revenue"]
    assert r["period_end"] == "2026-09-30" and rev["latest"] == 180.0
    assert rev["previous_quarter"] == 162.0 and rev["qoq"] == pytest.approx(180 / 162 - 1)
    assert rev["year_ago"] == 120.0 and rev["yoy"] == pytest.approx(0.5)
    assert [h["value"] for h in rev["history"]] == [100, 110, 120, 140, 150, 162, 180]

    ni = r["metrics"]["net_income"]
    assert ni["latest"] == 27.0 and ni["qoq"] == pytest.approx(27 / 16.2 - 1)
    assert ni["year_ago"] == -5.0 and ni["yoy"] is None, "growth from a loss is not a meaningful percentage"

    gm = r["margins"]["gross_margin"]
    assert gm["latest"] == pytest.approx(0.60) and gm["previous_quarter"] == pytest.approx(0.55)
    assert gm["change_vs_previous_pts"] == pytest.approx(5.0) and gm["change_vs_year_ago_pts"] == pytest.approx(10.0)
    assert r["margins"]["net_margin"]["latest"] == pytest.approx(0.15)
    assert "operating_margin" not in r["margins"], "no operating income reported, so no margin is invented"
    assert r["metrics"]["operating_cash_flow"]["latest"] == 55.0 and r["metrics"]["operating_cash_flow"]["derived"]
