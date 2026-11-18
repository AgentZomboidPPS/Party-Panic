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
    assert v.positions.at[option.id, "price"] == pytest.approx(5.5), "marked at the live quote, not the entry price"
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
