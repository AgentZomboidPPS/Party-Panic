"""Bond market data: Treasury curve parsing (shape verified live), curve analytics, FRED parsing."""

from datetime import date, timedelta

import httpx
import pytest

from spectre.db import init_db, make_engine, make_session_factory
from spectre.rates import analytics, fred, treasury

# The Treasury file as served on 2026-11-18: newest first, blanks where nothing was published.
CSV = '''Date,"1 Mo","1.5 Month","2 Mo","3 Mo","4 Mo","6 Mo","1 Yr","2 Yr","3 Yr","5 Yr","7 Yr","10 Yr","20 Yr","30 Yr"
11/17/2026,4.09,4.24,4.26,4.33,4.32,4.41,4.60,4.80,4.84,4.90,4.99,5.10,5.50,5.46
11/16/2026,4.10,4.19,4.27,4.34,4.33,4.42,4.62,4.83,4.87,4.93,5.01,5.12,5.51,5.46
11/13/2026,4.10,,4.27,4.35,N/A,4.43,4.61,4.79,4.82,4.88,4.97,5.07,5.47,5.43
not a date,1,1,1,1,1,1,1,1,1,1,1,1,1,1
'''


def test_treasury_csv_parsing():
    pts = treasury.parse_curve_csv(CSV)
    by = {(d, t): v for d, t, _, v in pts}
    assert by[(date(2026, 11, 17), "10Y")] == 5.10 and by[(date(2026, 11, 17), "6W")] == 4.24
    assert (date(2026, 11, 13), "6W") not in by and (date(2026, 11, 13), "4M") not in by, "blank and N/A are skipped"
    assert len({d for d, *_ in pts}) == 3, "the junk row is ignored"
    years = {t: y for _, t, y, _ in pts}
    assert years["3M"] == 0.25 and years["30Y"] == 30.0 and years["1M"] == pytest.approx(1 / 12)


@pytest.fixture
def session():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        yield s


def test_store_is_idempotent_and_updates_revisions(session):
    assert treasury.store(session, treasury.parse_curve_csv(CSV)) == 14 + 14 + 12
    revised = CSV.replace("11/17/2026,4.09", "11/17/2026,4.11")
    assert treasury.store(session, treasury.parse_curve_csv(revised)) == 0
    assert analytics.latest_curve(session)["points"][0]["yield"] == 4.11


def test_sync_downloads_each_year(session):
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        return httpx.Response(200, text=CSV if "/2026/" in str(request.url) else CSV.splitlines()[0] + "\n")

    r = treasury.sync(session, years=[2025, 2026], client=httpx.Client(transport=httpx.MockTransport(handler)))
    assert r["new_points"] == 40 and r["latest_date"] == "2026-11-17"
    assert len(seen) == 2 and "daily_treasury_yield_curve" in seen[0] and "field_tdr_date_value=2025" in seen[0]


def test_curve_changes_and_slopes(session):
    # 30 business days of a curve where the 2-year rises 1bp a day and the 10-year is flat:
    # the 2s10s slope shrinks until the curve inverts.
    day, points = date(2026, 11, 17), []
    for i in range(30):
        while day.weekday() >= 5:
            day -= timedelta(days=1)
        points += [(day, "3M", 0.25, 4.30), (day, "2Y", 2.0, 5.15 - 0.01 * i), (day, "10Y", 10.0, 5.10)]
        day -= timedelta(days=1)
    treasury.store(session, points)
    c = analytics.latest_curve(session)
    two = next(p for p in c["points"] if p["tenor"] == "2Y")
    assert [p["tenor"] for p in c["points"]] == ["3M", "2Y", "10Y"], "ordered by maturity"
    assert two["yield"] == 5.15 and two["change_1d_bp"] == 1.0 and two["change_1w_bp"] == 5.0 and two["change_1m_bp"] == 21.0
    assert two["yield_1m_ago"] == pytest.approx(4.94)
    assert c["slope_2s10s_bp"] == -5.0 and c["slope_2s10s_1m_ago_bp"] == 16.0 and c["slope_3m10y_bp"] == 80.0
    assert c["inverted"] is True
    hist = analytics.history(session, "2y", limit=5)
    assert [h["yield"] for h in hist] == pytest.approx([5.11, 5.12, 5.13, 5.14, 5.15]), "oldest first"


def test_empty_database_has_no_curve(session):
    assert analytics.latest_curve(session) is None and analytics.latest_macro(session) == []


def test_fred_csv_parsing_and_latest_values(session):
    text = "observation_date,BAMLH0A0HYM2,DFF\n2026-11-13,3.10,4.33\n2026-11-16,.,4.33\n2026-11-17,3.25,4.33\nbad,1,2\n"
    data = fred.parse_fred_csv(text)
    assert data["BAMLH0A0HYM2"] == [(date(2026, 11, 13), 3.10), (date(2026, 11, 17), 3.25)], "'.' means no observation"
    assert len(data["DFF"]) == 3
    assert fred.store(session, data) == 5 and fred.store(session, data) == 0
    latest = {m["series"]: m for m in analytics.latest_macro(session)}
    assert latest["BAMLH0A0HYM2"]["value"] == 3.25 and latest["BAMLH0A0HYM2"]["date"] == "2026-11-17"
    assert latest["DFF"]["change_1m"] is None, "not enough history for a monthly change"
    assert fred.parse_fred_csv("") == {}
    # Holidays arrive as an empty cell in the live file.
    assert fred.parse_fred_csv("observation_date,DGS10\n2026-11-10,4.98\n2026-11-11,\n")["DGS10"] == [(date(2026, 11, 10), 4.98)]


def test_fred_sync_fetches_one_series_per_request_and_survives_failures(session):
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        sid = request.url.params["id"]
        calls.append(sid)
        if sid == "DFF":
            return httpx.Response(500)
        if sid == "T10YIE":  # what the service sends when several series are requested at once
            return httpx.Response(200, content=b"PK\x03\x04", headers={"content-type": "application/zip"})
        return httpx.Response(200, text=f"observation_date,{sid}\n2026-11-17,3.43\n", headers={"content-type": "application/csv"})

    r = fred.sync(session, series=["BAMLH0A0HYM2", "DFF", "T10YIE"], client=httpx.Client(transport=httpx.MockTransport(handler)))
    assert calls == ["BAMLH0A0HYM2", "DFF", "T10YIE"], "one request per series"
    assert r["new_points"] == 1 and set(r["failed"]) == {"DFF", "T10YIE"}
    assert [m["series"] for m in analytics.latest_macro(session)] == ["BAMLH0A0HYM2"]
