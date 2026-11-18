"""What a market-wide move would do to the book, with options priced again rather than scaled by delta."""

import pytest

from spectre.execution.models import OptionMark
from spectre.models import Price
from spectre.portfolio.positions import value_portfolio
from spectre.risk import ladder as lad
from tests.test_risk_live import END, book  # noqa: F401  (the fixture: 100 shares, two calls, a put, half a coin)


def test_black_scholes_matches_known_values_and_put_call_parity():
    call, put = lad.bs_price("call", 100, 100, 1.0, 0.2, 0.05), lad.bs_price("put", 100, 100, 1.0, 0.2, 0.05)
    assert call == pytest.approx(10.4506, abs=1e-3) and put == pytest.approx(5.5735, abs=1e-3)
    assert call - put == pytest.approx(100 - 100 * 2.718281828 ** -0.05, abs=1e-6)
    # At expiry an option is worth what exercising it gives.
    assert lad.bs_price("call", 110, 100, 0.0, 0.3) == 10 and lad.bs_price("put", 110, 100, 0.0, 0.3) == 0


def test_implied_volatility_recovers_the_volatility_a_price_was_made_with():
    price = lad.bs_price("put", 100, 95, 30 / 365, 0.45)
    assert lad.implied_vol("put", price, 100, 95, 30 / 365) == pytest.approx(0.45, abs=1e-6)
    assert lad.implied_vol("call", 4.0, 110, 100, 30 / 365) is None, "cheaper than exercising it now: no volatility explains that"
    assert lad.implied_vol("call", 99.0, 100, 105, 30 / 365) is None, "dearer than any sane volatility explains"


def test_shares_and_coins_move_one_for_one_and_options_are_priced_again(book):  # noqa: F811
    s, pid, _ = book
    v = value_portfolio(s, pid)
    r = lad.ladder(s, v, today=END)
    by = {round(m["move"], 2): m for m in r["moves"]}
    coin_value = float(v.positions.loc[v.positions["asset_class"] == "Crypto", "market_value"].sum())
    assert by[0.10]["stocks_and_funds"] == pytest.approx(1_000) and by[-0.05]["stocks_and_funds"] == pytest.approx(-500)
    assert by[0.10]["coins"] == pytest.approx(coin_value * 0.10)
    assert r["options_priced"] == 2 and r["option_premium"] == pytest.approx(2 * 500 + 400) and not r["left_out"]
    for m in r["moves"]:
        assert m["total"] == pytest.approx(m["stocks_and_funds"] + m["coins"] + m["options"])
        assert m["options"] >= -r["option_premium"], "bought options cannot lose more than was paid for them"
        assert m["pct"] == pytest.approx(m["total"] / v.total_value)
    # Bought options gain more on a move one way than they lose on the same move the other way.
    assert by[0.10]["options"] + by[-0.10]["options"] > 0 and by[0.05]["options"] + by[-0.05]["options"] > 0
    # Two calls and one put: net long, so the options gain when everything rises.
    assert by[0.10]["options"] > 0 > by[-0.10]["options"]
    # Scaling the calls by delta would have them lose everything in a 10% fall (2 x 100 x 0.5 x 100 x 10% = their
    # whole 1,000 premium); priced properly they keep some value.
    assert by[-0.10]["options"] > -1_000
    assert r["time_decay_per_day"] < 0 < r["per_volatility_point"]


def test_only_the_calls_shows_the_shape_plainly(book):  # noqa: F811
    s, pid, secs = book
    s.execute(Price.__table__.update().where(Price.security_id == secs["put"].id).values(close=0.0))  # the put is worthless
    s.commit()
    r = lad.ladder(s, value_portfolio(s, pid), moves=(-0.10, 0.10), today=END)
    down, up = r["moves"]
    assert up["options"] > -down["options"] > 0, "a call gains faster on the way up than it loses on the way down"
    assert r["left_out"] == [secs["put"].ticker], "a contract with no price is named, not silently dropped"


def test_a_contract_that_cannot_be_priced_falls_back_to_delta_or_is_named(book):  # noqa: F811
    s, pid, secs = book
    # The call's price makes no sense against its stock (dearer than any volatility explains): scale it by delta.
    s.execute(Price.__table__.update().where(Price.security_id == secs["call"].id).values(close=99.0))
    # The put has no stored quote at all.
    s.delete(s.get(OptionMark, secs["put"].id))
    s.commit()
    r = lad.ladder(s, value_portfolio(s, pid), moves=(-0.10, 0.10), today=END)
    assert r["options_by_delta_only"] == [secs["call"].ticker] and r["left_out"] == [secs["put"].ticker]
    leverage = 0.5 * 100 / 99
    assert r["moves"][1]["options"] == pytest.approx(2 * 99 * 100 * leverage * 0.10)
    assert r["time_decay_per_day"] == 0.0


def test_the_api_and_the_daily_report_carry_it(book):  # noqa: F811
    from fastapi.testclient import TestClient

    from spectre.api.app import create_app
    from spectre.portfolio import daily

    s, pid, _ = book
    r = TestClient(create_app(engine=s.get_bind())).get(f"/portfolios/{pid}/risk/moves").json()
    assert [m["move"] for m in r["moves"]] == sorted(lad.MOVES) and r["options_priced"] == 2
    report = daily.daily_report(s, pid, day=END)
    assert report["if_everything_fell_2pct"]["pnl"] < 0 and report["option_time_decay_per_day"] < 0
    text = daily.render(report)
    assert "everything falling 2% together would cost about" in text and "a day to time passing" in text
