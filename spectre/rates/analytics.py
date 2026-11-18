"""Reading the curve: today's shape, how it has moved, and whether it is inverted."""

from __future__ import annotations

from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.rates.models import MacroSeries, YieldPoint
from spectre.rates.treasury import YEARS

KEY_TENORS = ("3M", "2Y", "5Y", "10Y", "30Y")


def _curve_on(session: Session, day: date) -> dict[str, float]:
    return dict(session.execute(select(YieldPoint.tenor, YieldPoint.value).where(YieldPoint.date == day)).all())


def _bp(a: float | None, b: float | None) -> float | None:
    """Difference of two yields in basis points."""
    return None if a is None or b is None else round((a - b) * 100, 1)


def latest_curve(session: Session) -> dict | None:
    """The newest curve, with changes over one day, about a week and about a month (in basis
    points), the 2s10s and 3m10y slopes, and an inversion flag."""
    days = list(session.execute(select(YieldPoint.date).distinct().order_by(YieldPoint.date.desc()).limit(30)).scalars())
    if not days:
        return None
    today = _curve_on(session, days[0])
    prior = {
        "1d": _curve_on(session, days[1]) if len(days) > 1 else {},
        "1w": _curve_on(session, days[5]) if len(days) > 5 else {},
        "1m": _curve_on(session, days[21]) if len(days) > 21 else {},
    }
    points = [
        {
            "tenor": tenor, "years": YEARS[tenor], "yield": value,
            "change_1d_bp": _bp(value, prior["1d"].get(tenor)),
            "change_1w_bp": _bp(value, prior["1w"].get(tenor)),
            "change_1m_bp": _bp(value, prior["1m"].get(tenor)),
            "yield_1m_ago": prior["1m"].get(tenor),
        }
        for tenor, value in sorted(today.items(), key=lambda kv: YEARS.get(kv[0], 99))
        if tenor in YEARS
    ]

    def slope(curve: dict[str, float], long: str, short: str) -> float | None:
        return _bp(curve.get(long), curve.get(short))

    s_2s10s, s_3m10y = slope(today, "10Y", "2Y"), slope(today, "10Y", "3M")
    return {
        "date": days[0].isoformat(),
        "compared_with": {"1d": days[1].isoformat() if len(days) > 1 else None,
                          "1w": days[5].isoformat() if len(days) > 5 else None,
                          "1m": days[21].isoformat() if len(days) > 21 else None},
        "points": points,
        "slope_2s10s_bp": s_2s10s,
        "slope_2s10s_1m_ago_bp": slope(prior["1m"], "10Y", "2Y"),
        "slope_3m10y_bp": s_3m10y,
        "inverted": bool((s_2s10s is not None and s_2s10s < 0) or (s_3m10y is not None and s_3m10y < 0)),
    }


def history(session: Session, tenor: str, limit: int = 260) -> list[dict]:
    rows = session.execute(
        select(YieldPoint.date, YieldPoint.value).where(YieldPoint.tenor == tenor.upper())
        .order_by(YieldPoint.date.desc()).limit(limit)
    ).all()
    return [{"date": d.isoformat(), "yield": v} for d, v in reversed(rows)]


def latest_macro(session: Session) -> list[dict]:
    """Newest value of each stored macro series with its change over about a month."""
    out = []
    for sid in session.execute(select(MacroSeries.series).distinct()).scalars():
        rows = session.execute(
            select(MacroSeries.date, MacroSeries.value).where(MacroSeries.series == sid)
            .order_by(MacroSeries.date.desc()).limit(22)
        ).all()
        if rows:
            out.append({"series": sid, "date": rows[0][0].isoformat(), "value": rows[0][1],
                        "change_1m": (rows[0][1] - rows[-1][1]) if len(rows) > 21 else None})
    return sorted(out, key=lambda r: r["series"])
