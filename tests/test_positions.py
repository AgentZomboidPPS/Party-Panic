import pytest

from lantern.models import Side
from lantern.portfolio import exposures as ex
from lantern.portfolio.positions import value_portfolio
from lantern.portfolio.whatif import ProposedTrade, apply_trades
from tests.conftest import D0, D1

# Mini book, bought on D0:
#   AAA  1,000 sh @ 100 USD                 = 100,000 USD
#   EEE  2,000 sh @ 50 EUR  x 1.10          = 110,000 USD
#   BND  200,000 face @ 98 (per 100)        = 196,000 USD
#   cash = 1,000,000 - 406,000              = 594,000 USD
# Valued on D1: AAA 110 -> 110,000; EEE 50 EUR x 1.20 -> 120,000; BND 99 -> 198,000
#   securities 428,000; total 1,022,000


def test_cash_and_values_on_d1(mini):
    v = value_portfolio(mini["session"], mini["pf"].id, D1)
    assert v.cash == pytest.approx(594_000)
    assert v.securities_value == pytest.approx(428_000)
    assert v.total_value == pytest.approx(1_022_000)
    p = v.positions
    assert p.at[mini["aaa"].id, "market_value"] == pytest.approx(110_000)
    assert p.at[mini["eee"].id, "market_value"] == pytest.approx(120_000)
    assert p.at[mini["bnd"].id, "market_value"] == pytest.approx(198_000)
    assert p.at[mini["aaa"].id, "weight"] == pytest.approx(110_000 / 1_022_000)
    assert p["weight"].sum() + v.cash_weight == pytest.approx(1.0)


def test_valuation_as_of_d0_uses_d0_prices_and_fx(mini):
    v = value_portfolio(mini["session"], mini["pf"].id, D0)
    assert v.securities_value == pytest.approx(406_000)
    assert v.total_value == pytest.approx(1_000_000)


def test_exposures_by_dimension(mini):
    v = value_portfolio(mini["session"], mini["pf"].id, D1)
    by_ac = ex.exposure_by(v, "asset_class")
    assert by_ac.at["Equity", "market_value"] == pytest.approx(230_000)
    assert by_ac.at["Fixed Income", "market_value"] == pytest.approx(198_000)
    assert by_ac.at["Cash", "market_value"] == pytest.approx(594_000)
    assert by_ac["weight"].sum() == pytest.approx(1.0)

    by_ccy = ex.exposure_by(v, "currency")
    assert by_ccy.at["EUR", "weight"] == pytest.approx(120_000 / 1_022_000)
    assert by_ccy.at["USD", "market_value"] == pytest.approx(110_000 + 198_000 + 594_000)

    by_issuer = ex.exposure_by(v, "issuer", include_cash=False)
    assert by_issuer.at["Alpha Inc", "market_value"] == pytest.approx(308_000)


def test_whatif_moves_cash_and_weights_without_touching_ledger(mini):
    s = mini["session"]
    v = value_portfolio(s, mini["pf"].id, D1)
    after = apply_trades(s, v, [ProposedTrade(mini["aaa"].id, Side.BUY, 500)])  # at 110
    assert after.cash == pytest.approx(594_000 - 55_000)
    assert after.positions.at[mini["aaa"].id, "quantity"] == 1500
    assert after.total_value == pytest.approx(v.total_value)  # buying at market is value-neutral
    # Ledger untouched
    again = value_portfolio(s, mini["pf"].id, D1)
    assert again.positions.at[mini["aaa"].id, "quantity"] == 1000


def test_whatif_full_sale_drops_position(mini):
    s = mini["session"]
    v = value_portfolio(s, mini["pf"].id, D1)
    after = apply_trades(s, v, [ProposedTrade(mini["eee"].id, Side.SELL, 2000)])
    assert mini["eee"].id not in after.positions.index
    assert after.cash == pytest.approx(594_000 + 120_000)
