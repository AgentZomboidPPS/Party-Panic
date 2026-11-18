"""What trading costs, measured from fills against the price when the order was decided."""

from datetime import date, datetime, timedelta

import pytest

from spectre.db import init_db, make_engine, make_session_factory
from spectre.models import CashFlow, Order, Portfolio, Price, Security, Side, Trade
from spectre.trading import costs, oms

DAY = date(2026, 11, 18)


@pytest.fixture
def book():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        pf = Portfolio(name="P", base_currency="USD")
        stock = Security(ticker="AAA", name="AAA", asset_class="Equity", currency="USD")
        coin = Security(ticker="BTC", name="Bitcoin", asset_class="Crypto", currency="USD")
        call = Security(ticker="AAA261218C00100000", name="AAA call", asset_class="Option", currency="USD", multiplier=100)
        s.add_all([pf, stock, coin, call])
        s.flush()
        s.add(CashFlow(portfolio_id=pf.id, date=DAY, amount=1_000_000))
        s.add_all([Price(security_id=stock.id, date=DAY, close=100.0), Price(security_id=coin.id, date=DAY, close=50_000.0),
                   Price(security_id=call.id, date=DAY, close=4.0)])
        s.commit()
        yield s, pf.id, stock, coin, call


def trade(s, pid, sec, side, qty, fill, limit=None):
    order = oms.create_order(s, portfolio_id=pid, security_id=sec.id, side=side, quantity=qty, as_of=DAY,
                             **({"order_type": oms.OrderType.LIMIT, "limit_price": limit} if limit else {}))
    assert order.status == "APPROVED", order.reject_reason
    oms.fill_order(s, order.id, qty, fill)
    return order


def test_an_order_remembers_the_market_price_it_was_decided_at_even_with_a_limit(book):
    s, pid, stock, _, call = book
    assert trade(s, pid, stock, Side.BUY, 10, 100.2).arrival_price == 100.0
    assert trade(s, pid, call, Side.BUY, 1, 4.1, limit=4.2).arrival_price == 4.0  # the mid, not the limit


def test_paying_more_or_receiving_less_is_a_cost_and_the_other_way_round_a_gain(book):
    s, pid, stock, _, call = book
    trade(s, pid, stock, Side.BUY, 100, 100.10)   # paid 0.10 too much on 100 shares: 10
    trade(s, pid, stock, Side.SELL, 50, 99.80)    # received 0.20 too little on 50: 10
    trade(s, pid, stock, Side.SELL, 50, 100.04)   # received 0.04 more than decided on 50: -2
    trade(s, pid, call, Side.BUY, 2, 4.10, limit=4.2)  # 0.10 over the mid on 2 contracts of 100: 20
    r = costs.execution_costs(s, pid)
    stocks, options = r["books"]
    assert stocks["book"] == "Stocks and funds" and stocks["orders"] == 3 and stocks["slippage"] == pytest.approx(18.0)
    assert stocks["buys"]["slippage_pct"] == pytest.approx(0.001) and stocks["sells"]["slippage_pct"] == pytest.approx(8 / 10_000)
    assert stocks["round_trip_pct"] == pytest.approx(0.001 + 0.0008) and not stocks["enough"]
    assert options["slippage"] == pytest.approx(20.0) and options["slippage_pct"] == pytest.approx(0.025)
    assert options["round_trip_pct"] == pytest.approx(0.05), "with only buys measured, selling is taken to cost the same"
    assert r["slippage"] == pytest.approx(38.0) and r["worst"][0]["ticker"] == call.ticker
    assert costs.execution_costs(s, pid + 1)["books"] == []


def test_fees_count_towards_the_round_trip_including_coin_fees_booked_without_an_order(book):
    s, pid, _, coin, _ = book
    trade(s, pid, coin, Side.BUY, 0.2, 50_000.0)  # 10,000 moved, filled at the decision price
    # Alpaca keeps a quarter of a percent of the coin: booked as a sale whose proceeds are the fee.
    s.add(Trade(portfolio_id=pid, security_id=coin.id, side="SELL", quantity=0.0005, price=50_000.0, currency="USD", fees=25.0,
                trade_date=DAY))
    s.commit()
    (coins,) = costs.execution_costs(s, pid)["books"]
    assert coins["fees"] == 25.0 and coins["fees_pct"] == pytest.approx(0.0025)
    assert coins["slippage_pct"] == pytest.approx(0.0) and coins["round_trip_pct"] == pytest.approx(0.005)


def test_the_measured_round_trip_replaces_the_estimate_only_once_enough_orders_stand_behind_it(book, monkeypatch):
    s, pid, stock, _, _ = book
    trade(s, pid, stock, Side.BUY, 10, 100.10)
    assert costs.round_trip(s, "Stocks and funds", 0.0005) == (0.0005, False)
    monkeypatch.setattr(costs, "ENOUGH_ORDERS", 1)
    assert costs.round_trip(s, "Stocks and funds", 0.0005) == (pytest.approx(0.002), True)
    assert costs.round_trip(s, "Coins", 0.006) == (0.006, False)
    # A run of lucky fills does not make trading free.
    trade(s, pid, stock, Side.SELL, 10, 101.0)
    assert costs.round_trip(s, "Stocks and funds", 0.0005) == (0.0, True)


def test_older_orders_get_an_arrival_price_from_one_minute_history(book):
    s, pid, stock, coin, call = book
    made = datetime(2026, 11, 18, 15, 30, 20)
    orders = [trade(s, pid, sec, Side.BUY, 1, px) for sec, px in ((stock, 100.3), (coin, 50_100.0), (call, 4.1))]
    for o in orders:
        o.arrival_price, o.created_at = None, made
    s.commit()

    class History:
        def stock_bars(self, symbols, start, timeframe="1Day", adjustment="all"):
            assert timeframe == "1Min" and symbols == ["AAA"]
            # the 15:29 minute closed at 100.25 before the order; the 15:30 minute was still open
            return {"AAA": [(made.replace(second=0) - timedelta(minutes=1), 100.25), (made.replace(second=0), 100.9)]}

        def crypto_bars(self, coins_, start, timeframe="1Day"):
            return {"BTC": [(made.replace(second=0) - timedelta(minutes=30), 50_000.0)]}  # too old to stand for the arrival price

    assert costs.backfill_arrival_prices(s, History(), pid) == {"filled_in": 1, "left": 1}
    stock_order, coin_order, option_order = (s.get(Order, o.id) for o in orders)
    assert stock_order.arrival_price == 100.25 and coin_order.arrival_price is None and option_order.arrival_price is None
    r = costs.execution_costs(s, pid)
    assert {b["book"]: (b["orders"], b["not_measured"]) for b in r["books"]} == {
        "Stocks and funds": (1, 0), "Options": (0, 1), "Coins": (0, 1)}


def test_the_api_serves_costs(book):
    from fastapi.testclient import TestClient

    from spectre.api.app import create_app

    s, pid, stock, _, _ = book
    trade(s, pid, stock, Side.BUY, 100, 100.10)
    r = TestClient(create_app(engine=s.get_bind())).get(f"/portfolios/{pid}/costs").json()
    assert r["orders"] == 1 and r["books"][0]["slippage"] == pytest.approx(10.0) and r["recent"][0]["ticker"] == "AAA"
