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


# ----------------------------------------------------------------------------- signals


@app.command()
def seed_social(db: str | None = typer.Option(None, "--db"), days: int = 365, posts_per_day: int = 80,
                ic: float = typer.Option(0.03, help="Built-in edge of the synthetic stream (0 = pure noise; 0.03 is realistic for alt data)"),
                seed: int = 11):
    """Generate a synthetic social history aligned to the demo prices, with daily bubbles and sentiment bars."""
    from lantern.signals.sources.synthetic import seed_social_history

    with _session(db) as s:
        summary = seed_social_history(s, days=days, posts_per_day=posts_per_day, seed=seed, ic=ic)
    console.print_json(data=summary)


@app.command()
def ingest(sources: str = typer.Option("synthetic", help="Comma list: synthetic,bluesky,reddit,stocktwits,rss,kalshi,polymarket,x"),
           minutes: float = typer.Option(5.0, help="How long to run (0 = until Ctrl-C)"),
           topic_window: int = typer.Option(15, help="Minutes per topic-bubble window"),
           bar_window: int = typer.Option(60, help="Minutes per sentiment bar"),
           keywords: str = typer.Option("", help="bluesky: only keep posts containing one of these (comma list)"),
           symbols: str = typer.Option("", help="stocktwits: symbols to follow (comma list)"),
           db: str | None = typer.Option(None, "--db")):
    """Run the live pipeline: sources -> screening -> NLP -> store -> bubbles and bars every window."""
    import asyncio

    from lantern.signals import sources as src
    from lantern.signals.pipeline import Pipeline

    engine = make_engine(db or settings.database_url)
    init_db(engine)
    factory = make_session_factory(engine)
    built = []
    for name in [x.strip() for x in sources.split(",") if x.strip()]:
        kwargs: dict = {}
        if name == "synthetic":
            kwargs["session_factory"] = factory
        if name == "bluesky" and keywords:
            kwargs["keywords"] = [k.strip() for k in keywords.split(",")]
        if name == "stocktwits":
            kwargs["symbols"] = [k.strip() for k in symbols.split(",") if k.strip()] or ["SPY", "AAPL", "NVDA", "TSLA"]
        built.append(src.build(name, **kwargs))
    pipe = Pipeline(factory)

    def report(c: dict) -> None:
        console.print(f"received {c['received']:>7}  stored {c['stored']:>7}  dup {c['duplicates']:>5}  "
                      f"screened {c['screened_out']:>6}  quotes {c['quotes']:>5}  queue {c['queue']}", end="\r")

    console.print(f"Ingesting from {', '.join(s.name for s in built)} for {minutes or '∞'} min; dashboard at /dashboard")
    summary = asyncio.run(pipe.run(built, duration_seconds=minutes * 60 if minutes else None,
                                   topic_window_minutes=topic_window, bar_window_minutes=bar_window, on_batch=report))
    console.print()
    console.print_json(data=summary)


@app.command()
def bubbles(db: str | None = typer.Option(None, "--db")):
    """Latest topic bubbles."""
    from lantern.signals.aggregate import latest_topics

    with _session(db) as s:
        topics = latest_topics(s)
        if not topics:
            console.print("No topics yet. Run `lantern seed-social` or `lantern ingest`.")
            return
        console.print(f"Window {topics[0].window_start} → {topics[0].window_end} UTC")
        t = Table("topic", "volume", "authors", "sentiment", "velocity", "fear", "tickers")
        for tp in topics:
            t.add_row(tp.label, str(tp.volume), str(tp.unique_authors), f"{tp.sentiment_mean:+.2f}", f"{tp.velocity:+.0%}",
                      _pct(tp.fear_share), ", ".join(x[0] for x in tp.tickers))
        console.print(t)


@app.command()
def sentiment(db: str | None = typer.Option(None, "--db")):
    """Latest sentiment bar per security, with z-scores."""
    from lantern.signals.aggregate import latest_sentiment

    with _session(db) as s:
        df = latest_sentiment(s)
    if df.empty:
        console.print("No sentiment bars yet.")
        return
    t = Table("ticker", "posts", "authors", "sentiment", "bull", "bear", "sentiment z", "attention z")
    for r in df.itertuples():
        t.add_row(r.ticker, str(r.n_posts), str(r.n_authors), f"{r.sentiment_mean:+.2f}", _pct(r.bull_share), _pct(r.bear_share),
                  f"{r.sentiment_z:+.2f}" if r.sentiment_z == r.sentiment_z and r.sentiment_z is not None else "-",
                  f"{r.attention_z:+.2f}" if r.attention_z == r.attention_z and r.attention_z is not None else "-")
    console.print(t)


@app.command()
def markets(db: str | None = typer.Option(None, "--db")):
    """Latest prediction-market snapshot."""
    from lantern.signals.aggregate import latest_markets

    with _session(db) as s:
        df = latest_markets(s)
    if df.empty:
        console.print("No market snapshots yet.")
        return
    t = Table("source", "market", "yes", "24h", "volume")
    for r in df.itertuples():
        chg = "-" if r.change_24h is None or r.change_24h != r.change_24h else f"{r.change_24h * 100:+.1f} pts"
        t.add_row(r.source, r.title, _pct(r.yes_price), chg, _money(r.volume) if r.volume else "-")
    console.print(t)


@app.command()
def backtest(db: str | None = typer.Option(None, "--db"), horizon: int = 1, signal: str = "score", quantile: float = 0.3,
             days: int = 365):
    """Does the sentiment signal predict returns? Information coefficient and a long/short backtest."""
    from datetime import timedelta

    from lantern.marketdata.prices import latest_price_date
    from lantern.signals.signals import evaluate

    with _session(db) as s:
        end = latest_price_date(s) or date.today()
        r = evaluate(s, end - timedelta(days=days), end, horizon, signal, quantile)
    if "error" in r:
        console.print(f"[red]{r['error']}[/]")
        return
    ic, ls = r["ic"], r["long_short"]
    console.print(f"[bold]{r['signal']}[/] over {r['start']} → {r['end']}, horizon {r['horizon_days']}d, "
                  f"{r['names_per_day']:.1f} names/day")
    console.print("[dim]IC = daily rank correlation between the signal and the forward return[/]")
    t = Table("metric", "value", title="Information coefficient", min_width=44)
    t.add_row("days", str(ic["n_days"]))
    t.add_row("mean IC", f"{ic['mean_ic']:+.4f}")
    t.add_row("t-stat", f"{ic['t_stat']:+.2f}")
    t.add_row("hit rate", _pct(ic["hit_rate"]))
    console.print(t)
    console.print(f"[dim]Long top {quantile:.0%} / short bottom {quantile:.0%} by signal, daily rebalance, no costs[/]")
    t = Table("metric", "value", title="Long/short backtest", min_width=44)
    t.add_row("Sharpe", f"{ls['sharpe']:.2f}")
    t.add_row("ann. return", _pct(ls["ann_return"]))
    t.add_row("ann. vol", _pct(ls["ann_vol"]))
    t.add_row("max drawdown", _pct(ls["max_drawdown"]))
    t.add_row("daily turnover", _pct(ls["turnover"]))
    console.print(t)


@app.command()
def paper_trade(portfolio_id: int, db: str | None = typer.Option(None, "--db"), top_n: int = 5, sleeve: float = 0.10,
                min_score: float = 0.5, fill: bool = typer.Option(False, help="Fill approved orders at the latest price")):
    """Trade the sentiment signal on paper through the OMS (compliance applies)."""
    from lantern.signals.signals import fill_approved_at_market, strategy_orders

    with _session(db) as s:
        orders = strategy_orders(s, portfolio_id, top_n=top_n, sleeve=sleeve, min_score=min_score)
        n = fill_approved_at_market(s, orders) if fill else 0
        if not orders:
            console.print("No orders: no names clear the score threshold and nothing to unwind.")
            return
        t = Table("id", "ticker", "side", "qty", "status", "reason")
        for o in orders:
            t.add_row(str(o.id), o.security.ticker, o.side, f"{o.quantity:,.0f}", o.status, (o.reject_reason or "")[:70])
        console.print(t)
        if fill:
            console.print(f"Filled {n} approved orders at the latest price.")


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
