"""Command line: `spectre --help`."""

from __future__ import annotations

from datetime import date

import typer
from rich.console import Console
from rich.table import Table

from spectre.config import settings
from spectre.db import init_db, make_engine, make_session_factory

app = typer.Typer(help="SPECTRE: Signal Processing, Execution, Compliance, Trading & Risk Engine.")
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
    from spectre.marketdata.synthetic import seed_demo as _seed

    with _session(db) as s:
        summary = _seed(s, seed=seed)
    console.print_json(data=summary)


@app.command()
def portfolios(db: str | None = typer.Option(None, "--db")):
    """List portfolios with their current value."""
    from sqlalchemy import select

    from spectre.models import Portfolio
    from spectre.portfolio.positions import value_portfolio

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
    from spectre.portfolio.positions import value_portfolio

    with _session(db) as s:
        v = value_portfolio(s, portfolio_id, date.fromisoformat(as_of) if as_of else None)
        console.print(f"[bold]{v.portfolio_name}[/] as of {v.as_of}  total {_money(v.total_value)} {v.base_currency}")
        t = Table("ticker", "name", "asset class", "sector", "qty", "price", "ccy", "mkt value", "weight")
        for _sid, r in v.positions.sort_values("market_value", ascending=False).iterrows():
            t.add_row(r.ticker, r["name"], r.asset_class, r.sector, _fmt_qty(r.quantity), _fmt_px(r.price),
                      r.currency, _money(r.market_value), _pct(r.weight))
        t.add_row("CASH", "", "Cash", "", "", "", v.base_currency, _money(v.cash), _pct(v.cash_weight))
        console.print(t)


@app.command()
def exposures(portfolio_id: int, by: str = typer.Option("sector", help="asset_class|sector|country|currency|issuer"),
              db: str | None = typer.Option(None, "--db")):
    """Exposure by dimension, with active weight vs benchmark when one is set."""
    from spectre.models import Portfolio
    from spectre.portfolio import exposures as ex
    from spectre.portfolio.positions import value_portfolio

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
    from spectre.risk.report import risk_report

    with _session(db) as s:
        r = risk_report(s, portfolio_id, confidence=confidence, horizon_days=horizon)
    p = r["portfolio"]
    console.print(f"[bold]{p['name']}[/] as of {p['as_of']}  value {_money(p['total_value'])} {p['base_currency']}")

    v = r["var"]
    e = v.get("exposure")
    if e and e["net_pct"] is not None:
        by = e["by"]
        console.print(f"Market exposure {_money(e['net'])} = [bold]{e['net_pct']:.0%}[/] of the portfolio's value: "
                      f"stocks and funds {_money(by['stocks_and_funds'])}, coins {_money(by['coins'])}, "
                      f"options {_money(by['options_delta_equivalent'])} by delta (they cost {_money(e['option_premium'])}).")
    if v.get("options_by_delta"):
        console.print("[dim]Options are counted through their delta: a first-order estimate that ignores gamma, "
                      "volatility and time decay.[/]")
    if v.get("not_modelled"):
        console.print(f"[yellow]Not in the risk numbers: {', '.join(v['not_modelled'])}[/]")
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
    from spectre.compliance.engine import post_trade_check

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
    from spectre.trading.oms import blotter

    with _session(db) as s:
        t = Table("id", "portfolio", "ticker", "side", "qty", "filled", "avg px", "type", "status", "reason")
        for o in blotter(s, portfolio_id):
            t.add_row(str(o.id), str(o.portfolio_id), o.security.ticker, o.side, _fmt_qty(o.quantity),
                      _fmt_qty(o.filled_quantity), f"{o.avg_fill_price:,.2f}" if o.avg_fill_price else "-",
                      o.order_type, o.status, (o.reject_reason or "")[:60])
        console.print(t)


# ----------------------------------------------------------------------------- signals


@app.command()
def seed_social(db: str | None = typer.Option(None, "--db"), days: int = 365, posts_per_day: int = 80,
                ic: float = typer.Option(0.03, help="Built-in edge of the synthetic stream (0 = pure noise; 0.03 is realistic for alt data)"),
                seed: int = 11):
    """Generate a synthetic social history aligned to the demo prices, with daily bubbles and sentiment bars."""
    from spectre.signals.sources.synthetic import seed_social_history

    with _session(db) as s:
        summary = seed_social_history(s, days=days, posts_per_day=posts_per_day, seed=seed, ic=ic)
    console.print_json(data=summary)


@app.command()
def seed_universe(db: str | None = typer.Option(None, "--db")):
    """Add the curated real-world tickers (reference data only, no prices) so live posts map to companies."""
    from spectre.marketdata.universe import seed_universe as _seed

    with _session(db) as s:
        console.print_json(data=_seed(s))


def _build_sources(factory, sources: str, preset: str = "finance", sample: float = 1.0, keywords: str = "",
                   symbols: str = "", geos: str = "US", feeds: str = "") -> list:
    """Turn the command-line source options into source objects."""
    from sqlalchemy import select

    from spectre.marketdata.universe import firehose_keywords
    from spectre.models import Security
    from spectre.signals import sources as src
    from spectre.signals.nlp import FINANCE_TERMS

    extra = [k.strip() for k in keywords.split(",") if k.strip()]
    built = []
    for name in [x.strip() for x in sources.split(",") if x.strip()]:
        kwargs: dict = {}
        if name == "synthetic":
            kwargs["session_factory"] = factory
        if name == "bluesky":
            kwargs["sample"] = sample
            if preset == "finance":
                with factory() as s:
                    tickers = set(s.execute(select(Security.ticker)).scalars())
                kwargs["keywords"] = FINANCE_TERMS + firehose_keywords(tickers) + extra
            elif extra:
                kwargs["keywords"] = extra
        if name == "stocktwits":
            kwargs["symbols"] = [k.strip().upper() for k in symbols.split(",") if k.strip()]
        if name in ("trends", "google_trends"):
            kwargs["geos"] = tuple(g.strip().upper() for g in geos.split(",") if g.strip())
        if name == "rss":
            kwargs["feeds"] = dict(pair.split("=", 1) for pair in feeds.split(",") if "=" in pair)
        built.append(src.build(name, **kwargs))
    return built


@app.command()
def ingest(sources: str = typer.Option("synthetic", help="Comma list: synthetic,bluesky,stocktwits,kalshi,polymarket,trends,reddit,rss,x"),
           minutes: float = typer.Option(5.0, help="How long to run (0 = until Ctrl-C)"),
           topic_window: int = typer.Option(15, help="Minutes per topic-bubble window"),
           bar_window: int = typer.Option(60, help="Minutes per sentiment bar"),
           preset: str = typer.Option("finance", help="bluesky: 'finance' keeps market talk only; 'all' keeps everything (use --sample)"),
           sample: float = typer.Option(1.0, help="bluesky: fraction of matching posts to keep (e.g. 0.1 with --preset all)"),
           keywords: str = typer.Option("", help="bluesky: extra terms to keep (comma list)"),
           symbols: str = typer.Option("", help="stocktwits: symbols to follow besides the trending stream (comma list)"),
           geos: str = typer.Option("US", help="trends: countries (comma list of codes)"),
           feeds: str = typer.Option("", help="rss: name=url pairs (comma list)"),
           db: str | None = typer.Option(None, "--db")):
    """Run the live pipeline: sources -> screening -> NLP -> store -> bubbles and bars every window."""
    import asyncio

    from spectre.signals.pipeline import Pipeline

    engine = make_engine(db or settings.database_url)
    init_db(engine)
    factory = make_session_factory(engine)
    built = _build_sources(factory, sources, preset, sample, keywords, symbols, geos, feeds)
    pipe = Pipeline(factory)

    def report(c: dict) -> None:
        console.print(f"received {c['received']:>7}  stored {c['stored']:>7}  dup {c['duplicates']:>5}  "
                      f"screened {c['screened_out']:>6}  quotes {c['quotes']:>5}  trends {c['trends']:>4}  "
                      f"queue {c['queue']}", end="\r")

    console.print(f"Ingesting from {', '.join(s.name for s in built)} for {minutes or '∞'} min; dashboard at /dashboard")
    summary = asyncio.run(pipe.run(built, duration_seconds=minutes * 60 if minutes else None,
                                   topic_window_minutes=topic_window, bar_window_minutes=bar_window, on_batch=report))
    console.print()
    console.print_json(data=summary)


@app.command()
def bubbles(db: str | None = typer.Option(None, "--db")):
    """Latest topic bubbles."""
    from spectre.signals.aggregate import latest_topics

    with _session(db) as s:
        topics = latest_topics(s)
        if not topics:
            console.print("No topics yet. Run `spectre seed-social` or `spectre ingest`.")
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
    from spectre.signals.aggregate import latest_sentiment

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
    from spectre.signals.aggregate import latest_markets

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
def trends(db: str | None = typer.Option(None, "--db"), hours: float = 24):
    """Trending search terms (Google Trends)."""
    from spectre.signals.aggregate import latest_trends

    with _session(db) as s:
        rows = latest_trends(s, hours)
    if not rows:
        console.print("No trends yet. Run `spectre ingest --sources trends`.")
        return
    t = Table("term", "geo", "searches", "tickers", "top headline")
    for r in rows:
        t.add_row(r["term"], r["geo"], f"{r['approx_traffic']:,}+" if r["approx_traffic"] else "-",
                  ", ".join(r["tickers"]), (r["headlines"][0] if r["headlines"] else "")[:70])
    console.print(t)


def _sentiment_line(r: dict) -> str:
    """One line on the state of the learned sentiment model, for a log or a terminal."""
    if "blend" not in r:
        return f"Sentiment: word list only ({r.get('reason', 'no model trained')})."
    return (f"Sentiment: {'word list blended with a learned model' if r['adopt'] else 'word list only'} "
            f"({r['reason']}; {r['labelled']:,} tagged posts, judged on {r['judged']:,} later ones).")


@app.command()
def sentiment_train(db: str | None = typer.Option(None, "--db")):
    """Train a sentiment model on posts their authors tagged Bullish or Bearish, test it on later
    posts, and use it (blended with the word list) only if that beats the word list alone."""
    from spectre.signals import learned

    url = db or settings.database_url
    with _session(db) as s:
        r = learned.train(s, learned.model_path(url))
    if "blend" not in r:
        console.print(r.get("reason", "Nothing to train on."))
        return
    console.print(f"{r['labelled']:,} tagged posts ({r['bullish_share']:.0%} bullish), {r['from']} to {r['to']} UTC. "
                  f"Trained on earlier posts and judged on {r['judged']:,} later ones.")
    t = Table("scorer", "ranks later posts (0.5 = coin toss)", "takes a side on", "right when it does")
    for name, key in (("word list", "lexicon"), ("learned from tags", "learned"), ("even blend of the two", "blend")):
        m = r[key]
        t.add_row(name, f"{m['auc']:.3f}", f"{m['takes_a_side']:.0%}", "-" if m["right_when_it_does"] is None else f"{m['right_when_it_does']:.0%}")
    console.print(t)
    console.print(f"Always guessing the commoner tag would be right {r['majority_share']:.0%} of the time.")
    console.print(("[green]In use from the next start:[/] " if r["adopt"] else "[yellow]Not adopted:[/] ") + r["reason"] + ".")


@app.command()
def calibrate(db: str | None = typer.Option(None, "--db")):
    """Check the sentiment model against Bullish/Bearish labels users put on their own posts."""
    from spectre.signals.aggregate import sentiment_calibration

    with _session(db) as s:
        r = sentiment_calibration(s)
    if not r["labelled_posts"]:
        console.print("No labelled posts yet. Run `spectre ingest --sources stocktwits`.")
        return
    c = r["confusion"]
    console.print(f"{r['labelled_posts']} labelled posts, {_pct(r['label_bullish_share'])} of them bullish")
    console.print(f"Model takes a side on {_pct(r['coverage'])}; when it does it is right {_pct(r['accuracy'])} of the time "
                  f"(always guessing the majority label would score {_pct(r['majority_baseline'])})")
    t = Table("user said", "model: bullish", "model: bearish", "model: neutral")
    t.add_row("Bullish", str(c["bull_as_bull"]), str(c["bull_as_bear"]), str(c["bull_as_neutral"]))
    t.add_row("Bearish", str(c["bear_as_bull"]), str(c["bear_as_bear"]), str(c["bear_as_neutral"]))
    console.print(t)


@app.command()
def signal_check(horizon: int = typer.Option(60, help="Minutes ahead to look at what the price did"),
                 days: float = typer.Option(5.0, help="How far back to measure"),
                 crypto: bool = typer.Option(False, help="Measure the coins instead of stocks and funds"),
                 lookback: int = typer.Option(45, help="Minutes of conversation behind each read (as the bot uses)"),
                 min_authors: int = typer.Option(8, help="Fewest distinct authors behind a read (as the bot uses)"),
                 db: str | None = typer.Option(None, "--db")):
    """Does the crowd read predict what the price does next? Measured on the data collected so far."""
    from spectre.execution.alpaca import AlpacaClient, AlpacaError
    from spectre.signals.intraday import check
    from spectre.signals.strategy import CRYPTO, STOCKS

    try:
        with _session(db) as s:
            r = check(s, AlpacaClient(), days=days, horizon=horizon, lookback=lookback, min_authors=min_authors,
                      asset_classes=CRYPTO if crypto else STOCKS)
    except AlpacaError as exc:
        console.print(f"[red]Alpaca (prices): {exc}[/]")
        raise typer.Exit(1) from exc
    if not r["samples"]:
        console.print(r["verdict"])
        return

    def pct(x: float | None, digits: int = 3) -> str:
        return "-" if x is None else f"{x:+.{digits}%}"

    def num(x: float | None) -> str:
        return "-" if x is None else f"{x:+.2f}"

    console.print(f"[bold]{'Coins' if crypto else 'Stocks and funds'}[/], {r['from']} to {r['to']} UTC: {r['samples']} readings of "
                  f"{r['names']} names at {r['moments']} moments, looking {r['horizon_minutes']} minutes ahead. "
                  f"Separate windows: [bold]{r['windows']}[/].")
    t = Table("what followed", "readings", "return", "against the other names", "share that beat them", title="By zone")
    for z in r["zones"]:
        t.add_row(z["zone"], str(z["samples"]), pct(z["mean_return"]), pct(z["mean_relative_return"]),
                  "-" if z["share_beating_the_rest"] is None else f"{z['share_beating_the_rest']:.0%}")
    console.print(t)
    ra, h = r["rank_agreement"], r["held"]
    t = Table("measure", "value", "moments", "share positive", "t")
    t.add_row("Rank agreement between score and what followed (-1 to +1)", num(ra["mean"]), str(ra["moments"]),
              "-" if ra["share_positive"] is None else f"{ra['share_positive']:.0%}", num(ra["t_stat"]))
    t.add_row(f"Top {h['top_n']} in the buy zone against all names", pct(h["mean_edge"]), str(h["moments"]),
              "-" if h["share_positive"] is None else f"{h['share_positive']:.0%}", num(h["t_stat"]))
    console.print(t)
    console.print(f"[bold]{r['verdict']}[/]")
    console.print("[dim]t is the average over its standard error, counting only separate windows; around 2 or more starts to mean something.[/]")


@app.command()
def backtest(db: str | None = typer.Option(None, "--db"), horizon: int = 1, signal: str = "score", quantile: float = 0.3,
             days: int = 365,
             cost_bps: float = typer.Option(5.0, help="One-way trading cost in basis points (spread + fees)")):
    """Does the sentiment signal predict returns? Information coefficient and a long/short backtest."""
    from datetime import timedelta

    from spectre.marketdata.prices import latest_price_date
    from spectre.signals.signals import evaluate

    with _session(db) as s:
        end = latest_price_date(s) or date.today()
        r = evaluate(s, end - timedelta(days=days), end, horizon, signal, quantile, cost_bps)
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
    console.print(f"[dim]Long top {quantile:.0%} / short bottom {quantile:.0%} by signal, daily rebalance, "
                  f"{cost_bps:g} bps cost each way[/]")
    t = Table("metric", "before costs", "after costs", title="Long/short backtest", min_width=56)
    t.add_row("Sharpe", f"{ls['gross_sharpe']:.2f}", f"{ls['sharpe']:.2f}")
    t.add_row("ann. return", _pct(ls["gross_ann_return"]), _pct(ls["ann_return"]))
    t.add_row("ann. trading cost", "-", _pct(ls["ann_cost"]))
    t.add_row("ann. vol", "", _pct(ls["ann_vol"]))
    t.add_row("max drawdown", "", _pct(ls["max_drawdown"]))
    t.add_row("daily turnover", "", _pct(ls["turnover"]))
    console.print(t)


@app.command()
def paper_trade(portfolio_id: int, db: str | None = typer.Option(None, "--db"), top_n: int = 5, sleeve: float = 0.10,
                min_score: float = 0.5, fill: bool = typer.Option(False, help="Fill approved orders at the latest price")):
    """Trade the sentiment signal on paper through the OMS (compliance applies)."""
    from spectre.signals.signals import fill_approved_at_market, strategy_orders

    with _session(db) as s:
        orders = strategy_orders(s, portfolio_id, top_n=top_n, sleeve=sleeve, min_score=min_score)
        n = fill_approved_at_market(s, orders) if fill else 0
        if not orders:
            console.print("No orders: no names clear the score threshold and nothing to unwind.")
            return
        t = Table("id", "ticker", "side", "qty", "status", "reason")
        for o in orders:
            t.add_row(str(o.id), o.security.ticker, o.side, _fmt_qty(o.quantity), o.status, (o.reject_reason or "")[:70])
        console.print(t)
        if fill:
            console.print(f"Filled {n} approved orders at the latest price.")


# ----------------------------------------------------------------------------- rates


@app.command()
def rates_sync(years: int = typer.Option(2, help="How many calendar years of history to keep up to date"),
               credit: bool = typer.Option(False, help="Also fetch credit spreads and policy rates from FRED"),
               db: str | None = typer.Option(None, "--db")):
    """Download the US Treasury yield curve (and optionally FRED credit spreads)."""
    from spectre.rates import fred, treasury

    this_year = date.today().year
    with _session(db) as s:
        r = treasury.sync(s, years=list(range(this_year - years + 1, this_year + 1)))
        console.print(f"Treasury curve: {r['new_points']} new points, latest {r['latest_date']}")
        if credit:
            f = fred.sync(s)
            console.print(f"FRED: {f['new_points']} new points across {len(f['series']) - len(f['failed'])} series")
            for sid, why in f["failed"].items():
                console.print(f"  [yellow]{sid} skipped: {why}[/]")


@app.command()
def rates(db: str | None = typer.Option(None, "--db")):
    """Today's Treasury yield curve, how it has moved, and whether it is inverted."""
    from spectre.rates.analytics import latest_curve, latest_macro

    with _session(db) as s:
        c = latest_curve(s)
        macro = latest_macro(s)
    if c is None:
        console.print("No curve stored yet. Run `spectre rates-sync`.")
        return

    def bp(x):
        return "-" if x is None else f"[{'red' if x > 0 else 'green' if x < 0 else 'white'}]{x:+.0f}[/]"

    console.print(f"[bold]US Treasury yield curve[/] {c['date']}")
    t = Table("maturity", "yield", "1 day (bp)", "1 week (bp)", "1 month (bp)")
    for p in c["points"]:
        t.add_row(p["tenor"], f"{p['yield']:.2f}%", bp(p["change_1d_bp"]), bp(p["change_1w_bp"]), bp(p["change_1m_bp"]))
    console.print(t)
    shape = "[red]inverted[/]" if c["inverted"] else "upward sloping"
    console.print(f"10y minus 2y: {c['slope_2s10s_bp']:+.0f} bp (a month ago {c['slope_2s10s_1m_ago_bp'] or 0:+.0f}); "
                  f"10y minus 3m: {c['slope_3m10y_bp']:+.0f} bp; curve is {shape}")
    if macro:
        from spectre.rates.fred import SERIES

        t = Table("series", "latest", "1 month change", "as of", "what it is")
        for m in macro:
            chg = "-" if m["change_1m"] is None else f"{m['change_1m']:+.2f}"
            t.add_row(m["series"], f"{m['value']:.2f}", chg, m["date"], SERIES.get(m["series"], ""))
        console.print(t)


# ----------------------------------------------------------------------------- fundamentals


def _big(x: float | None) -> str:
    if x is None:
        return "-"
    a = abs(x)
    if a >= 1e9:
        return f"{x / 1e9:,.2f}bn"
    if a >= 1e6:
        return f"{x / 1e6:,.1f}m"
    return f"{x:,.2f}"


def _chg(x: float | None) -> str:
    if x is None:
        return "-"
    return f"[{'green' if x >= 0 else 'red'}]{x:+.1%}[/]"


@app.command()
def fundamentals_sync(tickers: str = typer.Option("", help="Comma list; default is every equity in the book"),
                      db: str | None = typer.Option(None, "--db")):
    """Download quarterly results from SEC filings (needs SPECTRE_SEC_USER_AGENT to be set)."""
    from spectre.fundamentals.edgar import sync

    with _session(db) as s:
        try:
            r = sync(s, [t.strip() for t in tickers.split(",") if t.strip()] or None)
        except ValueError as exc:
            console.print(f"[red]{exc}[/]")
            raise typer.Exit(1) from exc
    console.print(f"Stored quarters for {len(r['stored'])} companies; skipped {len(r['skipped'])}.")
    for t, why in list(r["skipped"].items())[:10]:
        console.print(f"  [dim]{t}: {why}[/]")


@app.command()
def earnings(ticker: str, db: str | None = typer.Option(None, "--db")):
    """Latest reported quarter against the previous quarter and the same quarter a year ago."""
    from sqlalchemy import select

    from spectre.fundamentals.compare import company_report
    from spectre.models import Security

    with _session(db) as s:
        sec = s.execute(select(Security).where(Security.ticker == ticker.upper())).scalar_one_or_none()
        if sec is None:
            console.print(f"[red]Unknown ticker {ticker}[/]")
            raise typer.Exit(1)
        r = company_report(s, sec.id, sec.ticker)
    if not r["metrics"]:
        console.print(f"No filed results stored for {sec.ticker}. Run `spectre fundamentals-sync --tickers {sec.ticker}`.")
        return
    console.print(f"[bold]{sec.ticker}[/] {sec.name}: quarter ended {r.get('period_end', '?')}")
    t = Table("metric", "latest quarter", "previous quarter", "change", "year ago", "change", "note")
    labels = {"revenue": "Revenue", "gross_profit": "Gross profit", "operating_income": "Operating income",
              "net_income": "Net income", "eps_diluted": "EPS (diluted)", "operating_cash_flow": "Operating cash flow"}
    for key, label in labels.items():
        m = r["metrics"].get(key)
        if m:
            t.add_row(label, _big(m["latest"]), _big(m["previous_quarter"]), _chg(m["qoq"]), _big(m["year_ago"]),
                      _chg(m["yoy"]), "derived" if m["derived"] else "")
    console.print(t)
    if r["margins"]:
        t = Table("margin", "latest", "previous quarter", "change (pts)", "year ago", "change (pts)")
        for key, m in r["margins"].items():
            def pts(x):
                return "-" if x is None else f"[{'green' if x >= 0 else 'red'}]{x:+.1f}[/]"
            t.add_row(key.replace("_", " "), _pct(m["latest"]), _pct(m["previous_quarter"]) if m["previous_quarter"] is not None else "-",
                      pts(m["change_vs_previous_pts"]), _pct(m["year_ago"]) if m["year_ago"] is not None else "-",
                      pts(m["change_vs_year_ago_pts"]))
        console.print(t)


# ----------------------------------------------------------------------------- trading


@app.command()
def portfolio_create(name: str, cash: float = typer.Option(100_000.0, help="Starting cash"),
                     db: str | None = typer.Option(None, "--db")):
    """Create a portfolio funded with cash (for paper trading real tickers)."""
    from sqlalchemy import select

    from spectre.models import Portfolio

    with _session(db) as s:
        if s.execute(select(Portfolio).where(Portfolio.name == name)).scalar_one_or_none():
            console.print(f"[red]Portfolio '{name}' already exists[/]")
            raise typer.Exit(1)
        pf = _new_trading_portfolio(s, name, cash)
        console.print(f"Created portfolio {pf.id} '{name}' with {_money(cash)} {pf.base_currency}")


def _new_trading_portfolio(s, name: str, cash: float | None):
    """A portfolio for the bot: funded with `cash` (None = leave it empty, to be filled from a
    broker account) and given the rules a cash account trades under."""
    from spectre.marketdata.prices import latest_price_date
    from spectre.models import CashFlow, ComplianceRule, Portfolio

    pf = Portfolio(name=name, base_currency=settings.base_currency)
    s.add(pf)
    s.flush()
    if cash is not None:
        s.add(CashFlow(portfolio_id=pf.id, date=min(latest_price_date(s) or date.today(), date.today()), amount=cash,
                       memo="Initial funding"))
    for rule_name, rule_type in (("No overdraft", "no_negative_cash"), ("No short positions", "no_short_positions"),
                                 ("No naked options", "no_naked_options"),
                                 ("No good-faith violations", "no_good_faith_violations")):
        s.add(ComplianceRule(portfolio_id=pf.id, name=rule_name, rule_type=rule_type, params={}, severity="HARD"))
    s.commit()
    return pf


@app.command()
def order(portfolio_id: int, ticker: str, side: str, quantity: float,
          limit: float | None = typer.Option(None, help="Limit price; omit for a market order"),
          actor: str = "cli", db: str | None = typer.Option(None, "--db")):
    """Create an order. Compliance checks it immediately; nothing is sent anywhere yet."""
    from sqlalchemy import select

    from spectre.models import OrderType, Security, Side
    from spectre.trading import oms

    with _session(db) as s:
        sec = s.execute(select(Security).where(Security.ticker == ticker.upper())).scalar_one_or_none()
        if sec is None:
            console.print(f"[red]Unknown ticker {ticker}[/]")
            raise typer.Exit(1)
        o = oms.create_order(s, portfolio_id=portfolio_id, security_id=sec.id, side=Side(side.upper()), quantity=quantity,
                             order_type=OrderType.LIMIT if limit is not None else OrderType.MARKET, limit_price=limit,
                             actor=actor)
        colour = "green" if o.status == "APPROVED" else "red"
        console.print(f"Order {o.id}: {o.side} {_fmt_qty(o.quantity)} {sec.ticker} -> [{colour}]{o.status}[/] {o.reject_reason or ''}")
        if o.status == "APPROVED":
            console.print(f"Run `spectre execute {o.id}` to fill it on paper.")


@app.command()
def execute(order_id: int, slippage_bps: float = typer.Option(0.0, help="Built-in paper broker: slippage against you"),
            broker: str = typer.Option("paper", help="'paper' (built-in simulation) or 'alpaca' (your Alpaca paper account)"),
            db: str | None = typer.Option(None, "--db")):
    """Fill an approved order on paper, subject to the trading limits and kill switch."""
    from spectre.execution.brokers import PaperBroker
    from spectre.execution.guard import execute as _execute

    with _session(db) as s:
        chosen = PaperBroker(slippage_bps) if broker == "paper" else _broker(broker, s)
        r = _execute(s, order_id, chosen, actor="cli")
    if r.outcome == "executed":
        console.print(f"[green]Executed[/] order {r.order_id} on {r.broker}: {_fmt_qty(r.quantity)} @ {_fmt_px(r.price)}")
    else:
        console.print(f"[red]{r.outcome}[/] order {r.order_id}: " + "; ".join(r.reasons))


def _broker(name: str, session=None):
    """'paper' is the built-in simulation; 'alpaca' is your Alpaca paper account (still fake money)."""
    if name == "alpaca":
        from spectre.execution.alpaca import AlpacaClient, AlpacaPaperBroker, sync_prices

        client = AlpacaClient()
        if session is not None:
            sync_prices(session, client)  # decide and size on Alpaca's latest prices
        return AlpacaPaperBroker(client)
    if name != "paper":
        raise typer.BadParameter("broker must be 'paper' or 'alpaca'")
    from spectre.execution.brokers import PaperBroker

    return PaperBroker()


def _option_rules(budget: float, per_trade: float, enter: float, min_authors: int, max_exposure: float = 0.0):
    from spectre.signals.options_strategy import OptionRules

    return OptionRules(budget=budget, per_trade=per_trade, enter=enter, min_authors=min_authors,
                       max_exposure=max_exposure or None)


def _fmt_qty(q: float) -> str:
    """Whole numbers plainly, fractions of a coin to six places."""
    return f"{q:,.0f}" if float(q).is_integer() else f"{q:,.6f}".rstrip("0")


def _fmt_px(px: float | None) -> str:
    if not px:
        return "-"
    return f"{px:,.2f}" if px >= 1 else f"{px:.6f}"


def _action_line(a: dict) -> str:
    colour = {"executed": "green", "dry run": "yellow", "skipped": "dim"}.get(a["outcome"], "red")
    return (f"{a['side']:<4} {_fmt_qty(a['quantity']):>10} {a['ticker']:<21} @ {_fmt_px(a.get('fill_price') or a.get('price')):>10}  "
            f"[{colour}]{a['outcome']}[/]  {a.get('detail') or a['why']}")


CRYPTO_STREAMS = "BTC.X,ETH.X,SOL.X,XRP.X,DOGE.X"


def _kairos_cycle(s, portfolio_id: int, broker: str, *, top_n, invest, enter, exit_below, lookback, min_authors,
                  dry_run=False, options=False, option_rules=None, crypto=False, crypto_invest=0.10, crypto_top=3,
                  stop_loss=None, crypto_stop_loss=None, min_hold=60.0, crypto_min_hold=240.0, crypto_enter=0.5,
                  risk_weighted=True):
    """One full KAIROS cycle: stocks and options while the stock market is open, coins at any hour.
    Returns (stock report or None, coin report or None, every action taken, notes worth printing)."""
    from spectre.signals.strategy import CRYPTO, run_once

    route = _broker(broker, s)
    notes: list[str] = []
    market_open = True
    if broker == "alpaca":
        from spectre.execution.alpaca import reconcile

        clock = route.client.clock()
        market_open = bool(clock.get("is_open"))
        if not market_open:
            notes.append(f"stock market closed (next open {clock.get('next_open')})")
        if not dry_run:
            rec = reconcile(s, route.client, portfolio_id, apply=True)
            for item in rec["positions"]:
                notes.append(f"reconcile {item['ticker']}: ledger {item['ledger']:g}, broker {item['broker']:g} -> {item['action']}")
            if rec["cash"]:
                notes.append(f"reconcile cash: {rec['cash']['difference']:+,.2f} -> {rec['cash']['action']}")
    from spectre.portfolio.performance import buying_brake

    brake = buying_brake(s, portfolio_id, settings.trading_max_drawdown, settings.trading_max_daily_loss)
    if brake:
        notes.append(f"Buying is paused: {brake}. Sales and stop-losses still run.")
    report, actions = None, []
    booked: list[tuple[str, dict]] = []  # (which book, what was done) for the journal
    if market_open:
        report = run_once(s, portfolio_id, route, top_n=top_n, invest=invest, enter=enter, exit_below=exit_below,
                          lookback_minutes=lookback, min_authors=min_authors, dry_run=dry_run, stop_loss=stop_loss or None,
                          min_hold_minutes=min_hold, risk_weighted=risk_weighted, allow_buys=not brake)
        actions += report.actions
        booked += [("stocks", a) for a in report.actions]
        if options:
            from spectre.execution.alpaca import AlpacaClient
            from spectre.signals.options_strategy import run_options_once

            done = run_options_once(s, portfolio_id, getattr(route, "client", None) or AlpacaClient(), route,
                                    lookback_minutes=lookback, dry_run=dry_run, rules=option_rules,
                                    allow_buys=not brake).actions
            actions += done
            booked += [("options", a) for a in done]
    coins = None
    if crypto:
        # Coins cost about half a percent in fees per round trip, so they need a stronger read to
        # get in and are kept longer before a change of mind counts.
        coins = run_once(s, portfolio_id, route, top_n=crypto_top, invest=crypto_invest, enter=max(enter, crypto_enter),
                         exit_below=exit_below, lookback_minutes=lookback, min_authors=min_authors, dry_run=dry_run,
                         asset_classes=CRYPTO, stop_loss=crypto_stop_loss or None, min_hold_minutes=crypto_min_hold,
                         risk_weighted=risk_weighted, allow_buys=not brake)
        actions += coins.actions
        booked += [("coins", a) for a in coins.actions]
    if not dry_run:
        from spectre.portfolio.performance import record_snapshot
        from spectre.signals.journal import record_cycle

        record_snapshot(s, portfolio_id)  # the track record: what it was worth after this cycle
        record_cycle(s, portfolio_id, booked, notes, (report.targets if report else []) + (coins.targets if coins else []))
    return report, coins, actions, notes


@app.command()
def bot(portfolio_id: int,
        top_n: int = typer.Option(5, help="How many names to hold at most"),
        invest: float = typer.Option(0.5, help="Share of the portfolio the stock book may hold"),
        enter: float = typer.Option(0.2, help="Minimum score to buy"),
        exit_below: float = typer.Option(0.0, help="Sell a holding when its score falls to this or lower"),
        lookback: int = typer.Option(60, help="Minutes of conversation to read"),
        min_authors: int = typer.Option(4, help="Ignore names with fewer distinct authors than this"),
        every: float = typer.Option(0.0, help="Minutes between cycles; 0 runs one cycle and stops"),
        dry_run: bool = typer.Option(False, help="Show what it would do without creating any order"),
        broker: str = typer.Option("paper", help="'paper' (built-in simulation) or 'alpaca' (your Alpaca paper account)"),
        options: bool = typer.Option(False, help="Also run the options sleeve: buy calls on the strongest bullish reads, puts on bearish (needs Alpaca keys for option prices)"),
        options_budget: float = typer.Option(0.20, help="Options: share of the portfolio that may sit in option premium"),
        options_per_trade: float = typer.Option(0.03, help="Options: share of the portfolio spent on one new position"),
        options_enter: float = typer.Option(1.0, help="Options: how strong the read must be (absolute score)"),
        options_min_authors: int = typer.Option(10, help="Options: fewest distinct authors behind a read"),
        max_exposure: float = typer.Option(1.0, help="Most market the portfolio may carry, as a multiple of its value, counting options by delta; stops new calls beyond it (0 = no cap)"),
        crypto: bool = typer.Option(False, help="Also run the coin book (trades at any hour)"),
        crypto_invest: float = typer.Option(0.10, help="Crypto: share of the portfolio the coin book may hold"),
        crypto_top: int = typer.Option(3, help="Crypto: how many coins to hold at most"),
        stop_loss: float = typer.Option(0.08, help="Sell a stock that falls this far below its average cost (0 = no stop)"),
        crypto_stop_loss: float = typer.Option(0.12, help="The same for coins, which move more"),
        min_hold: float = typer.Option(60.0, help="Minutes a stock is kept before a change of mind by the crowd can sell it (the stop-loss is not held back)"),
        crypto_min_hold: float = typer.Option(240.0, help="The same for coins, which cost about 0.5% in fees per round trip"),
        crypto_enter: float = typer.Option(0.5, help="Crypto: minimum score to buy (higher than for stocks, because of the fees)"),
        risk_weighted: bool = typer.Option(True, "--risk-weighted/--equal-weighted", help="Size each position by how much the name moves (calmer names larger), or give every name the same dollars"),
        db: str | None = typer.Option(None, "--db")):
    """KAIROS, the trend bot (paper only): buy what the crowd is leaning into, sell what it has turned on."""
    import time as _time

    def cycle() -> None:
        with _session(db) as s:
            r, coins, actions, notes = _kairos_cycle(
                s, portfolio_id, broker, top_n=top_n, invest=invest, enter=enter, exit_below=exit_below, lookback=lookback,
                min_authors=min_authors, dry_run=dry_run, options=options,
                option_rules=_option_rules(options_budget, options_per_trade, options_enter, options_min_authors, max_exposure),
                crypto=crypto, crypto_invest=crypto_invest, crypto_top=crypto_top,
                stop_loss=stop_loss, crypto_stop_loss=crypto_stop_loss, min_hold=min_hold, crypto_min_hold=crypto_min_hold,
                crypto_enter=crypto_enter, risk_weighted=risk_weighted)
        for note in notes:
            console.print(f"[dim]{note}[/]")
        shown = r or coins
        if shown is not None:
            console.print(f"[bold]KAIROS[/] portfolio {portfolio_id}  NAV {_money(shown.nav)}  cash {_money(shown.cash)}"
                          f"{'  [yellow](dry run)[/]' if dry_run else ''}")
        targets = set((r.targets if r else []) + (coins.targets if coins else []))
        signals = sorted((r.signals if r else []) + (coins.signals if coins else []), key=lambda x: -x.score)
        t = Table("ticker", "authors", "posts", "bullish", "bearish", "net", "trending", "price", "score", title="Crowd stance")
        for sg in signals[:18]:
            mark = "[green]buy zone[/]" if sg.ticker in targets else ""
            t.add_row(sg.ticker, str(sg.n_authors), str(sg.n_posts), _pct(sg.bull_share), _pct(sg.bear_share),
                      f"{sg.net:+.0%}", "yes" if sg.trending else "", _fmt_px(sg.price), f"{sg.score:+.2f} {mark}")
        console.print(t)
        if actions:
            t = Table("side", "ticker", "qty", "price", "outcome", "why / detail", title="Actions")
            for a in actions:
                t.add_row(a["side"], a["ticker"], _fmt_qty(a["quantity"]), _fmt_px(a.get("fill_price") or a.get("price")),
                          a["outcome"], (a.get("detail") or a["why"])[:110])
            console.print(t)
        else:
            console.print("No trades this cycle.")

    cycle()
    while every > 0:
        _time.sleep(every * 60)
        cycle()


@app.command()
def autopilot(portfolio_id: int,
              sources: str = typer.Option("bluesky,stocktwits,kalshi,polymarket,trends", help="Comma list of live sources"),
              symbols: str = typer.Option("NVDA,TSLA,SPY,AAPL,AMD,PLTR,MSFT,META,AMZN,QQQ", help="stocktwits symbols to follow"),
              geos: str = typer.Option("US", help="trends: countries"),
              minutes: float = typer.Option(0.0, help="How long to run (0 = until Ctrl-C)"),
              every: float = typer.Option(10.0, help="Minutes between trading decisions"),
              warmup: float = typer.Option(10.0, help="Minutes of data to collect before the first decision"),
              top_n: int = 5, invest: float = 0.5, enter: float = 0.2, exit_below: float = 0.0, lookback: int = 60,
              min_authors: int = 4,
              broker: str = typer.Option("paper", help="'paper' (built-in simulation) or 'alpaca' (your Alpaca paper account)"),
              options: bool = typer.Option(False, help="Also run the options sleeve (bought calls and puts; needs Alpaca keys)"),
              options_budget: float = 0.20, options_per_trade: float = 0.03, options_enter: float = 1.0,
              options_min_authors: int = 10,
              max_exposure: float = typer.Option(1.0, help="Most market the portfolio may carry, as a multiple of its value, counting options by delta; stops new calls beyond it (0 = no cap)"),
              crypto: bool = typer.Option(False, help="Also run the coin book, which trades at any hour"),
              crypto_invest: float = 0.10, crypto_top: int = 3,
              stop_loss: float = typer.Option(0.08, help="Sell a stock that falls this far below its average cost (0 = no stop)"),
              crypto_stop_loss: float = typer.Option(0.12, help="The same for coins"),
              min_hold: float = typer.Option(60.0, help="Minutes a stock is kept before a change of mind can sell it"),
              crypto_min_hold: float = typer.Option(240.0, help="The same for coins"),
              crypto_enter: float = typer.Option(0.5, help="Crypto: minimum score to buy"),
              risk_weighted: bool = typer.Option(True, "--risk-weighted/--equal-weighted", help="Size each position by how much the name moves (calmer names larger), or give every name the same dollars"),
              db: str | None = typer.Option(None, "--db")):
    """Run the whole thing: live data in, a paper trading decision every few minutes.

    Paper only. Every order goes through compliance, the trading limits and the kill switch
    (`spectre halt` from another terminal stops it trading at once)."""
    import asyncio
    import time as _time

    from spectre.marketdata.universe import seed_universe as _seed
    from spectre.signals.pipeline import Pipeline

    engine = make_engine(db or settings.database_url)
    init_db(engine)
    factory = make_session_factory(engine)
    if crypto:
        with factory() as s:
            _seed(s)  # make sure the coins exist before the recogniser is built
        symbols = ",".join(dict.fromkeys(filter(None, symbols.split(",") + CRYPTO_STREAMS.split(","))))
    built = _build_sources(factory, sources, symbols=symbols, geos=geos)
    from spectre.signals import learned
    from spectre.signals.nlp import SentimentModel

    model_file = learned.model_path(db or settings.database_url)

    def retrain() -> SentimentModel:
        """Re-test the learned sentiment model on the tagged posts collected so far, and use
        the blend only while it beats the word list on later posts."""
        try:
            with factory() as s:
                console.print(_sentiment_line(learned.train(s, model_file)))
        except Exception as exc:  # never worth stopping the run for
            console.print(f"[yellow]Sentiment model not retrained ({type(exc).__name__}: {exc}).[/]")
        return SentimentModel(model_file)

    pipe = Pipeline(factory, sentiment=retrain())
    started = _time.monotonic()

    def decide() -> None:
        if _time.monotonic() - started < warmup * 60:
            return
        stamp = _time.strftime("%H:%M:%S")
        try:
            with factory() as s:
                r, coins, actions, notes = _kairos_cycle(
                    s, portfolio_id, broker, top_n=top_n, invest=invest, enter=enter, exit_below=exit_below,
                    lookback=lookback, min_authors=min_authors, options=options,
                    option_rules=_option_rules(options_budget, options_per_trade, options_enter, options_min_authors,
                                               max_exposure),
                    crypto=crypto, crypto_invest=crypto_invest, crypto_top=crypto_top,
                    stop_loss=stop_loss, crypto_stop_loss=crypto_stop_loss, min_hold=min_hold,
                    crypto_min_hold=crypto_min_hold, crypto_enter=crypto_enter, risk_weighted=risk_weighted)
        except Exception as exc:  # one bad cycle (a network blip, a broker error) must not stop the run
            console.print(f"{stamp}  [red]cycle failed[/]: {type(exc).__name__}: {exc}")
            return
        for note in notes:
            console.print(f"{stamp}  [dim]{note}[/]")
        if not actions:
            shown = r or coins
            zone = (r.targets if r else []) + (coins.targets if coins else [])
            console.print(f"{stamp}  no trades" + (f"  (NAV {_money(shown.nav)}, buy zone: {', '.join(zone) or 'none'})" if shown else ""))
        for a in actions:
            console.print(f"{stamp}  {_action_line(a)}")

    console.print(f"KAIROS autopilot ({'Alpaca paper account' if broker == 'alpaca' else 'built-in paper'}) on portfolio {portfolio_id}: reading {', '.join(s.name for s in built)}; "
                  f"first decision {'in under a minute' if warmup <= 0 else f'after {max(warmup, every):g} min'}, then every {every:g} min. Ctrl-C to stop.")
    # With no warm-up asked for, decide soon after starting rather than a whole interval later:
    # a restart on a database that already holds the last hour of posts has what it needs.
    def tidy() -> None:  # a few times a day, so a database that runs for months stops growing
        from spectre.signals.retention import prune as _prune

        with factory() as s:
            r = _prune(s)
        if any(r.values()):
            console.print(f"{_time.strftime('%H:%M:%S')}  [dim]tidied: {r['posts']:,} old posts, {r['price_ticks']:,} ticks, "
                          f"{r['market_snapshots']:,} market snapshots removed[/]")
        pipe.sentiment = retrain()

    def headlines() -> None:  # company news for the dashboard; needs the Alpaca data feed
        if broker != "alpaca":
            return
        from spectre.execution.alpaca import AlpacaClient
        from spectre.signals.news import sync_news

        with factory() as s:
            sync_news(s, AlpacaClient(), sentiment=pipe.sentiment)

    summary = asyncio.run(pipe.run(built, duration_seconds=minutes * 60 if minutes else None,
                                   periodic=[(every * 60, decide), (6 * 3600.0, tidy), (300.0, headlines)],
                                   periodic_first_after=min(45.0, every * 60) if warmup <= 0 else None))
    console.print_json(data=summary)


@app.command()
def alpaca_status(portfolio_id: int | None = typer.Option(None, "--portfolio", help="Compare with this ledger portfolio"),
                  db: str | None = typer.Option(None, "--db")):
    """Your Alpaca paper account: balance, market clock and positions (optionally against the ledger)."""
    from spectre.execution.alpaca import AlpacaClient, AlpacaError
    from spectre.portfolio.positions import value_portfolio

    try:
        client = AlpacaClient()
        acct, clock, held = client.account(), client.clock(), client.positions()
    except AlpacaError as exc:
        console.print(f"[red]Alpaca: {exc}[/]")
        raise typer.Exit(1) from exc
    kind = "paper (fake money)" if client.paper else "[red]LIVE[/]"
    console.print(f"Alpaca {kind}: status {acct.get('status')}, equity {float(acct['equity']):,.2f}, "
                  f"cash {float(acct['cash']):,.2f}, options level {acct.get('options_trading_level')}")
    mult = str(acct.get("multiplier"))
    console.print(f"Buying power {float(acct.get('buying_power') or 0):,.2f}; "
                  + ("margin is [green]off[/] (cash only)" if mult == "1" else f"margin is [yellow]on[/] ({mult}x)"))
    console.print(f"Market is {'[green]open[/]' if clock.get('is_open') else '[yellow]closed[/]'}; "
                  f"next open {clock.get('next_open')}, next close {clock.get('next_close')}")
    ledger: dict[str, float] = {}
    if portfolio_id is not None:
        with _session(db) as s:
            v = value_portfolio(s, portfolio_id)
            ledger = {r.ticker: float(r.quantity) for r in v.positions.itertuples()}
            console.print(f"Ledger portfolio {portfolio_id} '{v.portfolio_name}': NAV {v.total_value:,.2f}, cash {v.cash:,.2f}")
    from spectre.execution.alpaca import position_ticker

    at_broker = {position_ticker(p): p for p in held}
    if not at_broker and not ledger:
        console.print("No positions.")
        return
    t = Table("symbol", "qty at Alpaca", "avg entry", "price", "market value", "unrealised P&L", "qty in ledger", "match")
    for sym in sorted(set(at_broker) | set(ledger)):
        p = at_broker.get(sym)
        bq, lq = (float(p["qty"]) if p else 0.0), ledger.get(sym)
        match = "" if portfolio_id is None else ("[green]yes[/]" if lq is not None and abs(bq - lq) < 1e-6 else "[red]no[/]")
        t.add_row(sym, _fmt_qty(bq), _fmt_px(float(p["avg_entry_price"])) if p else "-",
                  _fmt_px(float(p["current_price"])) if p else "-", f"{float(p['market_value']):,.2f}" if p else "-",
                  f"{float(p['unrealized_pl']):+,.2f}" if p else "-", _fmt_qty(lq) if lq is not None else "-", match)
    console.print(t)


@app.command()
def report(portfolio_id: int | None = typer.Argument(None, help="Default: the portfolio named by SPECTRE_PORTFOLIO (KAIROS)"),
           day: str | None = typer.Option(None, help="YYYY-MM-DD; default today (UTC)"),
           if_closed: bool = typer.Option(False, help="Print only once per day, after the stock market has closed; otherwise print nothing"),
           db: str | None = typer.Option(None, "--db")):
    """The day in one page: value, what the bot did and why, holdings, risk, and anything needing attention."""
    import os
    from datetime import date as _date

    from sqlalchemy import select

    from spectre.models import Portfolio
    from spectre.portfolio import daily

    client = None
    market_open = None
    if settings.alpaca_key_id and settings.alpaca_secret_key:
        from spectre.execution.alpaca import AlpacaClient, AlpacaError

        client = AlpacaClient()
        try:
            market_open = bool(client.clock().get("is_open"))
        except AlpacaError:
            client = None
    with _session(db) as s:
        if portfolio_id is None:
            name = os.environ.get("SPECTRE_PORTFOLIO", "KAIROS")
            portfolio_id = s.execute(select(Portfolio.id).where(Portfolio.name == name)).scalar_one_or_none()
            if portfolio_id is None:
                console.print(f"[red]No portfolio named '{name}'.[/]")
                raise typer.Exit(1)
        which = _date.fromisoformat(day) if day else daily.datetime.now(daily.UTC).date()
        if if_closed and (not daily.session_is_over(market_open=market_open) or daily.already_reported(s, portfolio_id, which)):
            return
        text = daily.render(daily.daily_report(s, portfolio_id, which, client))
        if if_closed:
            daily.mark_reported(s, portfolio_id, which)
    print(text)  # plain text on purpose: it is meant to be pasted into a message


@app.command()
def attention(portfolio_id: int | None = typer.Argument(None, help="Default: the portfolio named by SPECTRE_PORTFOLIO (KAIROS)"),
              db: str | None = typer.Option(None, "--db")):
    """Anything a person should look at: a halt, a brake, a bot that has stopped looking, a
    compliance failure, a ledger that disagrees with the broker. Prints nothing when all is well."""
    import os

    from sqlalchemy import select

    from spectre.models import Portfolio
    from spectre.portfolio import daily

    client = None
    if settings.alpaca_key_id and settings.alpaca_secret_key:
        from spectre.execution.alpaca import AlpacaClient

        client = AlpacaClient()
    with _session(db) as s:
        if portfolio_id is None:
            name = os.environ.get("SPECTRE_PORTFOLIO", "KAIROS")
            portfolio_id = s.execute(select(Portfolio.id).where(Portfolio.name == name)).scalar_one_or_none()
            if portfolio_id is None:
                print(f"No portfolio named '{name}'.")
                raise typer.Exit(1)
        for line in daily.needs_attention(s, portfolio_id, client):
            print("- " + line)


@app.command()
def performance(portfolio_id: int, db: str | None = typer.Option(None, "--db")):
    """Is it making money? Profit and loss since the start, against the S&P 500, and where it came from."""
    from spectre.portfolio.performance import performance as _performance

    with _session(db) as s:
        r = _performance(s, portfolio_id)

    def signed(x: float | None, pct: bool = False) -> str:
        if x is None:
            return "-"
        return f"{x:+.2%}" if pct else f"{x:+,.2f}"

    bench = r["benchmark"]
    console.print(f"[bold]Portfolio {portfolio_id}[/] is worth {r['nav']:,.2f}; {r['put_in']:,.2f} was put in. "
                  f"Profit and loss {signed(r['pnl'])} ({signed(r['return'], True)})"
                  + (f" since {r['since']} UTC." if r["since"] else "."))
    console.print(f"{bench['ticker']} over the same stretch: {signed(bench['return'], True)}; difference {signed(r['excess_return'], True)}. "
                  f"Today {signed(r['day_change'])}. Deepest fall from a high so far: {r['max_drawdown']:.2%} "
                  f"({r['snapshots']} recorded values).")
    t = Table("sleeve", "worth now", "banked", "still open", "fees", "total", "sales", "at a profit", title="Where it came from")
    for x in r["sleeves"]:
        t.add_row(x["sleeve"], f"{x['market_value']:,.2f}", signed(x["realised"]), signed(x["unrealised"]), f"{x['fees']:,.2f}",
                  signed(x["total"]), str(x["closed_trades"]), str(x["winners"]))
    if abs(r["account_fees_and_adjustments"]) >= 0.005:
        t.add_row("Broker fees outside any one trade", "", "", "", "", signed(r["account_fees_and_adjustments"]), "", "")
    console.print(t)
    console.print("[dim]Banked = profit already taken by selling. Still open = at today's prices; it can still change.[/]")


@app.command()
def settlement(portfolio_id: int, db: str | None = typer.Option(None, "--db"),
               as_of: str | None = typer.Option(None, help="YYYY-MM-DD; default today")):
    """Settled and unsettled cash: what has really changed hands, what settles when, and what cannot be sold yet."""
    from datetime import date as _date

    from spectre.portfolio.settlement import backfill_settlement_dates, simulate

    with _session(db) as s:
        backfill_settlement_dates(s)
        st = simulate(s, portfolio_id, _date.fromisoformat(as_of) if as_of else None)
    t = Table("", "amount", title=f"Portfolio {portfolio_id} settlement as of {st.as_of}")
    t.add_row("Cash the ledger shows (every trade counted at once)", f"{st.cash:,.2f}")
    t.add_row("  Settled cash (has actually changed hands)", f"{st.settled_cash:,.2f}")
    t.add_row("  + sale proceeds still to arrive", f"{st.receivable:,.2f}")
    t.add_row("  - purchases still to be paid for", f"{st.payable:,.2f}")
    t.add_row("Settled money not yet committed to a purchase", f"{st.funds_available:,.2f}")
    console.print(t)
    if st.funds_available < -0.005:
        console.print(f"[yellow]{-st.funds_available:,.2f} of purchases rest on sale proceeds that have not settled yet.[/]")
    if st.pending:
        t = Table("settles on", "traded", "side", "ticker", "qty", "cash", title="Still to settle")
        for x in st.pending:
            t.add_row(x["settles_on"], x["traded_on"], x["side"], x["ticker"], _fmt_qty(x["quantity"]), f"{x['amount']:+,.2f}")
        console.print(t)
    else:
        console.print("Nothing is waiting to settle.")
    if st.restricted:
        t = Table("ticker", "qty", "can be sold from", title="On hold: bought with money from a sale that has not settled")
        for x in st.restricted:
            t.add_row(x["ticker"], _fmt_qty(x["quantity"]), x["sell_freely_on"])
        console.print(t)
    recent = st.recent_violations()
    if st.violations:
        t = Table("date", "what happened", title="Good-faith violations on record")
        for v in st.violations:
            t.add_row(v.date.isoformat(), v.describe())
        console.print(t)
    colour = "green" if not recent else "yellow" if len(recent) < 3 else "red"
    console.print(f"[{colour}]{len(recent)} good-faith violation(s) in the last 12 months.[/] "
                  "At three, a real cash account is limited to settled money for 90 days.")


@app.command()
def alpaca_reconcile(portfolio_id: int,
                     apply: bool = typer.Option(False, help="Book the small, explainable differences (fees taken in coin, a few dollars of fees and rounding)"),
                     db: str | None = typer.Option(None, "--db")):
    """Check the ledger against Alpaca's own figures, position by position and in cash."""
    from spectre.execution.alpaca import AlpacaClient, AlpacaError, reconcile

    try:
        with _session(db) as s:
            rec = reconcile(s, AlpacaClient(), portfolio_id, apply=apply)
    except AlpacaError as exc:
        console.print(f"[red]Alpaca: {exc}[/]")
        raise typer.Exit(1) from exc
    if not rec["positions"] and not rec["cash"]:
        console.print("[green]Ledger and broker agree[/]: every position and the cash balance match.")
        return
    t = Table("item", "ledger", "broker", "difference", "what it is")
    for item in rec["positions"]:
        t.add_row(item["ticker"], f"{item['ledger']:,.6g}", f"{item['broker']:,.6g}", f"{item['difference']:+,.6g}", item["action"])
    if rec["cash"]:
        c = rec["cash"]
        t.add_row("cash", f"{c['ledger']:,.2f}", f"{c['broker']:,.2f}", f"{c['difference']:+,.2f}", c["action"])
    console.print(t)
    if not rec["clean"]:
        console.print("[red]Unexplained differences were left alone[/]: they need a person to look at them.")


@app.command()
def alpaca_margin(multiplier: str | None = typer.Argument(None, help="1 = cash only (no borrowing); 2 or 4 = margin on. Omit to just show it.")):
    """Show or set how much the Alpaca account may borrow. `spectre alpaca-margin 1` makes it cash only."""
    from spectre.execution.alpaca import AlpacaClient, AlpacaError

    try:
        client = AlpacaClient()
        if multiplier is not None:
            if multiplier not in ("1", "2", "4"):
                raise typer.BadParameter("multiplier must be 1, 2 or 4")
            client.set_configurations(max_margin_multiplier=multiplier)
        acct = client.account()
    except AlpacaError as exc:
        console.print(f"[red]Alpaca: {exc}[/]")
        raise typer.Exit(1) from exc
    mult = str(acct.get("multiplier"))
    console.print(f"Margin multiplier {mult}: " + ("cash only, nothing can be borrowed" if mult == "1" else "the account can borrow")
                  + f". Cash {float(acct['cash']):,.2f}, buying power {float(acct.get('buying_power') or 0):,.2f}.")


@app.command()
def prune(days: int = typer.Option(30, help="Keep raw posts and their price ticks this many days"),
          market_days: int = typer.Option(7, help="Keep every prediction-market snapshot this many days; older ones are thinned to one a day"),
          db: str | None = typer.Option(None, "--db")):
    """Trim old raw data so a long-running database stops growing. The ledger and audit trail are never touched."""
    from spectre.signals.retention import prune as _prune

    with _session(db) as s:
        r = _prune(s, days, market_days)
    console.print(f"Removed {r['posts']:,} posts, {r['price_ticks']:,} price ticks and {r['market_snapshots']:,} market snapshots.")


@app.command()
def prices_backfill(days: int = typer.Option(750, help="How many calendar days of daily history to load"),
                    tickers: str = typer.Option("", help="Comma list; default is every real stock, fund and coin in the book"),
                    everything: bool = typer.Option(False, "--all", help="Also securities outside the curated real-world universe"),
                    db: str | None = typer.Option(None, "--db")):
    """Load daily price history from Alpaca so volatility and value at risk work on real holdings."""
    from spectre.execution.alpaca import AlpacaClient, AlpacaError, backfill_prices

    try:
        with _session(db) as s:
            r = backfill_prices(s, AlpacaClient(), days, [t.strip() for t in tickers.split(",") if t.strip()] or None, everything)
    except AlpacaError as exc:
        console.print(f"[red]Alpaca: {exc}[/]")
        raise typer.Exit(1) from exc
    console.print(f"Stored {r['prices']:,} daily prices for {r['securities']} securities, back to {r['from']}.")
    if r["missing"]:
        console.print(f"[yellow]No history returned for: {', '.join(r['missing'])}[/]")


@app.command()
def prices_sync(tickers: str = typer.Option("", help="Comma list; default is every US stock and fund in the book"),
                db: str | None = typer.Option(None, "--db")):
    """Pull the latest traded prices from Alpaca into the book."""
    from spectre.execution.alpaca import AlpacaClient, AlpacaError, sync_prices

    with _session(db) as s:
        try:
            n = sync_prices(s, AlpacaClient(), [t.strip() for t in tickers.split(",") if t.strip()] or None)
        except AlpacaError as exc:
            console.print(f"[red]Alpaca: {exc}[/]")
            raise typer.Exit(1) from exc
    console.print(f"Priced {n} securities from Alpaca.")


@app.command()
def options(ticker: str,
            expiry: str | None = typer.Option(None, help="YYYY-MM-DD; default is the nearest expiry at least a week out"),
            kind: str | None = typer.Option(None, "--type", help="call or put; default both"),
            near: float = typer.Option(0.10, help="Only strikes within this fraction of the stock price"),
            db: str | None = typer.Option(None, "--db")):
    """Option chain for a stock from Alpaca: bid, ask, implied volatility and greeks per contract."""
    from datetime import timedelta

    from spectre.execution.alpaca import AlpacaClient, AlpacaError

    ticker = ticker.upper()
    try:
        client = AlpacaClient()
        spot = client.latest_trades([ticker]).get(ticker)
        if spot is None:
            console.print(f"[red]No recent trade for {ticker}[/]")
            raise typer.Exit(1)
        price = spot[0]
        lo, hi = round(price * (1 - near), 2), round(price * (1 + near), 2)
        if expiry:
            chain = client.option_chain(ticker, expiration_date=date.fromisoformat(expiry), option_type=kind,
                                        strike_price_gte=lo, strike_price_lte=hi)
        else:
            start = date.today() + timedelta(days=7)
            chain = client.option_chain(ticker, expiration_date_gte=start, expiration_date_lte=start + timedelta(days=45),
                                        option_type=kind, strike_price_gte=lo, strike_price_lte=hi)
            if chain:
                first = min(q.expiration for q in chain)
                chain = [q for q in chain if q.expiration == first]
    except AlpacaError as exc:
        console.print(f"[red]Alpaca: {exc}[/]")
        raise typer.Exit(1) from exc
    if not chain:
        console.print(f"No contracts returned for {ticker} in that range.")
        return
    console.print(f"[bold]{ticker}[/] last {price:,.2f}; expiry {chain[0].expiration}; strikes {lo:,.2f} to {hi:,.2f}; "
                  f"{settings.alpaca_option_feed} prices")

    def f(x, fmt="{:,.2f}"):
        return "-" if x is None else fmt.format(x)

    t = Table("strike", "type", "bid", "ask", "mid", "implied vol", "delta", "theta", "volume", "contract")
    for q in chain:
        t.add_row(f"{q.strike:,.2f}", q.type, f(q.bid), f(q.ask), f(q.mid), f(q.implied_volatility, "{:.1%}"),
                  f(q.delta, "{:+.2f}"), f(q.theta, "{:+.3f}"), f(q.volume, "{:,}"), q.symbol)
    console.print(t)


@app.command()
def halt(reason: str = typer.Argument("manual halt"), actor: str = "cli", db: str | None = typer.Option(None, "--db")):
    """Kill switch: stop every order from reaching any broker until `spectre resume`."""
    from spectre.execution.guard import set_halt

    with _session(db) as s:
        set_halt(s, True, actor, reason)
    console.print(f"[red]Trading halted[/]: {reason}")


@app.command()
def resume(actor: str = "cli", db: str | None = typer.Option(None, "--db")):
    """Lift the kill switch."""
    from spectre.execution.guard import set_halt

    with _session(db) as s:
        set_halt(s, False, actor)
    console.print("[green]Trading resumed[/]")


@app.command()
def limits(db: str | None = typer.Option(None, "--db")):
    """Show the trading limits in force and whether trading is halted."""
    from spectre.execution.guard import TradingLimits, halt_state

    lim = TradingLimits.from_settings()
    with _session(db) as s:
        h = halt_state(s)
        s.commit()
        t = Table("setting", "value")
        t.add_row("mode", lim.mode)
        t.add_row("halted", f"[red]yes: {h.reason}[/]" if h.halted else "no")
        t.add_row("max per order", _money(lim.max_order_notional))
        t.add_row("max per day", _money(lim.max_daily_notional))
        t.add_row("max orders per day", str(lim.max_orders_per_day))
        t.add_row("max position size", _pct(lim.max_position_weight))
        t.add_row("live orders need approval", "yes" if lim.require_approval else "no")
        t.add_row("allowed symbols", ", ".join(sorted(lim.allowed_symbols)) or "any")
    console.print(t)


@app.command()
def serve(host: str = "127.0.0.1", port: int = 8000, db: str | None = typer.Option(None, "--db"),
          reload: bool = False):
    """Run the REST API (docs at /docs)."""
    import os

    import uvicorn

    if db:
        os.environ["SPECTRE_DATABASE_URL"] = db
    uvicorn.run("spectre.api.app:app", host=host, port=port, reload=reload)


@app.command()
def run(host: str = typer.Option("127.0.0.1", envvar="SPECTRE_HOST", help="0.0.0.0 to be reachable from outside; needs SPECTRE_DASHBOARD_PASSWORD"),
        port: int = typer.Option(8000, envvar="PORT"),
        portfolio: str = typer.Option("KAIROS", envvar="SPECTRE_PORTFOLIO", help="Portfolio to trade; created if it does not exist"),
        cash: float = typer.Option(100_000.0, envvar="SPECTRE_START_CASH", help="Starting cash for the built-in paper broker (an Alpaca account brings its own)"),
        every: float = typer.Option(10.0, envvar="SPECTRE_EVERY", help="Minutes between decisions"),
        invest: float = typer.Option(0.70, envvar="SPECTRE_INVEST", help="Share of the portfolio for stocks"),
        options: bool = typer.Option(True, envvar="SPECTRE_OPTIONS", help="Trade bought calls and puts (Alpaca only)"),
        options_budget: float = typer.Option(0.20, envvar="SPECTRE_OPTIONS_BUDGET"),
        max_exposure: float = typer.Option(1.0, envvar="SPECTRE_MAX_EXPOSURE", help="Most market the portfolio may carry, as a multiple of its value, counting options by delta; stops new calls beyond it (0 = no cap)"),
        crypto: bool = typer.Option(True, envvar="SPECTRE_CRYPTO", help="Trade coins, around the clock"),
        crypto_invest: float = typer.Option(0.10, envvar="SPECTRE_CRYPTO_INVEST"),
        stop_loss: float = typer.Option(0.08, envvar="SPECTRE_STOP_LOSS", help="Stocks: sell this far below average cost (0 = off)"),
        crypto_stop_loss: float = typer.Option(0.12, envvar="SPECTRE_CRYPTO_STOP_LOSS"),
        min_hold: float = typer.Option(60.0, envvar="SPECTRE_MIN_HOLD", help="Stocks: minutes held before a change of mind can sell"),
        crypto_min_hold: float = typer.Option(240.0, envvar="SPECTRE_CRYPTO_MIN_HOLD"),
        crypto_enter: float = typer.Option(0.5, envvar="SPECTRE_CRYPTO_ENTER", help="Crypto: minimum score to buy"),
        risk_weighted: bool = typer.Option(True, "--risk-weighted/--equal-weighted", envvar="SPECTRE_RISK_WEIGHTED", help="Size positions by how much each name moves"),
        min_authors: int = typer.Option(8, envvar="SPECTRE_MIN_AUTHORS"),
        lookback: int = typer.Option(45, envvar="SPECTRE_LOOKBACK"),
        symbols: str = typer.Option("NVDA,TSLA,SPY,AAPL,AMD,PLTR,MSFT,META,AMZN,QQQ,GOOGL,INTC", envvar="SPECTRE_SYMBOLS"),
        require_alpaca: bool = typer.Option(False, envvar="SPECTRE_REQUIRE_ALPACA", help="Without Alpaca credentials, only listen and show the dashboard: do not start a simulated book in the real one's place"),
        db: str | None = typer.Option(None, "--db")):
    """Everything in one process, for a machine that stays on: the dashboard and API, the live
    feeds, and KAIROS deciding every few minutes. Paper only.

    With Alpaca keys configured it trades your Alpaca paper account (and, on a fresh database,
    starts from what that account already holds); without them it uses the built-in simulation."""
    import os
    import threading
    import time as _time

    import uvicorn
    from sqlalchemy import select

    from spectre.marketdata.universe import seed_universe as _seed
    from spectre.models import Portfolio

    local = host in ("127.0.0.1", "localhost", "::1")
    if not local and not settings.dashboard_password:
        console.print("[red]Refusing to listen on a public address without a password.[/] The API can place orders. "
                      "Set SPECTRE_DASHBOARD_PASSWORD, or use --host 127.0.0.1.")
        raise typer.Exit(1)
    if db:
        os.environ["SPECTRE_DATABASE_URL"] = db
        settings.database_url = db
    use_alpaca = bool(settings.alpaca_key_id and settings.alpaca_secret_key)
    if not use_alpaca:
        # No keys in the settings: the host may still supply them (a saved network secret that
        # is added to every request to Alpaca). One call to the account tells.
        from spectre.execution.alpaca import AlpacaClient as _Probe

        use_alpaca = _Probe().authorised()
        if use_alpaca:
            console.print("Alpaca credentials are supplied by this environment.")

    listen_only = require_alpaca and not use_alpaca
    warm = False
    with _session(db) as s:
        _seed(s)
        from sqlalchemy import func

        from spectre.signals.models import SocialPost
        from spectre.signals.sources.base import utcnow as _utcnow

        newest = s.execute(select(func.max(SocialPost.posted_at))).scalar_one_or_none()
        warm = newest is not None and (_utcnow() - newest).total_seconds() < lookback * 60 / 2
        pf = s.execute(select(Portfolio).where(Portfolio.name == portfolio)).scalar_one_or_none()
        if pf is None and listen_only:
            pid = None
        elif pf is None:
            pf = _new_trading_portfolio(s, portfolio, None if use_alpaca else cash)
            console.print(f"Created portfolio {pf.id} '{portfolio}'.")
        if pf is not None:
            pid = pf.id
        if use_alpaca:
            from spectre.execution.alpaca import AlpacaClient, adopt_account, rebuild_ledger

            client = AlpacaClient()
            if settings.alpaca_cash_only and str(client.account().get("multiplier")) != "1":
                client.set_configurations(max_margin_multiplier="1")
                console.print("Cash only: margin switched off at Alpaca.")
            # A fresh database: rebuild the books from the broker's record of every fill, or,
            # if that record does not add up to what the account holds, start from its positions.
            built = rebuild_ledger(s, client, pid)
            if built["rebuilt"]:
                console.print(f"Rebuilt the ledger from Alpaca's records: {built['fills']} fills in {built['orders']} orders, "
                              f"{len(built['positions'])} positions; "
                              + ("it agrees with the broker." if built["clean"] else "[yellow]some differences remain[/].")
                              + (f" Not understood: {', '.join(built['not_understood'])}." if built["not_understood"] else ""))
            elif built["reason"] != "the ledger already has history":
                console.print(f"[yellow]Could not rebuild from fills ({built['reason']}); starting from the positions instead.[/]")
                took = adopt_account(s, client, pid)
                if took["adopted"]:
                    console.print(f"Picked up the Alpaca account: {len(took['positions'])} positions, cash {took['cash']:,.2f}.")
            try:  # price history for the risk numbers; cheap, and safe to repeat on every start
                from spectre.execution.alpaca import backfill_prices

                hist = backfill_prices(s, client)
                console.print(f"Price history: {hist['prices']:,} daily prices for {hist['securities']} securities.")
            except Exception as exc:
                console.print(f"[yellow]Could not load price history ({type(exc).__name__}: {exc}); risk numbers may be missing.[/]")

    from spectre.api.app import create_app

    server = uvicorn.Server(uvicorn.Config(create_app(), host=host, port=port, log_level="warning"))
    threading.Thread(target=server.run, daemon=True, name="spectre-api").start()
    where = f"http://localhost:{port}/" if local else f"port {port} of this machine's address"
    doing = ("[yellow]listening only: no Alpaca credentials here, so nothing is traded[/]" if listen_only else
             f"KAIROS trading portfolio {pid} on {'the Alpaca paper account' if use_alpaca else 'the built-in paper broker'}")
    console.print(f"[bold]SPECTRE[/] is up: dashboard at {where}"
                  f"{' (password protected)' if settings.dashboard_password else ''}; {doing}.")

    while True:  # the feeds and the bot; if they ever fall over, start them again
        try:
            if listen_only:
                ingest(sources="bluesky,stocktwits,kalshi,polymarket,trends", minutes=0.0, topic_window=15, bar_window=60,
                       preset="finance", sample=1.0, keywords="", symbols=symbols, geos="US", feeds="", db=db)
                break
            # A database that already holds the last stretch of posts needs no warm-up.
            autopilot(portfolio_id=pid, sources="bluesky,stocktwits,kalshi,polymarket,trends", symbols=symbols, geos="US",
                      minutes=0.0, every=every, warmup=0.0 if warm else min(every, 10.0), top_n=5, invest=invest, enter=0.2, exit_below=0.0,
                      lookback=lookback, min_authors=min_authors, broker="alpaca" if use_alpaca else "paper",
                      options=options and use_alpaca, options_budget=options_budget, options_per_trade=0.03,
                      options_enter=1.0, options_min_authors=10, max_exposure=max_exposure, crypto=crypto,
                      crypto_invest=crypto_invest, crypto_top=3, stop_loss=stop_loss, crypto_stop_loss=crypto_stop_loss,
                      min_hold=min_hold, crypto_min_hold=crypto_min_hold, crypto_enter=crypto_enter,
                      risk_weighted=risk_weighted, db=db)
            break  # it only returns when asked to stop
        except KeyboardInterrupt:
            break
        except Exception as exc:
            console.print(f"[red]KAIROS stopped[/]: {type(exc).__name__}: {exc}. Restarting in 30 seconds.")
            _time.sleep(30)


if __name__ == "__main__":
    app()
