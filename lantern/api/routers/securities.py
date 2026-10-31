from __future__ import annotations

from datetime import date

from fastapi import APIRouter, HTTPException
from sqlalchemy import select

from lantern.api.deps import DB
from lantern.marketdata.prices import upsert_prices
from lantern.models import FxRate, Price, Security
from lantern.schemas import FxRateIn, PriceOut, PricesBulkIn, SecurityIn, SecurityOut

router = APIRouter(tags=["securities"])


@router.get("/securities", response_model=list[SecurityOut])
def list_securities(db: DB, asset_class: str | None = None):
    q = select(Security).order_by(Security.ticker)
    if asset_class:
        q = q.where(Security.asset_class == asset_class)
    return list(db.execute(q).scalars())


@router.post("/securities", response_model=SecurityOut, status_code=201)
def create_security(body: SecurityIn, db: DB):
    if db.execute(select(Security).where(Security.ticker == body.ticker)).scalar_one_or_none():
        raise HTTPException(409, f"Security {body.ticker} already exists")
    data = body.model_dump()
    data["asset_class"] = body.asset_class.value
    sec = Security(**data)
    db.add(sec)
    db.commit()
    return sec


@router.get("/securities/{security_id}", response_model=SecurityOut)
def get_security(security_id: int, db: DB):
    sec = db.get(Security, security_id)
    if sec is None:
        raise LookupError(f"Security {security_id} not found")
    return sec


@router.get("/securities/{security_id}/prices", response_model=list[PriceOut])
def get_prices(security_id: int, db: DB, start: date | None = None, end: date | None = None, limit: int = 1000):
    q = select(Price).where(Price.security_id == security_id).order_by(Price.date.desc()).limit(limit)
    if start:
        q = q.where(Price.date >= start)
    if end:
        q = q.where(Price.date <= end)
    return list(reversed(list(db.execute(q).scalars())))


@router.post("/prices", status_code=201)
def load_prices(body: PricesBulkIn, db: DB) -> dict:
    n = upsert_prices(db, [p.model_dump() for p in body.prices])
    db.commit()
    return {"loaded": n}


@router.post("/fx", status_code=201)
def load_fx(rates: list[FxRateIn], db: DB) -> dict:
    for r in rates:
        existing = db.execute(
            select(FxRate).where(
                FxRate.base_currency == r.base_currency,
                FxRate.quote_currency == r.quote_currency,
                FxRate.date == r.date,
            )
        ).scalar_one_or_none()
        if existing:
            existing.rate = r.rate
        else:
            db.add(FxRate(**r.model_dump()))
    db.commit()
    return {"loaded": len(rates)}
