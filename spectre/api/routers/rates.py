from __future__ import annotations

from fastapi import APIRouter

from spectre.api.deps import DB
from spectre.rates import analytics

router = APIRouter(prefix="/rates", tags=["rates"])


@router.get("/curve")
def curve(db: DB) -> dict:
    """The latest Treasury yield curve with changes, slopes and an inversion flag."""
    c = analytics.latest_curve(db)
    return c or {"date": None, "points": []}


@router.get("/history/{tenor}")
def history(tenor: str, db: DB, limit: int = 260) -> list[dict]:
    return analytics.history(db, tenor, limit)


@router.get("/macro")
def macro(db: DB) -> list[dict]:
    """Latest value of each stored macro series (credit spreads, policy rate, ...)."""
    return analytics.latest_macro(db)
