"""Linear factor model: estimate betas by OLS, aggregate to portfolio exposures, decompose risk."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

import numpy as np
import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from lantern.models import FactorReturn


def factor_returns(
    session: Session, start: date, end: date, factors: list[str] | None = None
) -> pd.DataFrame:
    q = select(FactorReturn.factor, FactorReturn.date, FactorReturn.value).where(
        FactorReturn.date >= start, FactorReturn.date <= end
    )
    if factors:
        q = q.where(FactorReturn.factor.in_(factors))
    rows = session.execute(q).all()
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows, columns=["factor", "date", "value"])
    df["date"] = pd.to_datetime(df["date"])
    return df.pivot(index="date", columns="factor", values="value").sort_index()


@dataclass
class FactorModel:
    betas: pd.DataFrame  # assets x factors
    alphas: pd.Series
    resid_var: pd.Series  # daily idiosyncratic variance per asset
    r_squared: pd.Series
    factor_cov: pd.DataFrame  # daily factor covariance


def estimate(asset_returns: pd.DataFrame, factor_rets: pd.DataFrame) -> FactorModel:
    """OLS of each asset's returns on the factors (with intercept), over their common dates."""
    idx = asset_returns.index.intersection(factor_rets.index)
    if len(idx) < len(factor_rets.columns) + 2:
        raise ValueError("Not enough overlapping observations to estimate the factor model")
    Y = asset_returns.loc[idx].to_numpy(dtype=float)
    F = factor_rets.loc[idx].to_numpy(dtype=float)
    X = np.column_stack([np.ones(len(idx)), F])
    coef, *_ = np.linalg.lstsq(X, Y, rcond=None)  # (K+1) x N
    resid = Y - X @ coef
    dof = max(len(idx) - X.shape[1], 1)
    resid_var = (resid**2).sum(axis=0) / dof
    tss = ((Y - Y.mean(axis=0)) ** 2).sum(axis=0)
    r2 = np.where(tss > 0, 1.0 - (resid**2).sum(axis=0) / np.where(tss > 0, tss, 1.0), 0.0)

    assets = asset_returns.columns
    return FactorModel(
        betas=pd.DataFrame(coef[1:].T, index=assets, columns=factor_rets.columns),
        alphas=pd.Series(coef[0], index=assets),
        resid_var=pd.Series(resid_var, index=assets),
        r_squared=pd.Series(r2, index=assets),
        factor_cov=factor_rets.loc[idx].cov(),
    )


def portfolio_exposures(weights: pd.Series, model: FactorModel) -> pd.Series:
    w = weights.reindex(model.betas.index).fillna(0.0)
    return model.betas.mul(w, axis=0).sum(axis=0)


@dataclass
class RiskDecomposition:
    total_vol: float  # annualised
    systematic_vol: float
    idiosyncratic_vol: float
    factor_exposures: pd.Series
    factor_contribution: pd.Series  # share of total variance per factor

    def to_dict(self) -> dict:
        return {
            "total_vol": self.total_vol,
            "systematic_vol": self.systematic_vol,
            "idiosyncratic_vol": self.idiosyncratic_vol,
            "systematic_share": (self.systematic_vol**2 / self.total_vol**2) if self.total_vol else 0.0,
            "factor_exposures": self.factor_exposures.to_dict(),
            "factor_contribution": self.factor_contribution.to_dict(),
        }


def decompose(weights: pd.Series, model: FactorModel, periods_per_year: int = 252) -> RiskDecomposition:
    w = weights.reindex(model.betas.index).fillna(0.0).to_numpy(dtype=float)
    B = model.betas.to_numpy(dtype=float)
    F = model.factor_cov.to_numpy(dtype=float)
    b = B.T @ w  # portfolio factor exposures
    sys_var = float(b @ F @ b)
    idio_var = float((w**2 * model.resid_var.to_numpy(dtype=float)).sum())
    total_var = sys_var + idio_var
    # Marginal contribution of each factor to systematic variance (Euler), as share of total.
    contrib = (b * (F @ b)) / total_var if total_var > 0 else np.zeros_like(b)
    ann = np.sqrt(periods_per_year)
    return RiskDecomposition(
        total_vol=float(np.sqrt(total_var)) * ann,
        systematic_vol=float(np.sqrt(sys_var)) * ann,
        idiosyncratic_vol=float(np.sqrt(idio_var)) * ann,
        factor_exposures=pd.Series(b, index=model.betas.columns),
        factor_contribution=pd.Series(contrib, index=model.betas.columns),
    )
