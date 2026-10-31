import numpy as np
import pandas as pd
import pytest
from scipy.stats import norm

from lantern.risk import factors as fm
from lantern.risk import fixed_income as fi
from lantern.risk.stress import Scenario, apply_scenario
from lantern.risk.var import (
    component_var,
    historical_var,
    monte_carlo_var,
    parametric_var,
    portfolio_return_series,
)

# ---------------------------------------------------------------- VaR


@pytest.fixture
def two_asset():
    cov = pd.DataFrame([[0.0004, 0.0001], [0.0001, 0.0009]], index=[1, 2], columns=[1, 2])
    w = pd.Series({1: 0.6, 2: 0.3})  # 10% cash
    return w, cov


def test_parametric_var_matches_closed_form(two_asset):
    w, cov = two_asset
    r = parametric_var(w, cov, 1_000_000, 0.99, 1)
    sigma = np.sqrt(w.to_numpy() @ cov.to_numpy() @ w.to_numpy())
    assert r.var == pytest.approx(norm.ppf(0.99) * sigma * 1_000_000)
    assert r.expected_shortfall > r.var


def test_horizon_scaling_is_sqrt_time(two_asset):
    w, cov = two_asset
    one = parametric_var(w, cov, 1e6, 0.99, 1).var
    ten = parametric_var(w, cov, 1e6, 0.99, 10).var
    assert ten == pytest.approx(one * np.sqrt(10))


def test_component_var_sums_to_total(two_asset):
    w, cov = two_asset
    total = parametric_var(w, cov, 1e6, 0.99, 1).var
    comp = component_var(w, cov, 1e6, 0.99, 1)
    assert comp["component_var"].sum() == pytest.approx(total)
    assert comp["pct_of_total"].sum() == pytest.approx(1.0)


def test_monte_carlo_converges_to_parametric(two_asset):
    w, cov = two_asset
    para = parametric_var(w, cov, 1e6, 0.99, 1).var
    mc = monte_carlo_var(w, cov, 1e6, 0.99, 1, n_sims=400_000, seed=1).var
    assert mc == pytest.approx(para, rel=0.03)


def test_historical_var_on_known_series():
    # 1000 daily returns, 15 of them at -5%; the 99th percentile loss sits inside that block.
    rets = np.full(1000, 0.001)
    rets[:15] = -0.05
    r = historical_var(pd.Series(rets), 1_000_000, 0.99, 1)
    assert r.var == pytest.approx(50_000, rel=0.05)
    assert r.expected_shortfall >= r.var


def test_portfolio_return_series_ignores_cash_and_aligns():
    rets = pd.DataFrame({1: [0.01, -0.02], 2: [0.02, 0.01]})
    w = pd.Series({2: 0.5, 1: 0.25})  # unordered on purpose, 25% cash
    p = portfolio_return_series(rets, w)
    assert p.iloc[0] == pytest.approx(0.25 * 0.01 + 0.5 * 0.02)


# ---------------------------------------------------------------- fixed income


def test_bond_prices_at_par_when_yield_equals_coupon():
    assert fi.bond_price(100, 0.05, 0.05, 5, 2) == pytest.approx(100.0, abs=1e-9)
    assert fi.bond_price(100, 0.05, 0.06, 5, 2) < 100.0
    assert fi.bond_price(100, 0.05, 0.04, 5, 2) > 100.0


def test_ytm_round_trips():
    px = fi.bond_price(100, 0.04, 0.0375, 7.3, 2)
    assert fi.bond_ytm(px, 100, 0.04, 7.3, 2) == pytest.approx(0.0375, abs=1e-8)


def test_zero_coupon_duration_equals_maturity():
    assert fi.macaulay_duration(100, 0.0, 0.05, 6.0, 2) == pytest.approx(6.0)
    assert fi.modified_duration(100, 0.0, 0.05, 6.0, 2) == pytest.approx(6.0 / 1.025)


def test_modified_duration_predicts_small_price_moves():
    y, dy = 0.05, 0.0001
    p0 = fi.bond_price(100, 0.05, y, 10, 2)
    p1 = fi.bond_price(100, 0.05, y + dy, 10, 2)
    d = fi.modified_duration(100, 0.05, y, 10, 2)
    assert (p1 - p0) / p0 == pytest.approx(-d * dy, rel=1e-2)


# ---------------------------------------------------------------- factor model


def test_factor_model_recovers_known_betas():
    rng = np.random.default_rng(0)
    T = 1500
    F = pd.DataFrame({"MKT": rng.normal(0, 0.01, T), "RATES": rng.normal(0, 0.0005, T)})
    true_b = pd.DataFrame({"MKT": [1.2, 0.0], "RATES": [0.0, -7.0]}, index=["eq", "bond"])
    Y = pd.DataFrame(
        {
            "eq": 1.2 * F["MKT"] + rng.normal(0, 0.01, T),
            "bond": -7.0 * F["RATES"] + rng.normal(0, 0.0005, T),
        }
    )
    model = fm.estimate(Y, F)
    assert model.betas.loc["eq", "MKT"] == pytest.approx(1.2, abs=0.1)
    assert model.betas.loc["bond", "RATES"] == pytest.approx(-7.0, abs=0.5)
    assert abs(model.betas.loc["eq", "RATES"]) < 1.0
    assert (model.r_squared > 0.4).all()
    _ = true_b  # documents the generating betas

    w = pd.Series({"eq": 0.6, "bond": 0.4})
    d = fm.decompose(w, model)
    assert d.total_vol**2 == pytest.approx(d.systematic_vol**2 + d.idiosyncratic_vol**2, rel=1e-9)
    assert d.factor_exposures["MKT"] == pytest.approx(0.72, abs=0.07)
    assert 0 < d.to_dict()["systematic_share"] < 1


# ---------------------------------------------------------------- stress


def test_stress_shocks_are_additive_and_rates_use_duration(mini):
    from lantern.portfolio.positions import value_portfolio
    from tests.conftest import D1

    v = value_portfolio(mini["session"], mini["pf"].id, D1)
    scen = Scenario("x", "", {"asset_class": {"Equity": -0.10}, "sector": {"Technology": -0.05}}, rates_bp=100)
    durs = pd.Series({mini["bnd"].id: 4.0})
    res = apply_scenario(v, scen, durs)
    expected = 110_000 * -0.15 + 120_000 * -0.10 + 198_000 * (-4.0 * 0.01)
    assert res.pnl == pytest.approx(expected)
    assert res.by_security.at[mini["aaa"].id, "shock"] == pytest.approx(-0.15)


def test_currency_shock_skips_base_currency(mini):
    from lantern.portfolio.positions import value_portfolio
    from tests.conftest import D1

    v = value_portfolio(mini["session"], mini["pf"].id, D1)
    res = apply_scenario(v, Scenario("usd", "", {"currency": {"EUR": -0.10, "USD": -0.50}}))
    assert res.pnl == pytest.approx(120_000 * -0.10)
