"""Exposure aggregation by any attribute, and active exposure versus a benchmark."""

from __future__ import annotations

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.models import BenchmarkWeight, Security
from lantern.portfolio.positions import ValuedPositions, security_map

DIMENSIONS = ("asset_class", "sector", "country", "currency", "issuer")


def _cash_bucket(dimension: str, base_currency: str) -> str:
    return base_currency if dimension == "currency" else "Cash"


def exposure_by(valued: ValuedPositions, dimension: str, include_cash: bool = True) -> pd.DataFrame:
    """Market value and weight per bucket of `dimension`, largest first."""
    if dimension not in DIMENSIONS:
        raise ValueError(f"dimension must be one of {DIMENSIONS}")
    df = valued.positions
    if len(df):
        mv = df.groupby(dimension)["market_value"].sum().astype(float)
    else:
        mv = pd.Series(dtype=float)
    if include_cash:
        bucket = _cash_bucket(dimension, valued.base_currency)
        mv[bucket] = mv.get(bucket, 0.0) + valued.cash
    total = valued.total_value
    out = pd.DataFrame({"market_value": mv})
    out["weight"] = out["market_value"] / total if total else 0.0
    out.index.name = dimension
    return out.sort_values("market_value", ascending=False)


def benchmark_weights(session: Session, benchmark_id: int) -> pd.Series:
    rows = session.execute(
        select(BenchmarkWeight.security_id, BenchmarkWeight.weight).where(
            BenchmarkWeight.benchmark_id == benchmark_id
        )
    ).all()
    return pd.Series({sid: float(w) for sid, w in rows}, dtype=float)


def active_weights(session: Session, valued: ValuedPositions, bench: pd.Series) -> pd.DataFrame:
    """Security-level portfolio vs benchmark weights. Cash is shown as its own row."""
    port = valued.weights()
    ids = sorted(set(port.index) | set(bench.index))
    secs = security_map(session, ids)
    out = pd.DataFrame(
        {
            "ticker": [secs[i].ticker for i in ids],
            "name": [secs[i].name for i in ids],
            "asset_class": [secs[i].asset_class for i in ids],
            "sector": [secs[i].sector or "Unclassified" for i in ids],
            "portfolio_weight": port.reindex(ids).fillna(0.0).to_numpy(),
            "benchmark_weight": bench.reindex(ids).fillna(0.0).to_numpy(),
        },
        index=pd.Index(ids, name="security_id"),
    )
    out["active_weight"] = out["portfolio_weight"] - out["benchmark_weight"]
    return out.sort_values("active_weight", key=abs, ascending=False)


def active_exposures(
    session: Session, valued: ValuedPositions, bench: pd.Series, dimension: str
) -> pd.DataFrame:
    """Bucketed portfolio vs benchmark weights. Portfolio cash counts against the cash bucket."""
    if dimension not in DIMENSIONS:
        raise ValueError(f"dimension must be one of {DIMENSIONS}")
    port = exposure_by(valued, dimension, include_cash=True)["weight"]

    secs = security_map(session, bench.index)
    attrs = {
        sid: (
            getattr(secs[sid], dimension) or "Unclassified"
            if dimension not in ("currency", "asset_class")
            else getattr(secs[sid], dimension)
        )
        for sid in bench.index
    }
    bench_buckets = pd.Series(
        {sid: attrs[sid] for sid in bench.index}, dtype=object
    )
    bench_w = bench.groupby(bench_buckets).sum() if len(bench) else pd.Series(dtype=float)
    bench_w = bench_w.astype(float)
    # Benchmark cash = anything not allocated to securities (so weights can sum to < 1).
    bench_cash = 1.0 - float(bench.sum())
    if bench_cash > 1e-9:
        bucket = _cash_bucket(dimension, valued.base_currency)
        bench_w[bucket] = bench_w.get(bucket, 0.0) + bench_cash

    buckets = sorted(set(port.index) | set(bench_w.index))
    out = pd.DataFrame(
        {
            "portfolio_weight": port.reindex(buckets).fillna(0.0).to_numpy(),
            "benchmark_weight": bench_w.reindex(buckets).fillna(0.0).to_numpy(),
        },
        index=pd.Index(buckets, name=dimension),
    )
    out["active_weight"] = out["portfolio_weight"] - out["benchmark_weight"]
    return out.sort_values("active_weight", key=abs, ascending=False)


def securities_in(session: Session, tickers: list[str]) -> dict[str, Security]:
    rows = session.execute(select(Security).where(Security.ticker.in_(tickers))).scalars()
    return {s.ticker: s for s in rows}
