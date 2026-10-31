"""Command line: `lantern --help`."""

from __future__ import annotations

from datetime import date

import typer
from rich.console import Console
from rich.table import Table

from lantern.config import settings
from lantern.db import init_db, make_engine, make_session_factory

app = typer.Typer(help="Lantern: portfolio, risk, compliance and trading on one book of record.")
console = Console()


def _session(db_url: str | None):
    engine = make_engine(db_url or settings.database_url)
    init_db(engine)
    return make_session_factory(engine)()


def _money(x: float) -> str:
    return f"{x:,.0f}"


def _pct(x: float) -> str:
    return f"{x:.2%}"


@app.command()
def init_db_cmd(db: str | None = typer.Option(None, "--db", help="SQLAlchemy URL")):
    """Create the database schema."""
    engine = make_engine(db or settings.database_url)
    init_db(engine)
    console.print(f"[green]Schema ready[/] at {db or settings.database_url}")


@app.command()
def seed_demo(
    db: str | None = typer.Option(None, "--db"),
    seed: int = typer.Option(8, help="Random seed for the synthetic market"),
):
    """Load the demo universe: 21 securities, 3 years of prices, two portfolios, rules, orders."""
    from lantern.marketdata.synthetic import seed_demo as _seed

    with _session(db) as s:
        summary = _seed(s, seed=seed)
    console.print_json(data=summary)


@app.command()
def portfolios(db: str | None = typer.Option(None, "--db")):
    """List portfolios with their current value."""
    from sqlalchemy import select

    from lantern.models import Portfolio
    from lantern.portfolio.positions import value_portfolio

    with _session(db) as s:
        t = Table("id", "name", "ccy", "as of", "total value", "cash %", "positions")
        for pf in s.execute(select(Portfolio).order_by(Portfolio.id)).scalars():
            v = value_portfolio(s, pf.id)
            t.add_row(str(pf.id), pf.name, pf.base_currency, v.as_of.isoformat(),
                      _money(v.total_value), _pct(v.cash_weight), str(len(v.positions)))
        console.print(t)


@app.command()
def positions(portfolio_id: int, db: str | None = typer.Option(None, "--db"),
              as_of: str | None = typer.Option(None, help="YYYY-MM-DD")):
    """Valued holdings for a portfolio."""
    from lantern.portfolio.positions import value_portfolio

    with _session(db) as s:
        v = value_portfolio(s, portfolio_id, date.fromisoformat(as_of) if as_of else None)
        console.print(f"[bold]{v.portfolio_name}[/] as of {v.as_of}  total {_money(v.total_value)} {v.base_currency}")
        t = Table("ticker", "name", "asset class", "sector", "qty", "price", "ccy", "mkt value", "weight")
        for _sid, r in v.positions.sort_values("market_value", ascending=False).iterrows():
            t.add_row(r.ticker, r["name"], r.asset_class, r.sector, f"{r.quantity:,.0f}", f"{r.price:,.2f}",
                      r.currency, _money(r.market_value), _pct(r.weight))
        t.add_row("CASH", "", "Cash", "", "", "", v.base_currency, _money(v.cash), _pct(v.cash_weight))
        console.print(t)


@app.command()
def exposures(portfolio_id: int, by: str = typer.Option("sector", help="asset_class|sector|country|currency|issuer"),
              db: str | None = typer.Option(None, "--db")):
    """Exposure by dimension, with active weight vs benchmark when one is set."""
    from lantern.models import Portfolio
    from lantern.portfolio import exposures as ex
    from lantern.portfolio.positions import value_portfolio

    with _session(db) as s:
        pf = s.get(Portfolio, portfolio_id)
        v = value_portfolio(s, portfolio_id)
        if pf.benchmark_id:
            df = ex.active_exposures(s, v, ex.benchmark_weights(s, pf.benchmark_id), by)
            t = Table(by, "portfolio", "benchmark", "active")
            for b, r in df.iterrows():
                t.add_row(str(b), _pct(r.portfolio_weight), _pct(r.benchmark_weight), f"{r.active_weight:+.2%}")
        else:
            df = ex.exposure_by(v, by)
            t = Table(by, "market value", "weight")
            for b, r in df.iterrows():
                t.add_row(str(b), _money(r.market_value), _pct(r.weight))
        console.print(t)


@app.command()
def risk(portfolio_id: int, db: str | None = typer.Option(None, "--db"),
         confidence: float = typer.Option(None), horizon: int = typer.Option(None)):
    """VaR (three methods), stress scenarios, factor exposures and bond analytics."""
    from lantern.risk.report import risk_report

    with _session(db) as s:
        r = risk_report(s, portfolio_id, confidence=confidence, horizon_days=horizon)
    p = r["portfolio"]
    console.print(f"[bold]{p['name']}[/] as of {p['as_of']}  value {_money(p['total_value'])} {p['base_currency']}")

    v = r["var"]
    if v.get("methods"):
        t = Table(
            "method", "VaR", "VaR %", "ES", "ES %",
            title=f"VaR {v['confidence']:.0%} / {v['horizon_days']}d  "
            f"(ann. vol {v['annualised_vol']:.2%}, {v['observations']} obs)",
        )
        for m, d in v["methods"].items():
            t.add_row(m, _money(d["var"]), _pct(d["var_pct"]), _money(d["expected_shortfall"]), _pct(d["es_pct"]))
        console.print(t)
        t = Table(title="Component VaR (parametric), top 8")
        for c in ("ticker", "weight", "component VaR", "% of total"):
            t.add_column(c)
        for row in v["component_var"][:8]:
            t.add_row(row["ticker"], _pct(row["weight"]), _money(row["component_var"]), _pct(row["pct_of_total"]))
        console.print(t)

    t = Table("scenario", "P&L", "P&L %", title="Stress scenarios")
    for sres in r["stress"]:
        t.add_row(sres["scenario"], _money(sres["pnl"]), _pct(sres["pnl_pct"]))
    console.print(t)

    f = r["factors"]
    if "factor_exposures" in f:
        t = Table(
            "factor", "exposure", "share of variance",
            title=f"Factor model (ann. vol): total {f['total_vol']:.1%}, "
            f"systematic {f['systematic_vol']:.1%}, idio {f['idiosyncratic_vol']:.1%}",
        )
        for k in f["factors"]:
            t.add_row(k, f"{f['factor_exposures'][k]:+.3f}", _pct(f["factor_contribution"][k]))
        console.print(t)

    if r["fixed_income"]:
        t = Table(title="Fixed income")
        for c in ("ticker", "price", "ytm", "mod dur", "convexity", "weight"):
            t.add_column(c)
        for b in r["fixed_income"]:
            t.add_row(b["ticker"], f"{b['price']:.2f}", _pct(b["ytm"]), f"{b['modified_duration']:.2f}",
                      f"{b['convexity']:.1f}", _pct(b["weight"]))
        console.print(t)


@app.command()
def compliance(portfolio_id: int, db: str | None = typer.Option(None, "--db")):
    """Post-trade compliance: every active rule against current holdings."""
    from lantern.compliance.engine import post_trade_check

    with _session(db) as s:
        res = post_trade_check(s, portfolio_id, record=False)
    status = "[green]PASS[/]" if res.passed else "[red]FAIL[/]"
    console.print(f"Portfolio {portfolio_id} as of {res.as_of}: {status}  ({len(res.breaches)} breaches)")
    if res.breaches:
        t = Table("severity", "rule", "scope", "observed", "limit", "message")
        for b in res.breaches:
            sev = f"[red]{b.severity.value}[/]" if b.severity.value == "HARD" else f"[yellow]{b.severity.value}[/]"
            t.add_row(sev, b.rule_name, b.scope,
                      _pct(b.observed) if b.observed is not None else "-",
                      _pct(b.limit) if b.limit is not None else "-", b.message)
        console.print(t)


@app.command()
def orders(db: str | None = typer.Option(None, "--db"), portfolio_id: int | None = None):
    """The order blotter."""
    from lantern.trading.oms import blotter

    with _session(db) as s:
        t = Table("id", "portfolio", "ticker", "side", "qty", "filled", "avg px", "type", "status", "reason")
        for o in blotter(s, portfolio_id):
            t.add_row(str(o.id), str(o.portfolio_id), o.security.ticker, o.side, f"{o.quantity:,.0f}",
                      f"{o.filled_quantity:,.0f}", f"{o.avg_fill_price:,.2f}" if o.avg_fill_price else "-",
                      o.order_type, o.status, (o.reject_reason or "")[:60])
        console.print(t)


@app.command()
def serve(host: str = "127.0.0.1", port: int = 8000, db: str | None = typer.Option(None, "--db"),
          reload: bool = False):
    """Run the REST API (docs at /docs)."""
    import os

    import uvicorn

    if db:
        os.environ["LANTERN_DATABASE_URL"] = db
    uvicorn.run("lantern.api.app:app", host=host, port=port, reload=reload)


if __name__ == "__main__":
    app()
