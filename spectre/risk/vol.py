"""How much each security has been moving lately, for sizing positions by risk rather than by dollars."""

from __future__ import annotations

from datetime import date, timedelta

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.models import Price


def recent_vols(session: Session, security_ids, as_of: date, window: int = 60, min_obs: int = 20) -> dict[int, float]:
    """Annualised volatility of daily returns over about the last `window` trading days, per
    security id. Securities with fewer than `min_obs` returns are left out rather than guessed."""
    ids = list(security_ids)
    if not ids:
        return {}
    since = as_of - timedelta(days=int(window * 1.6) + 10)
    rows = session.execute(
        select(Price.security_id, Price.date, Price.close)
        .where(Price.security_id.in_(ids), Price.date <= as_of, Price.date >= since)
    ).all()
    if not rows:
        return {}
    px = pd.DataFrame(rows, columns=["sid", "date", "close"])
    px = px.pivot(index="date", columns="sid", values="close").sort_index()
    out: dict[int, float] = {}
    for sid in px.columns:
        returns = px[sid].dropna().pct_change().dropna().tail(window)
        if len(returns) >= min_obs and returns.std() > 0:
            out[int(sid)] = float(returns.std() * (252**0.5))
    return out
