"""Scenario analysis: instantaneous shocks applied to current positions."""

from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd

from lantern.portfolio.positions import ValuedPositions

SHOCK_DIMENSIONS = ("asset_class", "sector", "country", "currency", "ticker")


@dataclass
class Scenario:
    name: str
    description: str = ""
    # dimension -> bucket -> return shock (e.g. {"asset_class": {"Equity": -0.20}})
    shocks: dict[str, dict[str, float]] = field(default_factory=dict)
    # Parallel yield shift in basis points, applied to fixed income via modified duration.
    rates_bp: float = 0.0

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "description": self.description,
            "shocks": self.shocks,
            "rates_bp": self.rates_bp,
        }


@dataclass
class StressResult:
    scenario: str
    portfolio_value: float
    pnl: float
    by_security: pd.DataFrame  # ticker, market_value, shock, pnl

    @property
    def pnl_pct(self) -> float:
        return self.pnl / self.portfolio_value if self.portfolio_value else 0.0

    def to_dict(self, top: int | None = None) -> dict:
        rows = self.by_security.sort_values("pnl")
        if top:
            rows = rows.head(top)
        return {
            "scenario": self.scenario,
            "portfolio_value": self.portfolio_value,
            "pnl": self.pnl,
            "pnl_pct": self.pnl_pct,
            "by_security": rows.reset_index().to_dict(orient="records"),
        }


PREDEFINED: list[Scenario] = [
    Scenario("Equity -10%", "Broad equity drawdown", {"asset_class": {"Equity": -0.10, "Fund": -0.06}}),
    Scenario(
        "2008-style crisis",
        "Equities -35%, financials an extra -20%, HY credit -15%, flight to Treasuries (-150bp)",
        {
            "asset_class": {"Equity": -0.35, "Fund": -0.25},
            "sector": {"Financials": -0.20, "Corporate HY": -0.15, "Corporate IG": -0.05},
        },
        rates_bp=-150,
    ),
    Scenario("Rates +100bp", "Parallel shift up in yields", rates_bp=100),
    Scenario("Rates -100bp", "Parallel shift down in yields", rates_bp=-100),
    Scenario(
        "Tech selloff -20%",
        "Technology sector drawdown with mild market contagion",
        {"sector": {"Technology": -0.20}, "asset_class": {"Equity": -0.03}},
    ),
    Scenario(
        "USD +10%",
        "Dollar strengthens 10% against all currencies",
        {"currency": {"EUR": -0.10, "GBP": -0.10, "JPY": -0.10, "CHF": -0.10}},
    ),
    Scenario(
        "Stagflation",
        "Rates +200bp, equities -15%, energy +10%",
        {"asset_class": {"Equity": -0.15}, "sector": {"Energy": 0.25}},
        rates_bp=200,
    ),
]


def apply_scenario(
    valued: ValuedPositions, scenario: Scenario, durations: pd.Series | None = None
) -> StressResult:
    """Shock each position. Shocks across dimensions are additive. Rate shocks use -D_mod * dy."""
    df = valued.positions
    if len(df) == 0:
        empty = pd.DataFrame(columns=["ticker", "market_value", "shock", "pnl"])
        return StressResult(scenario.name, valued.total_value, 0.0, empty)

    shock = pd.Series(0.0, index=df.index)
    for dim, buckets in scenario.shocks.items():
        if dim not in SHOCK_DIMENSIONS:
            raise ValueError(f"Unknown shock dimension {dim!r}; expected one of {SHOCK_DIMENSIONS}")
        if dim == "currency":
            # A currency shock only hits positions not already in base currency.
            col = df[dim].where(df[dim] != valued.base_currency, other="__base__")
        else:
            col = df[dim]
        shock = shock + col.map(buckets).fillna(0.0).astype(float)

    if scenario.rates_bp and durations is not None and len(durations):
        dy = scenario.rates_bp / 10_000.0
        shock = shock + (-durations.reindex(df.index).fillna(0.0) * dy)

    pnl = df["market_value"] * shock
    out = pd.DataFrame(
        {"ticker": df["ticker"], "market_value": df["market_value"], "shock": shock, "pnl": pnl}
    )
    out.index.name = "security_id"
    return StressResult(scenario.name, valued.total_value, float(pnl.sum()), out)
