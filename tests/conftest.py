from __future__ import annotations

from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from lantern.api.app import create_app
from lantern.db import init_db, make_engine, make_session_factory
from lantern.marketdata.synthetic import seed_demo
from lantern.models import (
    AssetClass,
    CashFlow,
    FxRate,
    Portfolio,
    Price,
    Security,
    Side,
    Trade,
)

D0 = date(2025, 1, 6)
D1 = date(2025, 1, 7)


@pytest.fixture
def engine():
    e = make_engine("sqlite://")
    init_db(e)
    return e


@pytest.fixture
def session(engine):
    with make_session_factory(engine)() as s:
        yield s


@pytest.fixture
def mini(session):
    """Small hand-built book with known numbers (see test_positions for the arithmetic)."""
    aaa = Security(ticker="AAA", name="Alpha Inc", asset_class=AssetClass.EQUITY.value, currency="USD",
                   sector="Technology", country="US", issuer="Alpha Inc")
    eee = Security(ticker="EEE", name="Euro SA", asset_class=AssetClass.EQUITY.value, currency="EUR",
                   sector="Industrials", country="FR", issuer="Euro SA")
    bnd = Security(ticker="BND", name="Alpha 5% 2030", asset_class=AssetClass.FIXED_INCOME.value,
                   currency="USD", sector="Corporate IG", country="US", issuer="Alpha Inc", multiplier=0.01,
                   coupon_rate=0.05, coupon_frequency=2, face_value=100.0,
                   maturity_date=D1 + timedelta(days=int(5 * 365.25)))
    session.add_all([aaa, eee, bnd])
    session.flush()
    session.add_all([
        Price(security_id=aaa.id, date=D0, close=100.0), Price(security_id=aaa.id, date=D1, close=110.0),
        Price(security_id=eee.id, date=D0, close=50.0), Price(security_id=eee.id, date=D1, close=50.0),
        Price(security_id=bnd.id, date=D0, close=98.0), Price(security_id=bnd.id, date=D1, close=99.0),
        FxRate(base_currency="EUR", quote_currency="USD", date=D0, rate=1.10),
        FxRate(base_currency="EUR", quote_currency="USD", date=D1, rate=1.20),
    ])
    pf = Portfolio(name="Mini", base_currency="USD")
    session.add(pf)
    session.flush()
    session.add(CashFlow(portfolio_id=pf.id, date=D0, amount=1_000_000))
    session.add_all([
        Trade(portfolio_id=pf.id, security_id=aaa.id, side=Side.BUY.value, quantity=1000, price=100.0,
              currency="USD", trade_date=D0),
        Trade(portfolio_id=pf.id, security_id=eee.id, side=Side.BUY.value, quantity=2000, price=50.0,
              currency="EUR", trade_date=D0),
        Trade(portfolio_id=pf.id, security_id=bnd.id, side=Side.BUY.value, quantity=200_000, price=98.0,
              currency="USD", trade_date=D0),
    ])
    session.commit()
    return {"session": session, "pf": pf, "aaa": aaa, "eee": eee, "bnd": bnd}


@pytest.fixture(scope="module")
def demo_engine():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        summary = seed_demo(s, start=date(2022, 11, 1), end=date(2025, 10, 31), seed=7)
    e.demo_summary = summary  # type: ignore[attr-defined]
    return e


@pytest.fixture
def demo(demo_engine):
    with make_session_factory(demo_engine)() as s:
        yield s, demo_engine.demo_summary


@pytest.fixture(scope="module")
def client(demo_engine):
    return TestClient(create_app(engine=demo_engine))
