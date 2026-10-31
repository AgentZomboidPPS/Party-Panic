from __future__ import annotations

from datetime import date

from fastapi import APIRouter, HTTPException
from sqlalchemy import select

from lantern import audit
from lantern.api.deps import DB
from lantern.models import Benchmark, BenchmarkWeight, CashFlow, Portfolio, Security, Trade
from lantern.portfolio import exposures as ex
from lantern.portfolio.positions import value_portfolio
from lantern.portfolio.whatif import ProposedTrade, apply_trades
from lantern.schemas import (
    BenchmarkIn,
    BenchmarkOut,
    CashFlowIn,
    PortfolioIn,
    PortfolioOut,
    TradeIn,
    TradeOut,
    WhatIfIn,
)

router = APIRouter(tags=["portfolios"])


def _portfolio(db, portfolio_id: int) -> Portfolio:
    pf = db.get(Portfolio, portfolio_id)
    if pf is None:
        raise LookupError(f"Portfolio {portfolio_id} not found")
    return pf


# --- benchmarks


@router.get("/benchmarks", response_model=list[BenchmarkOut])
def list_benchmarks(db: DB):
    return list(db.execute(select(Benchmark).order_by(Benchmark.name)).scalars())


@router.post("/benchmarks", response_model=BenchmarkOut, status_code=201)
def create_benchmark(body: BenchmarkIn, db: DB):
    total = sum(w.weight for w in body.weights)
    if total > 1.0 + 1e-6:
        raise ValueError(f"Benchmark weights sum to {total:.4f}; must be <= 1")
    b = Benchmark(name=body.name)
    db.add(b)
    db.flush()
    for w in body.weights:
        db.add(BenchmarkWeight(benchmark_id=b.id, security_id=w.security_id, weight=w.weight))
    db.commit()
    return b


@router.get("/benchmarks/{benchmark_id}/weights")
def benchmark_weights(benchmark_id: int, db: DB) -> list[dict]:
    if db.get(Benchmark, benchmark_id) is None:
        raise LookupError(f"Benchmark {benchmark_id} not found")
    rows = db.execute(
        select(BenchmarkWeight.security_id, Security.ticker, BenchmarkWeight.weight)
        .join(Security, Security.id == BenchmarkWeight.security_id)
        .where(BenchmarkWeight.benchmark_id == benchmark_id)
        .order_by(BenchmarkWeight.weight.desc())
    ).all()
    return [{"security_id": s, "ticker": t, "weight": w} for s, t, w in rows]


# --- portfolios


@router.get("/portfolios", response_model=list[PortfolioOut])
def list_portfolios(db: DB):
    return list(db.execute(select(Portfolio).order_by(Portfolio.id)).scalars())


@router.post("/portfolios", response_model=PortfolioOut, status_code=201)
def create_portfolio(body: PortfolioIn, db: DB):
    if db.execute(select(Portfolio).where(Portfolio.name == body.name)).scalar_one_or_none():
        raise HTTPException(409, f"Portfolio '{body.name}' already exists")
    pf = Portfolio(**body.model_dump())
    db.add(pf)
    db.flush()
    audit.record(db, actor="api", entity_type="portfolio", entity_id=pf.id, action="created")
    db.commit()
    return pf


@router.get("/portfolios/{portfolio_id}", response_model=PortfolioOut)
def get_portfolio(portfolio_id: int, db: DB):
    return _portfolio(db, portfolio_id)


@router.post("/portfolios/{portfolio_id}/cashflows", status_code=201)
def add_cashflow(portfolio_id: int, body: CashFlowIn, db: DB) -> dict:
    _portfolio(db, portfolio_id)
    cf = CashFlow(portfolio_id=portfolio_id, **body.model_dump())
    db.add(cf)
    db.flush()
    audit.record(db, actor="api", entity_type="cashflow", entity_id=cf.id, action="created",
                 detail={"portfolio_id": portfolio_id, "amount": body.amount})
    db.commit()
    return {"id": cf.id}


@router.get("/portfolios/{portfolio_id}/trades", response_model=list[TradeOut])
def list_trades(portfolio_id: int, db: DB, limit: int = 500):
    _portfolio(db, portfolio_id)
    q = (
        select(Trade)
        .where(Trade.portfolio_id == portfolio_id)
        .order_by(Trade.trade_date.desc(), Trade.id.desc())
        .limit(limit)
    )
    return list(db.execute(q).scalars())


@router.post("/portfolios/{portfolio_id}/trades", response_model=TradeOut, status_code=201)
def book_trade(portfolio_id: int, body: TradeIn, db: DB):
    """Book a historical/externally executed trade straight into the ledger (bypasses the OMS)."""
    _portfolio(db, portfolio_id)
    sec = db.get(Security, body.security_id)
    if sec is None:
        raise LookupError(f"Security {body.security_id} not found")
    t = Trade(
        portfolio_id=portfolio_id,
        security_id=body.security_id,
        side=body.side.value,
        quantity=body.quantity,
        price=body.price,
        currency=body.currency or sec.currency,
        fees=body.fees,
        trade_date=body.trade_date,
    )
    db.add(t)
    db.flush()
    audit.record(db, actor="api", entity_type="trade", entity_id=t.id, action="booked",
                 detail={"portfolio_id": portfolio_id, "ticker": sec.ticker, "side": body.side.value,
                         "quantity": body.quantity, "price": body.price})
    db.commit()
    return t


@router.get("/portfolios/{portfolio_id}/positions")
def positions(portfolio_id: int, db: DB, as_of: date | None = None) -> dict:
    return value_portfolio(db, portfolio_id, as_of).to_dict()


@router.get("/portfolios/{portfolio_id}/exposures")
def exposures(portfolio_id: int, db: DB, dimension: str = "sector", as_of: date | None = None,
              include_cash: bool = True) -> dict:
    valued = value_portfolio(db, portfolio_id, as_of)
    df = ex.exposure_by(valued, dimension, include_cash=include_cash)
    return {
        "portfolio_id": portfolio_id,
        "as_of": valued.as_of.isoformat(),
        "dimension": dimension,
        "total_value": valued.total_value,
        "buckets": df.reset_index().to_dict(orient="records"),
    }


@router.get("/portfolios/{portfolio_id}/active")
def active(portfolio_id: int, db: DB, dimension: str | None = None, as_of: date | None = None) -> dict:
    """Portfolio vs benchmark. Without `dimension`, security-level; with it, bucketed."""
    pf = _portfolio(db, portfolio_id)
    if pf.benchmark_id is None:
        raise ValueError("Portfolio has no benchmark")
    valued = value_portfolio(db, portfolio_id, as_of)
    bench = ex.benchmark_weights(db, pf.benchmark_id)
    if dimension:
        df = ex.active_exposures(db, valued, bench, dimension)
    else:
        df = ex.active_weights(db, valued, bench)
    return {
        "portfolio_id": portfolio_id,
        "benchmark_id": pf.benchmark_id,
        "as_of": valued.as_of.isoformat(),
        "dimension": dimension or "security",
        "rows": df.reset_index().to_dict(orient="records"),
    }


@router.post("/portfolios/{portfolio_id}/whatif")
def whatif(portfolio_id: int, body: WhatIfIn, db: DB) -> dict:
    before = value_portfolio(db, portfolio_id, body.as_of)
    after = apply_trades(
        db, before, [ProposedTrade(t.security_id, t.side, t.quantity, t.price) for t in body.trades]
    )
    return {"before": before.to_dict(), "after": after.to_dict()}
