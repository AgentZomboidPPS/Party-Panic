from __future__ import annotations

from datetime import date

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.models import FxRate


def fx_rate(session: Session, from_ccy: str, to_ccy: str, as_of: date) -> float:
    """Latest rate on or before `as_of` converting 1 `from_ccy` into `to_ccy`."""
    if from_ccy == to_ccy:
        return 1.0
    direct = session.execute(
        select(FxRate.rate)
        .where(
            FxRate.base_currency == from_ccy,
            FxRate.quote_currency == to_ccy,
            FxRate.date <= as_of,
        )
        .order_by(FxRate.date.desc())
        .limit(1)
    ).scalar_one_or_none()
    if direct is not None:
        return float(direct)
    inverse = session.execute(
        select(FxRate.rate)
        .where(
            FxRate.base_currency == to_ccy,
            FxRate.quote_currency == from_ccy,
            FxRate.date <= as_of,
        )
        .order_by(FxRate.date.desc())
        .limit(1)
    ).scalar_one_or_none()
    if inverse is not None:
        return 1.0 / float(inverse)
    raise LookupError(f"No FX rate for {from_ccy}/{to_ccy} on or before {as_of}")


def fx_series(session: Session, from_ccy: str, to_ccy: str, start: date, end: date) -> pd.Series:
    """Daily rate series for `from_ccy` -> `to_ccy` between start and end (inclusive)."""
    if from_ccy == to_ccy:
        idx = pd.bdate_range(start, end)
        return pd.Series(1.0, index=idx, name=f"{from_ccy}{to_ccy}")
    rows = session.execute(
        select(FxRate.date, FxRate.rate).where(
            FxRate.base_currency == from_ccy,
            FxRate.quote_currency == to_ccy,
            FxRate.date >= start,
            FxRate.date <= end,
        )
    ).all()
    invert = False
    if not rows:
        rows = session.execute(
            select(FxRate.date, FxRate.rate).where(
                FxRate.base_currency == to_ccy,
                FxRate.quote_currency == from_ccy,
                FxRate.date >= start,
                FxRate.date <= end,
            )
        ).all()
        invert = True
    if not rows:
        raise LookupError(f"No FX rates for {from_ccy}/{to_ccy} between {start} and {end}")
    s = pd.Series(
        {pd.Timestamp(d): float(r) for d, r in rows}, name=f"{from_ccy}{to_ccy}"
    ).sort_index()
    return (1.0 / s) if invert else s
