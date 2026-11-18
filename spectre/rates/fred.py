"""FRED (St. Louis Fed) daily series: credit spreads, the policy rate, inflation expectations.

Verified against the live service on 2026-11-18. The keyless graph download returns, for ONE
series, a CSV with an `observation_date` column and one value column (blank on holidays).
Asking for several series at once returns a ZIP archive instead, so series are fetched one
request each. (FRED's servers dropped connections from `curl` on the build machine but answer
ordinary HTTP/1.1 clients.)
"""

from __future__ import annotations

import csv
import io
from datetime import date

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.rates.models import MacroSeries

URL = "https://fred.stlouisfed.org/graph/fredgraph.csv"

SERIES = {
    "BAMLC0A0CM": "Investment-grade corporate spread over Treasuries (percentage points)",
    "BAMLH0A0HYM2": "High-yield corporate spread over Treasuries (percentage points)",
    "DFF": "Effective federal funds rate (percent)",
    "T10YIE": "10-year breakeven inflation (percent)",
    "DFII10": "10-year real yield (percent)",
}


def parse_fred_csv(text: str) -> dict[str, list[tuple[date, float]]]:
    """series id -> [(date, value)], skipping missing observations."""
    reader = csv.reader(io.StringIO(text))
    header = next(reader, None)
    if not header or len(header) < 2:
        return {}
    ids = [h.strip() for h in header[1:]]
    out: dict[str, list[tuple[date, float]]] = {i: [] for i in ids}
    for row in reader:
        if not row:
            continue
        try:
            day = date.fromisoformat(row[0].strip())
        except ValueError:
            continue
        for sid, cell in zip(ids, row[1:], strict=False):
            cell = cell.strip()
            if cell in ("", "."):
                continue
            try:
                out[sid].append((day, float(cell)))
            except ValueError:
                continue
    return out


def store(session: Session, data: dict[str, list[tuple[date, float]]]) -> int:
    new = 0
    for sid, points in data.items():
        if not points:
            continue
        existing = {
            m.date: m for m in session.execute(select(MacroSeries).where(MacroSeries.series == sid)).scalars()
        }
        for day, value in points:
            row = existing.get(day)
            if row is None:
                session.add(MacroSeries(series=sid, date=day, value=value))
                new += 1
            else:
                row.value = value
    session.flush()
    return new


def sync(session: Session, series: list[str] | None = None, start: date | None = None,
         client: httpx.Client | None = None) -> dict:
    """Fetch each series (one request each) and store it. A series that fails is reported, not fatal."""
    series = series or list(SERIES)
    start = start or date(date.today().year - 1, 1, 1)
    own = client is None
    client = client or httpx.Client(timeout=30, headers={"User-Agent": "spectre/0.1"}, follow_redirects=True)
    new, failed = 0, {}
    try:
        for sid in series:
            try:
                r = client.get(URL, params={"id": sid, "cosd": start.isoformat()})
                r.raise_for_status()
                if "zip" in r.headers.get("content-type", ""):
                    raise httpx.HTTPError("got a ZIP archive, expected CSV")
                new += store(session, parse_fred_csv(r.text))
            except httpx.HTTPError as exc:
                failed[sid] = f"{type(exc).__name__}: {exc}"
    finally:
        if own:
            client.close()
    session.commit()
    return {"series": series, "new_points": new, "failed": failed}
