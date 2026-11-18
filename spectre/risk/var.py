"""Value at Risk and Expected Shortfall: historical, parametric (variance-covariance), Monte Carlo.

Conventions
- `weights` are market-value weights relative to total portfolio value (cash has zero return).
- Returns are daily simple returns in base currency.
- Horizon scaling uses the square-root-of-time rule with zero drift.
- VaR and ES are reported as positive currency losses.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

import numpy as np
import pandas as pd
from scipy.stats import norm


@dataclass
class VarResult:
    method: str
    confidence: float
    horizon_days: int
    portfolio_value: float
    var: float
    expected_shortfall: float
    observations: int | None = None

    @property
    def var_pct(self) -> float:
        return self.var / self.portfolio_value if self.portfolio_value else 0.0

    @property
    def es_pct(self) -> float:
        return self.expected_shortfall / self.portfolio_value if self.portfolio_value else 0.0

    def to_dict(self) -> dict:
        d = asdict(self)
        d["var_pct"] = self.var_pct
        d["es_pct"] = self.es_pct
        return d


def portfolio_return_series(returns: pd.DataFrame, weights: pd.Series) -> pd.Series:
    """Daily portfolio returns from an asset return matrix and a weight vector."""
    w = weights.reindex(returns.columns).fillna(0.0).to_numpy(dtype=float)
    return pd.Series(returns.to_numpy(dtype=float) @ w, index=returns.index, name="portfolio")


def _align(weights: pd.Series, cov: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    w = weights.reindex(cov.index).fillna(0.0).to_numpy(dtype=float)
    return w, cov.to_numpy(dtype=float)


def historical_var(
    port_returns: pd.Series, portfolio_value: float, confidence: float = 0.99, horizon_days: int = 1
) -> VarResult:
    losses = -port_returns.to_numpy(dtype=float)
    if losses.size == 0:
        return VarResult("historical", confidence, horizon_days, portfolio_value, 0.0, 0.0, 0)
    q = float(np.quantile(losses, confidence))
    tail = losses[losses >= q]
    es = float(tail.mean()) if tail.size else q
    scale = np.sqrt(horizon_days)
    return VarResult(
        "historical",
        confidence,
        horizon_days,
        portfolio_value,
        max(q, 0.0) * scale * portfolio_value,
        max(es, 0.0) * scale * portfolio_value,
        int(losses.size),
    )


def parametric_var(
    weights: pd.Series,
    cov: pd.DataFrame,
    portfolio_value: float,
    confidence: float = 0.99,
    horizon_days: int = 1,
) -> VarResult:
    w, S = _align(weights, cov)
    sigma = float(np.sqrt(max(w @ S @ w, 0.0)))
    z = norm.ppf(confidence)
    es_mult = norm.pdf(z) / (1.0 - confidence)
    scale = np.sqrt(horizon_days)
    return VarResult(
        "parametric",
        confidence,
        horizon_days,
        portfolio_value,
        z * sigma * scale * portfolio_value,
        es_mult * sigma * scale * portfolio_value,
    )


def monte_carlo_var(
    weights: pd.Series,
    cov: pd.DataFrame,
    portfolio_value: float,
    confidence: float = 0.99,
    horizon_days: int = 1,
    n_sims: int = 20_000,
    seed: int = 42,
) -> VarResult:
    w, S = _align(weights, cov)
    n = S.shape[0]
    if n == 0:
        return VarResult("monte_carlo", confidence, horizon_days, portfolio_value, 0.0, 0.0, 0)
    jitter = 1e-12 * np.eye(n)
    try:
        L = np.linalg.cholesky(S + jitter)
    except np.linalg.LinAlgError:
        vals, vecs = np.linalg.eigh(S)
        L = vecs @ np.diag(np.sqrt(np.clip(vals, 0.0, None)))
    rng = np.random.default_rng(seed)
    sims = rng.standard_normal((n_sims, n)) @ L.T
    losses = -(sims @ w) * np.sqrt(horizon_days)
    q = float(np.quantile(losses, confidence))
    tail = losses[losses >= q]
    es = float(tail.mean()) if tail.size else q
    return VarResult(
        "monte_carlo",
        confidence,
        horizon_days,
        portfolio_value,
        max(q, 0.0) * portfolio_value,
        max(es, 0.0) * portfolio_value,
        n_sims,
    )


def component_var(
    weights: pd.Series,
    cov: pd.DataFrame,
    portfolio_value: float,
    confidence: float = 0.99,
    horizon_days: int = 1,
) -> pd.DataFrame:
    """Euler decomposition of parametric VaR. Components sum to the portfolio VaR."""
    w, S = _align(weights, cov)
    sigma = float(np.sqrt(max(w @ S @ w, 0.0)))
    z = norm.ppf(confidence) * np.sqrt(horizon_days)
    if sigma == 0.0:
        marginal = np.zeros_like(w)
    else:
        marginal = (S @ w) / sigma
    comp = w * marginal * z * portfolio_value
    total = comp.sum()
    out = pd.DataFrame(
        {
            "weight": w,
            "marginal_var": marginal * z * portfolio_value,
            "component_var": comp,
            "pct_of_total": comp / total if total else 0.0,
        },
        index=cov.index,
    )
    out.index.name = "security_id"
    return out.sort_values("component_var", ascending=False)
