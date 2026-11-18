"""US Treasury daily par yield curve, from the Treasury's own CSV download.

Verified against the live file on 2026-11-18: one row per business day, newest first, a `Date`
column in MM/DD/YYYY and one column per maturity ("1 Mo" ... "30 Yr"), yields in percent.
Maturities the Treasury did not publish on a given day are blank.
"""

from __future__ import annotations

import csv
import io
from datetime import date, datetime

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.rates.models import YieldPoint

URL = (
    "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/"
    "{year}/all?type=daily_treasury_yield_curve&field_tdr_date_value={year}&page&_format=csv"
)

# column heading -> (short name, maturity in years)
TENORS: dict[str, tuple[str, float]] = {
    "1 Mo": ("1M", 1 / 12), "1.5 Month": ("6W", 1.5 / 12), "2 Mo": ("2M", 2 / 12), "3 Mo": ("3M", 0.25),
    "4 Mo": ("4M", 4 / 12), "6 Mo": ("6M", 0.5), "1 Yr": ("1Y", 1.0), "2 Yr": ("2Y", 2.0), "3 Yr": ("3Y", 3.0),
    "5 Yr": ("5Y", 5.0), "7 Yr": ("7Y", 7.0), "10 Yr": ("10Y", 10.0), "20 Yr": ("20Y", 20.0), "30 Yr": ("30Y", 30.0),
}
YEARS = {short: years for short, years in TENORS.values()}


def parse_curve_csv(text: str) -> list[tuple[date, str, float, float]]:
    """(date, tenor, years, yield in percent) for every published point in the file."""
    out: list[tuple[date, str, float, float]] = []
    for row in csv.DictReader(io.StringIO(text)):
        raw = (row.get("Date") or "").strip()
        try:
            day = datetime.strptime(raw, "%m/%d/%Y").date()
        except ValueError:
            continue
        for column, (tenor, years) in TENORS.items():
            cell = (row.get(column) or "").strip()
            if not cell or cell.upper() == "N/A":
                continue
            try:
                out.append((day, tenor, years, float(cell)))
            except ValueError:
                continue
    return out


def store(session: Session, points: list[tuple[date, str, float, float]]) -> int:
    """Insert or update curve points. Returns how many were new."""
    if not points:
        return 0
    days = {p[0] for p in points}
    existing = {
        (y.date, y.tenor): y
        for y in session.execute(select(YieldPoint).where(YieldPoint.date.in_(days))).scalars()
    }
    new = 0
    for day, tenor, years, value in points:
        row = existing.get((day, tenor))
        if row is None:
            session.add(YieldPoint(date=day, tenor=tenor, years=years, value=value))
            new += 1
        else:
            row.value = value
    session.flush()
    return new


def sync(session: Session, years: list[int] | None = None, client: httpx.Client | None = None) -> dict:
    """Download the curve for the given calendar years (default: this year and last)."""
    this_year = date.today().year
    years = years or [this_year - 1, this_year]
    own = client is None
    client = client or httpx.Client(timeout=60, headers={"User-Agent": "spectre/0.1"}, follow_redirects=True)
    added = 0
    try:
        for year in years:
            r = client.get(URL.format(year=year))
            r.raise_for_status()
            added += store(session, parse_curve_csv(r.text))
    finally:
        if own:
            client.close()
    session.commit()
    latest = session.execute(select(YieldPoint.date).order_by(YieldPoint.date.desc()).limit(1)).scalar_one_or_none()
    return {"years": years, "new_points": added, "latest_date": latest.isoformat() if latest else None}
