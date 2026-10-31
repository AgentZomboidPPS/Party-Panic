"""End-to-end on the seeded demo universe, through the library and the REST API."""

from datetime import date, timedelta

import pytest

from lantern.marketdata.synthetic import UNIVERSE
from lantern.portfolio.positions import value_portfolio
from lantern.risk import factors as fm
from lantern.risk.report import asset_returns, risk_report


def test_demo_portfolios_value_sensibly(demo):
    s, summary = demo
    v = value_portfolio(s, summary["portfolios"]["Global Balanced Fund"])
    assert v.as_of == date(2025, 10, 31)
    assert 60_000_000 < v.total_value < 250_000_000
    assert 0 < v.cash_weight < 0.15
    assert len(v.positions) == 20  # 19 initial names + GLDF
    assert v.positions["weight"].sum() + v.cash_weight == pytest.approx(1.0)


def test_factor_model_recovers_generating_betas(demo):
    """Prices were generated from known betas; the estimator must find them."""
    s, summary = demo
    v = value_portfolio(s, summary["portfolios"]["Global Balanced Fund"])
    rets = asset_returns(s, v, lookback_days=700)
    frets = fm.factor_returns(s, rets.index.min().date() - timedelta(days=1), v.as_of)
    model = fm.estimate(rets, frets)
    by_ticker = {spec.ticker: spec for spec in UNIVERSE}
    tickers = v.positions["ticker"]
    for sid, t in tickers.items():
        spec = by_ticker[t]
        if spec.currency != "USD":
            continue  # USD-converted returns also carry EURUSD; skip the strict check
        assert model.betas.loc[sid, "MKT"] == pytest.approx(spec.mkt_beta, abs=0.2), t
        if spec.duration:
            assert model.betas.loc[sid, "RATES"] == pytest.approx(-spec.duration, abs=1.5), t


def test_full_risk_report(demo):
    s, summary = demo
    r = risk_report(s, summary["portfolios"]["Global Balanced Fund"])
    m = r["var"]["methods"]
    assert set(m) == {"historical", "parametric", "monte_carlo"}
    for d in m.values():
        assert 0 < d["var_pct"] < 0.10
        assert d["expected_shortfall"] >= d["var"]
    # Different estimators of the same thing should land in the same neighbourhood.
    assert m["monte_carlo"]["var"] == pytest.approx(m["parametric"]["var"], rel=0.10)
    names = {x["scenario"] for x in r["stress"]}
    assert "Rates +100bp" in names and "Equity -10%" in names
    up = next(x for x in r["stress"] if x["scenario"] == "Rates +100bp")
    down = next(x for x in r["stress"] if x["scenario"] == "Rates -100bp")
    assert up["pnl"] < 0 < down["pnl"]
    assert up["pnl"] == pytest.approx(-down["pnl"])
    assert 0.5 < r["factors"]["systematic_share"] <= 1.0
    assert {b["ticker"] for b in r["fixed_income"]} == {"UST2Y", "UST10Y", "CORP-IG", "CORP-HY"}
    ten = next(b for b in r["fixed_income"] if b["ticker"] == "UST10Y")
    assert 6 < ten["modified_duration"] < 10


def test_demo_orders_went_through_compliance(demo):
    s, summary = demo
    from lantern.models import Order

    rejected = s.get(Order, summary["orders"]["rejected"])
    assert rejected.status == "REJECTED" and "restricted" in rejected.reject_reason
    filled = s.get(Order, summary["orders"]["filled"])
    assert filled.status == "FILLED" and filled.filled_quantity == 2000


# ---------------------------------------------------------------- REST API


def test_api_health_and_lists(client):
    assert client.get("/health").json()["status"] == "ok"
    assert len(client.get("/portfolios").json()) == 2
    assert len(client.get("/securities").json()) == 21
    assert "max_position_weight" in client.get("/compliance/rule-types").json()
    assert client.get("/portfolios/999").status_code == 404


def test_api_positions_exposures_active(client):
    pos = client.get("/portfolios/1/positions").json()
    assert pos["total_value"] > 0 and len(pos["positions"]) == 20
    exp = client.get("/portfolios/1/exposures", params={"dimension": "asset_class"}).json()
    assert sum(b["weight"] for b in exp["buckets"]) == pytest.approx(1.0)
    act = client.get("/portfolios/1/active", params={"dimension": "sector"}).json()
    assert act["rows"] and all("active_weight" in r for r in act["rows"])
    assert client.get("/portfolios/1/exposures", params={"dimension": "nope"}).status_code == 400


def test_api_risk_endpoints(client):
    var = client.get("/portfolios/1/risk/var", params={"confidence": 0.95, "horizon_days": 10}).json()
    assert var["confidence"] == 0.95 and var["horizon_days"] == 10
    assert len(var["methods"]) == 3
    stress = client.get("/portfolios/1/risk/stress").json()
    assert len(stress) >= 5
    custom = client.post("/portfolios/1/risk/stress", json=[
        {"name": "tech crash", "shocks": {"sector": {"Technology": -0.5}}}
    ]).json()
    assert custom[0]["pnl"] < 0
    assert client.get("/portfolios/1/risk/factors").json()["factors"]
    assert len(client.get("/portfolios/1/risk/fixed-income").json()) == 4


def test_api_order_flow(client):
    secs = {s["ticker"]: s["id"] for s in client.get("/securities").json()}
    # Restricted name: rejected at creation, with the reason attached.
    r = client.post("/orders", json={"portfolio_id": 2, "security_id": secs["SMKE"], "side": "BUY", "quantity": 100})
    assert r.status_code == 201 and r.json()["status"] == "REJECTED"
    assert "restricted" in r.json()["reject_reason"]
    # Clean order: approved, then filled through the API, then visible in the ledger.
    r = client.post("/orders", json={"portfolio_id": 2, "security_id": secs["FOOD"], "side": "BUY", "quantity": 500})
    o = r.json()
    assert o["status"] == "APPROVED"
    before = client.get("/portfolios/2/positions").json()["cash"]
    f = client.post(f"/orders/{o['id']}/fills", json={"quantity": 500, "price": 70.0})
    assert f.json()["status"] == "FILLED"
    # Overfill is a conflict, not a crash.
    assert client.post(f"/orders/{o['id']}/fills", json={"quantity": 1, "price": 70.0}).status_code == 409
    # Fill is dated today, after the last price date, so it shows up when valued as of today.
    today = date.today().isoformat()
    after = client.get("/portfolios/2/positions", params={"as_of": today}).json()["cash"]
    assert after == pytest.approx(before - 500 * 70.0)
    blotter = client.get("/orders", params={"portfolio_id": 2}).json()
    assert any(b["id"] == o["id"] for b in blotter)
    assert client.get("/audit", params={"entity_type": "order"}).json()


def test_api_compliance_endpoints(client):
    secs = {s["ticker"]: s["id"] for s in client.get("/securities").json()}
    post = client.get("/portfolios/1/compliance").json()
    assert post["stage"] == "POST_TRADE"
    pre = client.post("/portfolios/1/compliance/pre-trade", json={
        "trades": [{"security_id": secs["ACME"], "side": "BUY", "quantity": 1_000_000}]
    }).json()
    assert pre["blocked"] is True
    rule = client.post("/compliance/rules", json={
        "portfolio_id": 2, "name": "tmp", "rule_type": "max_cash_weight", "params": {"limit": 0.5}, "severity": "SOFT"
    })
    assert rule.status_code == 201
    assert client.patch(f"/compliance/rules/{rule.json()['id']}", params={"active": False}).json()["active"] is False
    assert client.post("/compliance/rules", json={"name": "x", "rule_type": "bogus"}).status_code == 400
    assert client.get("/portfolios/1/compliance/history").json()  # the demo orders recorded checks
