"""Compare a company's latest quarter with the previous quarter and the same quarter a year ago."""

from __future__ import annotations

from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.fundamentals.models import Fundamental

MARGINS = {"gross_margin": "gross_profit", "operating_margin": "operating_income", "net_margin": "net_income"}


def _pct(new: float | None, old: float | None) -> float | None:
    """Growth rate, or None when the base is zero or negative (a percentage would mislead)."""
    if new is None or old is None or old <= 0:
        return None
    return new / old - 1.0


def _series(session: Session, security_id: int, metric: str) -> list[Fundamental]:
    return list(
        session.execute(
            select(Fundamental)
            .where(Fundamental.security_id == security_id, Fundamental.metric == metric)
            .order_by(Fundamental.period_end)
        ).scalars()
    )


def _year_ago(rows: list[Fundamental], end: date) -> Fundamental | None:
    best = [r for r in rows if 350 <= (end - r.period_end).days <= 380]
    return best[-1] if best else None


def metric_comparison(rows: list[Fundamental]) -> dict | None:
    if not rows:
        return None
    latest = rows[-1]
    prev = rows[-2] if len(rows) > 1 and 80 <= (latest.period_end - rows[-2].period_end).days <= 100 else None
    yago = _year_ago(rows, latest.period_end)
    return {
        "period_end": latest.period_end.isoformat(),
        "fiscal_period": f"{latest.fiscal_period or ''} {latest.fiscal_year or ''}".strip() or None,
        "filed": latest.filed.isoformat() if latest.filed else None,
        "derived": latest.derived,
        "latest": latest.value,
        "previous_quarter": prev.value if prev else None,
        "year_ago": yago.value if yago else None,
        "qoq": _pct(latest.value, prev.value if prev else None),
        "yoy": _pct(latest.value, yago.value if yago else None),
        "history": [{"period_end": r.period_end.isoformat(), "value": r.value} for r in rows[-8:]],
    }


def company_report(session: Session, security_id: int, ticker: str) -> dict:
    """Latest quarter against the previous one and a year ago, for every metric, plus margins."""
    series = {m: _series(session, security_id, m) for m in
              ("revenue", "gross_profit", "operating_income", "net_income", "eps_diluted", "operating_cash_flow")}
    metrics = {m: c for m, rows in series.items() if (c := metric_comparison(rows))}
    report: dict = {"ticker": ticker, "metrics": metrics, "margins": {}}
    rev = {r.period_end: r.value for r in series["revenue"]}
    if "revenue" in metrics:
        latest_end = series["revenue"][-1].period_end
        prev_end = series["revenue"][-2].period_end if len(series["revenue"]) > 1 else None
        yago = _year_ago(series["revenue"], latest_end)
        for name, source in MARGINS.items():
            vals = {r.period_end: r.value for r in series[source]}

            def margin(end: date | None, vals=vals) -> float | None:
                if end is None or end not in vals or not rev.get(end):
                    return None
                return vals[end] / rev[end]

            now, before, last_year = margin(latest_end), margin(prev_end), margin(yago.period_end if yago else None)
            if now is not None:
                report["margins"][name] = {
                    "latest": now, "previous_quarter": before, "year_ago": last_year,
                    "change_vs_previous_pts": (now - before) * 100 if before is not None else None,
                    "change_vs_year_ago_pts": (now - last_year) * 100 if last_year is not None else None,
                }
        report["period_end"] = latest_end.isoformat()
    return report
