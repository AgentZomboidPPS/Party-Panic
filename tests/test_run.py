"""Running SPECTRE as one always-on service: the password gate, refusing to be public without
one, and picking up an existing broker account on a fresh database."""

from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import select
from typer.testing import CliRunner

from spectre.api.app import create_app
from spectre.cli import app as cli
from spectre.config import settings
from spectre.db import init_db, make_engine, make_session_factory
from spectre.execution import alpaca
from spectre.marketdata.universe import seed_universe
from spectre.models import ComplianceRule, Portfolio, Security, Trade
from spectre.portfolio.positions import value_portfolio
from spectre.portfolio.settlement import simulate
from tests.test_alpaca import FakeAlpaca, client_for
from tests.test_options import FakeOptions


def test_dashboard_and_api_ask_for_the_password_when_one_is_set(engine, monkeypatch):
    web = TestClient(create_app(engine=engine))
    assert web.get("/portfolios").status_code == 200, "no password configured: open, as on your own machine"

    monkeypatch.setattr(settings, "dashboard_password", "correct horse")
    refused = web.get("/portfolios")
    assert refused.status_code == 401 and refused.headers["www-authenticate"].startswith("Basic")
    assert web.get("/").status_code == 401 and web.post("/trading/halt", json={"reason": "x"}).status_code == 401
    assert web.get("/portfolios", auth=("anyone", "wrong")).status_code == 401
    assert web.get("/portfolios", headers={"Authorization": "Basic not-base64!"}).status_code == 401
    assert web.get("/portfolios", auth=("anyone", "correct horse")).status_code == 200
    assert web.get("/", auth=("me", "correct horse")).status_code == 200
    assert web.get("/health").status_code == 200, "the health check stays open so a host can tell the service is alive"


def test_run_refuses_a_public_address_without_a_password(tmp_path):
    result = CliRunner().invoke(cli, ["run", "--host", "0.0.0.0", "--db", f"sqlite:///{tmp_path / 'x.db'}"])
    assert result.exit_code == 1 and "without a password" in result.output


@pytest.fixture
def fresh():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        seed_universe(s)
        pf = Portfolio(name="KAIROS", base_currency="USD")
        s.add(pf)
        s.flush()
        s.add(ComplianceRule(portfolio_id=pf.id, name="No overdraft", rule_type="no_negative_cash", params={}))
        s.commit()
        yield s, pf.id


def test_a_fresh_ledger_starts_from_what_the_broker_already_holds(fresh):
    s, pid = fresh
    fake = FakeOptions()
    fake.cash = "17966.74"
    fake.positions = [
        {"symbol": "NVDA", "asset_class": "us_equity", "qty": "100", "avg_entry_price": "150.25"},
        {"symbol": "NVDA261224C00155000", "asset_class": "us_option", "qty": "5", "avg_entry_price": "5.60"},
        {"symbol": "BTCUSD", "asset_class": "crypto", "qty": "0.00049875", "avg_entry_price": "63155.718"},
        {"symbol": "ZZZZ", "asset_class": "us_equity", "qty": "3", "avg_entry_price": "10"},  # not in the universe
        {"symbol": "TSLA", "asset_class": "us_equity", "qty": "-4", "avg_entry_price": "400"},  # a short: not adopted
    ]
    client = client_for(fake)
    took = alpaca.adopt_account(s, client, pid)
    assert took["adopted"] and took["positions"] == ["NVDA", "NVDA261224C00155000", "BTC", "ZZZZ"] and took["skipped_short"] == ["TSLA"]

    v = value_portfolio(s, pid)
    held = {r.ticker: float(r.quantity) for r in v.positions.itertuples()}
    assert held == {"NVDA": 100, "NVDA261224C00155000": 5, "BTC": pytest.approx(0.00049875), "ZZZZ": 3}
    assert v.cash == pytest.approx(17_966.74), "funded so that the ledger's cash is the broker's cash"
    option = s.execute(select(Security).where(Security.ticker == "NVDA261224C00155000")).scalar_one()
    assert option.asset_class == "Option" and option.multiplier == 100 and option.maturity_date == date(2026, 12, 24)
    assert v.positions.at[option.id, "price"] == pytest.approx(5.0), "marked at the live quote (4.90 / 5.10), not the entry price"
    assert all(t.settle_date == t.trade_date for t in s.execute(select(Trade)).scalars()), "already owned, so already settled"
    state = simulate(s, pid)
    assert state.pending == [] and state.restricted == [] and state.settled_cash == pytest.approx(17_966.74)

    fake.positions = [p for p in fake.positions if p["symbol"] != "TSLA"]
    assert alpaca.reconcile(s, client, pid)["clean"], "ledger and broker now agree"
    assert alpaca.adopt_account(s, client, pid) == {"adopted": False, "reason": "the ledger already has history"}


def test_an_empty_broker_account_is_adopted_as_cash(fresh):
    s, pid = fresh
    fake = FakeAlpaca()
    assert alpaca.adopt_account(s, client_for(fake), pid)["positions"] == []
    assert value_portfolio(s, pid).cash == 100_000


# --------------------------------------------------------------------------- rebuilding the books from the broker


def _fill(i, when, symbol, side, qty, price, order):
    return {"id": f"{i:04d}::x", "activity_type": "FILL", "transaction_time": when, "symbol": symbol, "side": side,
            "qty": str(qty), "price": str(price), "order_id": order}


def _history(fake):
    """What Alpaca would have on record: a buy filled in two pieces, a sale, an option, a coin, a fee."""
    fake.activities = [
        _fill(1, "2026-11-17T15:00:00.618165Z", "NVDA", "buy", 60, 150.00, "o1"),
        _fill(2, "2026-11-17T15:00:01.100000Z", "NVDA", "buy", 40, 150.50, "o1"),
        _fill(3, "2026-11-18T15:10:00Z", "NVDA", "sell", 30, 160.00, "o2"),
        _fill(4, "2026-11-18T15:20:00Z", "NVDA261224C00155000", "buy", 5, 5.60, "o3"),
        _fill(5, "2026-11-18T15:30:00Z", "BTC/USD", "buy", 0.05, 63000.0, "o4"),
        {"id": "0006::x", "activity_type": "FEE", "date": "2026-11-18", "net_amount": "-0.14", "description": "REG fee"},
    ]
    spent = 60 * 150 + 40 * 150.5 - 30 * 160 + 5 * 5.6 * 100 + 0.05 * 63000 + 0.14
    fake.cash = str(100_000 - spent - 0.08)  # ... and eight cents more of fees that have not been itemised yet
    fake.positions = [
        {"symbol": "NVDA", "asset_class": "us_equity", "qty": "70", "avg_entry_price": "150.2", "current_price": "161"},
        {"symbol": "NVDA261224C00155000", "asset_class": "us_option", "qty": "5", "avg_entry_price": "5.6", "current_price": "5.4"},
        {"symbol": "BTCUSD", "asset_class": "crypto", "qty": "0.049875", "avg_entry_price": "63000", "current_price": "63100"},
    ]
    return spent


def test_an_empty_ledger_is_rebuilt_from_the_brokers_record_of_every_fill(fresh):
    from spectre.models import CashFlow, Order
    from spectre.portfolio.performance import performance
    from spectre.portfolio.positions import average_costs

    s, pid = fresh
    fake = FakeOptions()
    spent = _history(fake)
    client = client_for(fake)
    assert client.activities(page_size=2) == fake.activities, "read page by page, oldest first"

    out = alpaca.rebuild_ledger(s, client, pid)
    assert out["rebuilt"] and out["fills"] == 5 and out["orders"] == 4 and out["clean"] and out["not_understood"] == []
    assert out["opening_balance"] == 100_000, "the round sum it was opened with; the odd cents are fees"

    v = value_portfolio(s, pid)
    held = {r.ticker: float(r.quantity) for r in v.positions.itertuples()}
    assert held == {"NVDA": 70, "NVDA261224C00155000": 5, "BTC": pytest.approx(0.049875)}, "the coin is net of its fee"
    assert v.cash == pytest.approx(100_000 - spent - 0.08), "to the cent"
    nvda = s.execute(select(Security).where(Security.ticker == "NVDA")).scalar_one()
    assert average_costs(s, pid)[nvda.id] == pytest.approx(150.20), "60 at 150.00 and 40 at 150.50"
    first = s.execute(select(Order).order_by(Order.id)).scalars().first()
    assert first.quantity == 100 and first.avg_fill_price == pytest.approx(150.20) and first.created_by == "alpaca-import"
    assert len(first.fills) == 2 and first.status == "FILLED"
    dates = {t.security.ticker: (t.trade_date, t.settle_date) for t in s.execute(select(Trade).where(Trade.order_id.is_not(None))).scalars()}
    assert dates["NVDA261224C00155000"] == (date(2026, 11, 18), date(2026, 11, 19)) and dates["BTC"] == (date(2026, 11, 18),) * 2
    fees = sorted(c.amount for c in s.execute(select(CashFlow).where(CashFlow.kind != "EXTERNAL")).scalars())
    assert fees == pytest.approx([-0.14, -0.08]), "the itemised fee, and the rest found by reconciliation"

    r = performance(s, pid)
    stocks = next(x for x in r["sleeves"] if x["sleeve"] == "Stocks and funds")
    assert r["put_in"] == 100_000 and stocks["realised"] == pytest.approx(30 * (160 - 150.20)) and stocks["closed_trades"] == 1
    assert r["since"] == "2026-11-17T15:00:00", "the record starts at the first fill"
    assert alpaca.rebuild_ledger(s, client, pid) == {"rebuilt": False, "reason": "the ledger already has history"}


def test_a_record_that_does_not_add_up_writes_nothing_and_the_positions_are_used_instead(fresh):
    s, pid = fresh
    fake = FakeOptions()
    _history(fake)
    fake.activities = fake.activities[2:]  # the broker no longer serves the two oldest fills
    out = alpaca.rebuild_ledger(s, client_for(fake), pid)
    assert not out["rebuilt"] and "do not add up" in out["reason"] and "NVDA" in out["reason"]
    assert s.execute(select(Trade)).first() is None, "nothing half-written"
    assert alpaca.adopt_account(s, client_for(fake), pid)["adopted"]
    assert {r.ticker for r in value_portfolio(s, pid).positions.itertuples()} == {"NVDA", "NVDA261224C00155000", "BTC"}


def test_keys_supplied_by_the_environment_are_detected():
    import httpx

    def needs_basic(request):
        ok = request.headers.get("authorization", "").startswith("Basic ")
        return httpx.Response(200 if ok else 401, json={"status": "ACTIVE"} if ok else {"message": "unauthorized"})

    def injecting(request):  # what a hosting environment's saved secret does to every request
        request.headers["authorization"] = "Basic a2V5OnNlY3JldA=="
        return needs_basic(request)

    bare = dict(key_id="", secret_key="")
    assert not alpaca.AlpacaClient(**bare, transport=httpx.MockTransport(needs_basic)).authorised()
    assert alpaca.AlpacaClient(**bare, transport=httpx.MockTransport(injecting)).authorised()


def test_the_daily_brake_is_read_at_the_brokers_current_prices(fresh, monkeypatch):
    """The brake compares the account with a record kept at the broker's valuation, so the
    holdings are valued at the broker's prices before it is read: calls that have fallen since
    the last cycle count in this cycle, not the next one."""
    from datetime import timedelta

    from spectre import cli as commands
    from spectre.portfolio.performance import record_snapshot
    from spectre.signals.sources.base import utcnow

    s, pid = fresh
    fake = FakeOptions()
    fake.cash = "90000.00"
    fake.positions = [{"symbol": "NVDA261224C00155000", "asset_class": "us_option", "qty": "20", "avg_entry_price": "5.00",
                       "current_price": "5.00"}]
    client = client_for(fake)
    alpaca.adopt_account(s, client, pid)  # 90,000 in cash and twenty calls at 5.00: 100,000
    record_snapshot(s, pid, at=utcnow() - timedelta(days=1))
    assert value_portfolio(s, pid).total_value == pytest.approx(100_000)

    fake.positions[0]["current_price"] = "3.00"  # the calls have lost 4,000 since the last look
    monkeypatch.setattr(commands, "_broker", lambda name, session=None: alpaca.AlpacaPaperBroker(client))
    _, _, actions, notes = commands._kairos_cycle(s, pid, "alpaca", top_n=5, invest=0.9, enter=1.0, exit_below=0.0,
                                                  lookback=60, min_authors=4)
    assert actions == []
    assert any(n.startswith("Buying is paused: the account is 4.0% down today") for n in notes), notes
    assert value_portfolio(s, pid).total_value == pytest.approx(96_000)
