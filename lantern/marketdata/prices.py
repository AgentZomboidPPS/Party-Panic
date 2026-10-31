from __future__ import annotations

from collections.abc import Iterable
from datetime import date, timedelta

import pandas as pd
from sqlalchemy import func, insert, select
from sqlalchemy.orm import Session

from lantern.marketdata.fx import fx_series
from lantern.models import Price, Security


def latest_price_date(session: Session) -> date | None:
    return session.execute(select(func.max(Price.date))).scalar_one_or_none()


def latest_prices(session: Session, security_ids: Iterable[int], as_of: date) -> pd.Series:
    """Most recent close on or before `as_of` for each security. Missing securities are absent."""
    ids = list(security_ids)
    if not ids:
        return pd.Series(dtype=float)
    latest = (
        select(Price.security_id, func.max(Price.date).label("d"))
        .where(Price.security_id.in_(ids), Price.date <= as_of)
        .group_by(Price.security_id)
        .subquery()
    )
    rows = session.execute(
        select(Price.security_id, Price.close).join(
            latest, (Price.security_id == latest.c.security_id) & (Price.date == latest.c.d)
        )
    ).all()
    return pd.Series({sid: float(px) for sid, px in rows}, dtype=float)


def price_matrix(
    session: Session,
    security_ids: Iterable[int],
    end: date,
    lookback_days: int = 500,
    base_currency: str | None = None,
) -> pd.DataFrame:
    """Daily close prices (rows: dates, columns: security ids).

    When `base_currency` is given, prices are converted so returns include FX moves.
    Dates where any security lacks a price are forward-filled, then dropped if still missing.
    """
    ids = list(security_ids)
    if not ids:
        return pd.DataFrame()
    start = end - timedelta(days=int(lookback_days * 1.6) + 10)  # calendar days for N trading days
    rows = session.execute(
        select(Price.security_id, Price.date, Price.close).where(
            Price.security_id.in_(ids), Price.date >= start, Price.date <= end
        )
    ).all()
    if not rows:
        return pd.DataFrame(columns=ids)
    df = pd.DataFrame(rows, columns=["security_id", "date", "close"])
    df["date"] = pd.to_datetime(df["date"])
    px = df.pivot(index="date", columns="security_id", values="close").sort_index()

    if base_currency:
        ccy_rows = session.execute(
            select(Security.id, Security.currency).where(Security.id.in_(ids))
        ).all()
        by_ccy: dict[str, list[int]] = {}
        for sid, ccy in ccy_rows:
            by_ccy.setdefault(ccy, []).append(sid)
        for ccy, cols in by_ccy.items():
            if ccy == base_currency:
                continue
            fx = fx_series(session, ccy, base_currency, start, end)
            fx = fx.reindex(px.index).ffill().bfill()
            px[cols] = px[cols].mul(fx, axis=0)

    px = px.ffill().dropna(how="any")
    return px.tail(lookback_days + 1)


def returns_from_prices(prices: pd.DataFrame) -> pd.DataFrame:
    return prices.pct_change().dropna(how="all").fillna(0.0)


def upsert_prices(session: Session, rows: list[dict]) -> int:
    """Insert price rows ({security_id, date, close}); existing (security, date) pairs are replaced."""
    if not rows:
        return 0
    keys = {(r["security_id"], r["date"]) for r in rows}
    sids = {k[0] for k in keys}
    dates = {k[1] for k in keys}
    existing = session.execute(
        select(Price).where(Price.security_id.in_(sids), Price.date.in_(dates))
    ).scalars()
    existing_map = {(p.security_id, p.date): p for p in existing}
    new_rows = []
    for r in rows:
        key = (r["security_id"], r["date"])
        if key in existing_map:
            existing_map[key].close = float(r["close"])
        else:
            new_rows.append({"security_id": key[0], "date": key[1], "close": float(r["close"])})
    if new_rows:
        session.execute(insert(Price), new_rows)
    session.flush()
    return len(rows)
