from __future__ import annotations

from fastapi import APIRouter
from sqlalchemy import select

from spectre.api.deps import DB
from spectre.fundamentals.compare import company_report
from spectre.models import Security

router = APIRouter(prefix="/fundamentals", tags=["fundamentals"])


@router.get("/{ticker}")
def report(ticker: str, db: DB) -> dict:
    """Latest reported quarter against the previous quarter and a year ago, plus margins."""
    sec = db.execute(select(Security).where(Security.ticker == ticker.upper())).scalar_one_or_none()
    if sec is None:
        raise LookupError(f"Unknown ticker {ticker}")
    return company_report(db, sec.id, sec.ticker)
