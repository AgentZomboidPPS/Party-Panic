"""SEC EDGAR: fetch a company's tagged financial facts and reduce them to clean quarters.

The awkward part of filings is that they do not report every quarter directly:
- a 10-Q income statement gives the three months and the year to date;
- a 10-Q cash-flow statement gives only the year to date (3, 6, 9 months);
- a 10-K gives the full year, so the fourth quarter is never stated on its own.

`quarters()` therefore takes a three-month figure when one exists and otherwise derives the
quarter by subtraction (nine months minus six, full year minus nine months, or full year minus
three stated quarters). Derived values are flagged. For per-share figures the subtraction is the
usual approximation, since share counts drift during the year.

Network access needs a declared contact: set LANTERN_SEC_USER_AGENT="Name you@example.com".
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import date, timedelta

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.config import settings
from lantern.fundamentals.models import Fundamental
from lantern.models import Security

# metric -> (XBRL concepts that carry it, newest naming first; unit)
METRICS: dict[str, tuple[tuple[str, ...], str]] = {
    "revenue": (("RevenueFromContractWithCustomerExcludingAssessedTax", "Revenues", "SalesRevenueNet",
                 "RevenueFromContractWithCustomerIncludingAssessedTax"), "USD"),
    "gross_profit": (("GrossProfit",), "USD"),
    "operating_income": (("OperatingIncomeLoss",), "USD"),
    "net_income": (("NetIncomeLoss",), "USD"),
    "eps_diluted": (("EarningsPerShareDiluted",), "USD/shares"),
    "operating_cash_flow": (("NetCashProvidedByUsedInOperatingActivities",), "USD"),
}
QUARTER_DAYS = (80, 100)
TOLERANCE = timedelta(days=4)  # fiscal calendars shift a few days between years


@dataclass(frozen=True)
class Quarter:
    metric: str
    start: date
    end: date
    value: float
    fiscal_year: int | None
    fiscal_period: str | None
    form: str | None
    filed: date | None
    derived: bool = False


def _is_quarter(start: date, end: date) -> bool:
    return QUARTER_DAYS[0] <= (end - start).days <= QUARTER_DAYS[1]


def _periods(facts: dict, metric: str) -> dict[tuple[date, date], dict]:
    """Every reported (start, end) span for the metric, keeping the most recently filed value
    for each span (later filings restate earlier ones) across all the concepts that carry it."""
    concepts, unit = METRICS[metric]
    gaap = (facts.get("facts") or {}).get("us-gaap") or {}
    out: dict[tuple[date, date], dict] = {}
    for concept in concepts:
        for row in ((gaap.get(concept) or {}).get("units") or {}).get(unit, []):
            if not row.get("start") or not row.get("end") or row.get("val") is None:
                continue  # instant (balance-sheet) facts have no start
            try:
                key = (date.fromisoformat(row["start"]), date.fromisoformat(row["end"]))
                filed = date.fromisoformat(row["filed"]) if row.get("filed") else None
            except ValueError:
                continue
            cur = out.get(key)
            if cur is None or (filed or date.min) > (cur["filed"] or date.min):
                out[key] = {"val": float(row["val"]), "filed": filed, "form": row.get("form"), "fy": row.get("fy"),
                            "fp": row.get("fp")}
    return out


def quarters(facts: dict, metric: str) -> list[Quarter]:
    """One value per fiscal quarter, oldest first. Stated three-month figures win; the rest are derived."""
    periods = _periods(facts, metric)
    by_end: dict[date, Quarter] = {}
    for (start, end), r in periods.items():
        if _is_quarter(start, end):
            by_end[end] = Quarter(metric, start, end, r["val"], r["fy"], r["fp"], r["form"], r["filed"])

    longer = sorted((k for k in periods if not _is_quarter(*k)), key=lambda k: (k[1], k[1] - k[0]))
    for start, end in longer:
        if end in by_end:
            continue
        r = periods[(start, end)]
        # 1) year-to-date minus the previous year-to-date with the same start
        prefix = [
            (s2, e2) for (s2, e2) in periods
            if abs(s2 - start) <= TOLERANCE and e2 < end and QUARTER_DAYS[0] <= (end - e2).days <= QUARTER_DAYS[1]
        ]
        if prefix:
            s2, e2 = max(prefix, key=lambda k: k[1])
            by_end[end] = Quarter(metric, e2 + timedelta(days=1), end, r["val"] - periods[(s2, e2)]["val"], r["fy"], r["fp"],
                                  r["form"], r["filed"], derived=True)
            continue
        # 2) the span minus the stated quarters that tile its beginning
        inside = sorted((q for q in by_end.values() if q.start >= start - TOLERANCE and q.end < end and not q.derived),
                        key=lambda q: q.end)
        if not inside:
            continue
        tiles = abs(inside[0].start - start) <= TOLERANCE and all(
            abs(b.start - (a.end + timedelta(days=1))) <= TOLERANCE for a, b in zip(inside, inside[1:], strict=False)
        )
        last = inside[-1].end
        if tiles and QUARTER_DAYS[0] <= (end - last).days <= QUARTER_DAYS[1]:
            by_end[end] = Quarter(metric, last + timedelta(days=1), end, r["val"] - sum(q.value for q in inside), r["fy"],
                                  r["fp"], r["form"], r["filed"], derived=True)
    return sorted(by_end.values(), key=lambda q: q.end)


# --------------------------------------------------------------------------- network


class EdgarClient:
    """Minimal EDGAR client. The SEC asks for a declared contact and at most 10 requests a second."""

    def __init__(self, user_agent: str | None = None, pause: float = 0.15):
        ua = user_agent or settings.sec_user_agent
        if not ua or "@" not in ua:
            raise ValueError(
                'The SEC requires a contact: set LANTERN_SEC_USER_AGENT="Your Name you@example.com" '
                "(environment variable or .env file)"
            )
        self._client = httpx.Client(timeout=60, headers={"User-Agent": ua, "Accept-Encoding": "gzip, deflate"})
        self._pause = pause
        self._ciks: dict[str, int] | None = None

    def _get(self, url: str) -> dict:
        time.sleep(self._pause)
        r = self._client.get(url)
        r.raise_for_status()
        return r.json()

    def cik(self, ticker: str) -> int | None:
        if self._ciks is None:
            data = self._get("https://www.sec.gov/files/company_tickers.json")
            self._ciks = {str(v["ticker"]).upper(): int(v["cik_str"]) for v in data.values()}
        return self._ciks.get(ticker.upper().replace(".", "-"))

    def company_facts(self, cik: int) -> dict:
        return self._get(f"https://data.sec.gov/api/xbrl/companyfacts/CIK{cik:010d}.json")

    def close(self) -> None:
        self._client.close()


def store(session: Session, security: Security, facts: dict, keep: int = 24) -> int:
    """Replace the stored quarters for one company with the latest `keep` per metric."""
    n = 0
    for metric in METRICS:
        qs = quarters(facts, metric)[-keep:]
        if not qs:
            continue
        existing = {
            f.period_end: f
            for f in session.execute(
                select(Fundamental).where(Fundamental.security_id == security.id, Fundamental.metric == metric)
            ).scalars()
        }
        for q in qs:
            row = existing.get(q.end)
            if row is None:
                row = Fundamental(security_id=security.id, ticker=security.ticker, metric=metric, period_end=q.end,
                                  period_start=q.start, value=q.value)
                session.add(row)
            row.period_start, row.value, row.fiscal_year, row.fiscal_period = q.start, q.value, q.fiscal_year, q.fiscal_period
            row.form, row.filed, row.derived = q.form, q.filed, q.derived
            n += 1
    session.flush()
    return n


def sync(session: Session, tickers: list[str] | None = None, client: EdgarClient | None = None) -> dict:
    """Fetch and store fundamentals for the given tickers (default: every equity in the book)."""
    client = client or EdgarClient()
    q = select(Security).where(Security.asset_class == "Equity")
    if tickers:
        q = select(Security).where(Security.ticker.in_([t.upper() for t in tickers]))
    done, skipped = {}, {}
    for sec in session.execute(q).scalars():
        cik = client.cik(sec.ticker)
        if cik is None:
            skipped[sec.ticker] = "not an SEC filer under this ticker"
            continue
        try:
            done[sec.ticker] = store(session, sec, client.company_facts(cik))
        except httpx.HTTPError as exc:
            skipped[sec.ticker] = f"{type(exc).__name__}: {exc}"
    session.commit()
    return {"stored": done, "skipped": skipped}
