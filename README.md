# Lantern

Portfolio management, risk analytics, pre-trade compliance, order management and an
alternative-data **signals** layer (public conversation + prediction markets) on **one shared
book of record**. Every module reads the same securities, prices, FX, trades and cash flows, so the
portfolio manager, the risk team, compliance and the trading desk never disagree about what is held.

```
                    ┌───────────────────────────────────────────────┐
                    │              Book of record (SQL)             │
                    │  securities · prices · fx · factor returns    │
                    │  portfolios · cash flows · trades · orders    │
                    │  compliance rules & checks · audit events     │
                    └───────┬──────────┬──────────┬──────────┬──────┘
                            │          │          │          │
                   ┌────────▼───┐ ┌────▼─────┐ ┌──▼───────┐ ┌▼────────────┐
                   │ Portfolio  │ │   Risk   │ │Compliance│ │   Trading   │
                   │ positions  │ │ VaR / ES │ │ rules    │ │ orders      │
                   │ exposures  │ │ stress   │ │ pre-trade│ │ fills       │
                   │ active wts │ │ factors  │ │ post-trd │ │ blotter     │
                   │ what-if    │ │ bonds    │ │ history  │ │ audit       │
                   └────────────┘ └──────────┘ └──────────┘ └─────────────┘
                            │          │          │          │
                    ┌───────▼──────────▼──────────▼──────────▼──────┐
                    │          REST API (FastAPI)  ·  CLI            │
                    └───────────────────────────────────────────────┘
```

Positions are **never stored**. They are derived from the trade ledger and cash flows at any as-of
date, so there is exactly one source of truth and point-in-time reporting comes for free.

## Quick start

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

lantern seed-demo            # 21 securities, 3y of prices, 2 portfolios, rules, orders -> ./lantern.db
lantern portfolios
lantern positions 1
lantern exposures 1 --by sector
lantern risk 1               # VaR x3, component VaR, stress, factor model, bond analytics
lantern compliance 1
lantern orders
lantern serve                # REST API with interactive docs at http://127.0.0.1:8000/docs
```

Point at another database with `--db postgresql://...` or `LANTERN_DATABASE_URL=...`. SQLite is the
default for development; the schema is plain SQLAlchemy and runs unchanged on Postgres.

Run the tests with `pytest` (57 tests, ~1 min; most of it is seeding synthetic social history).
Lint with `ruff check lantern tests`.

## What each module does

### Portfolio (`lantern/portfolio`)
- `value_portfolio(session, portfolio_id, as_of)` → holdings from the ledger, latest prices on or
  before `as_of`, FX-converted to the portfolio's base currency, weights relative to total value
  including cash. Bonds are quoted per 100 face (`multiplier = 0.01`), quantity is face amount.
- `exposure_by(valued, dimension)` for `asset_class | sector | country | currency | issuer`.
- `active_weights` / `active_exposures` versus a benchmark (security-level or bucketed).
- `apply_trades(session, valued, [ProposedTrade...])` – what-if analysis that never touches the ledger.

### Risk (`lantern/risk`)
- **VaR / Expected Shortfall** by three methods: historical, parametric (variance–covariance),
  Monte Carlo (Cholesky, seeded). Square-root-of-time horizon scaling. Returns are computed in base
  currency so FX risk is included.
- **Component VaR**: Euler decomposition of parametric VaR; components sum to the total.
- **Stress tests**: additive shocks by asset class / sector / country / currency / ticker, plus
  parallel rate shifts applied through each bond's modified duration. Seven predefined scenarios;
  custom scenarios via the API.
- **Factor model**: OLS betas against stored factor returns, portfolio factor exposures, and a
  systematic / idiosyncratic variance decomposition with per-factor contributions.
- **Fixed income**: price ⇄ yield, Macaulay and modified duration, convexity, DV01.

### Compliance (`lantern/compliance`)
Rules live in the database, scoped to one portfolio or firm-wide, each `HARD` (blocks) or `SOFT`
(warns). Built-in rule types:

| type | params |
|---|---|
| `max_position_weight` | `limit`, `exclude_asset_classes` |
| `max_group_weight` | `dimension`, `limit`, `bucket` (optional), `include_cash` |
| `min_group_weight` | `dimension`, `bucket`, `limit` |
| `max_issuer_weight` | `limit`, `exclude_sectors` (e.g. exempt `Government`) |
| `restricted_list` | `tickers` |
| `min_cash_weight` / `max_cash_weight` | `limit` |
| `no_short_positions` / `no_negative_cash` | – |

Adding a rule type is one decorated function in `rules.py`. An unknown rule type evaluates as a hard
breach rather than silently passing.

**Pre-trade logic**: breaches are evaluated before and after the proposed trade. A hard breach that
is *introduced or worsened* blocks the order. A breach that already existed and is not made worse
is reported but does not block, so a portfolio already over a limit can still trade back into line.
Every check is recorded in `compliance_checks`.

### Trading (`lantern/trading`)
`create_order` runs pre-trade compliance and returns the order as `APPROVED` or `REJECTED` (with
the breach messages as the reason). `fill_order` accepts partial fills, enforces limit prices, writes
a `Trade` to the ledger, and tracks average fill price. `cancel_order`, `blotter`. Every status
transition writes an `audit_events` row with actor and detail.

### Signals (`lantern/signals`) — what the crowd is saying, made tradeable

```
sources ──► screening ──► NLP ──► store ──► aggregation ──► signals ──► backtest / paper strategy
bluesky     bots, spam    sentiment          topic bubbles   z-scores      IC, long/short, OMS orders
reddit      bursts        fear vocabulary    sentiment bars                      │
stocktwits  duplicates    ticker + alias     fear index                          ▼
rss, x      coordination  extraction         market snapshots              /dashboard (live viewer)
kalshi
polymarket
```

- **Sources** (`sources/`): Bluesky public firehose (Jetstream websocket, no key), Reddit, Stocktwits,
  RSS news, X recent search (needs a paid bearer token), Kalshi and Polymarket market data, plus
  `synthetic` (offline demo stream) and `replay` (JSONL recordings). Adding a source is one class
  with an `async run(emit, stop)`.
  *The live adapters are written to the documented APIs but have not been exercised from this
  repository's build environment, which has no outbound network.* Facebook and Instagram do not
  expose public conversation to third parties and are deliberately absent.
- **Screening** (`screening.py`): a post's quality is the product of independent heuristics —
  text shape (stuffing, link-only, shouting), author burst rate, self-duplication (SimHash),
  cross-author coordination (same text from many accounts in minutes), and account metadata when
  the source provides it. Below 0.35 a post is kept but excluded from every aggregate, so the
  screening itself is auditable. On the demo stream the bot population is caught with zero human
  posts screened out.
- **NLP** (`nlp.py`): VADER with a finance lexicon, a fear vocabulary, cashtag + company-name
  extraction mapped to the securities table, and topic clustering (agglomerative on TF-IDF cosine
  for ordinary windows, mini-batch k-means for firehose-sized ones).
- **Aggregation** (`aggregate.py`): per-window **topic bubbles** (volume, unique authors, sentiment,
  fear share, velocity vs. the matching topic in the previous window), per-security **sentiment
  bars** with attention and sentiment z-scores against the security's own history, a **fear
  index**, and prediction-market snapshots with 24h change.
- **Signals & evaluation** (`signals.py`): daily signal matrix; **information coefficient** (daily
  cross-sectional rank correlation with forward returns, with t-stat and hit rate) and a
  **long/short backtest**; a **paper strategy** that trades the top names inside a sleeve of a
  portfolio *through the OMS*, so compliance can reject it like any other order.

```bash
lantern seed-social                  # synthetic history aligned to the demo prices (daily bubbles + bars)
lantern bubbles · lantern sentiment · lantern markets
lantern backtest                     # does the signal predict returns? IC + long/short
lantern paper-trade 2 --fill         # trade it on paper through compliance
lantern ingest --sources synthetic --minutes 5 --topic-window 1   # live pipeline, then open /dashboard
lantern ingest --sources bluesky,kalshi,polymarket --keywords stocks,market,fed   # real data (needs network)
```

**On "edge".** The synthetic stream has a dial, `--ic` (default 0.03, roughly what good
alternative data delivers), that sets how much next-day return leaks into post sentiment. The
tests check that the backtester finds it when it is there and finds nothing when it is zero. On
real data the edge is whatever the IC says it is; the tooling is built so you find that out
before any capital does.

**Privacy and licensing.** Only aggregates leave the signals layer. Author identity is reduced
to a salted hash used for screening and de-duplication; no handles, names or profiles are stored,
and post text is kept only for the aggregation window. Platform terms generally forbid
redistributing raw content; derived aggregates (sentiment, attention, topic velocity) are the
sellable product, and a data-licensing review is still part of commercialising them.

## REST API

Start with `lantern serve` and open `/docs`. Main endpoints:

```
GET  /portfolios/{id}/positions?as_of=            valued holdings
GET  /portfolios/{id}/exposures?dimension=sector  bucketed exposure
GET  /portfolios/{id}/active?dimension=           vs benchmark (security level if omitted)
POST /portfolios/{id}/whatif                      before/after for proposed trades
GET  /portfolios/{id}/risk/report                 everything below in one call
GET  /portfolios/{id}/risk/var?confidence=&horizon_days=
GET  /portfolios/{id}/risk/stress                 predefined scenarios
POST /portfolios/{id}/risk/stress                 custom scenarios
GET  /portfolios/{id}/risk/factors
GET  /portfolios/{id}/risk/fixed-income
GET  /portfolios/{id}/compliance                  post-trade check
POST /portfolios/{id}/compliance/pre-trade        dry run, nothing recorded
GET  /portfolios/{id}/compliance/history
GET/POST /compliance/rules, PATCH /compliance/rules/{id}, GET /compliance/rule-types
POST /orders  ·  GET /orders  ·  GET /orders/{id}  ·  POST /orders/{id}/fills  ·  POST /orders/{id}/cancel
GET/POST /securities  ·  POST /prices  ·  POST /fx  ·  GET/POST /benchmarks
POST /portfolios/{id}/trades (book external trades)  ·  POST /portfolios/{id}/cashflows
GET  /audit
GET  /dashboard                                   live signals viewer (bubbles, sentiment, markets, fear)
GET  /signals/status · /signals/bubbles · /signals/bubbles/history?hours=
GET  /signals/sentiment · /signals/sentiment/{ticker} · /signals/fear · /signals/markets
GET  /signals/backtest?start=&end=&horizon=&signal=
POST /signals/paper-trade/{portfolio_id}?top_n=&sleeve=&fill=
```

Errors map to HTTP status: not found → 404, bad input → 400, order-state conflicts → 409.

## Demo data

`lantern seed-demo` builds a deterministic universe: 12 US equities across 9 sectors, 3 EUR
equities, 4 bonds (two Treasuries, an IG corporate, a HY corporate), a commodity ETF and one
restricted tobacco name. Prices are generated from a **known** five-factor model (market, rates,
credit, size, EURUSD), which is what lets the test suite check that the factor estimator recovers
the betas that produced the data. Two portfolios (a global balanced fund against a 60/40 benchmark,
a US growth fund against an equal-weight index), eleven compliance rules, and three orders in
different states (approved, rejected by the restricted list, filled).

Replace it with real data by loading `securities`, `prices`, `fx_rates`, `cash_flows` and `trades`
through the API or directly into the tables.

## Configuration

Environment variables, all prefixed `LANTERN_`: `DATABASE_URL`, `BASE_CURRENCY`, `VAR_CONFIDENCE`
(0.99), `VAR_HORIZON_DAYS` (1), `LOOKBACK_DAYS` (500), `MC_SIMULATIONS` (20000), `MC_SEED` (42).

## Design notes

- **Single data model.** The reason integrated platforms win over best-of-breed point tools is that
  risk, compliance and trading all see the same positions at the same instant. Lantern gets that by
  construction: there is no positions table to fall out of sync.
- **Point-in-time everywhere.** Every valuation, exposure and risk call takes `as_of`; trades dated
  after it are ignored, prices are the latest on or before it.
- **Compliance is a gate, not a report.** Orders cannot be filled unless they were approved, and
  approval means the pre-trade check ran and was recorded.
- **Audit by default.** Order transitions, rule changes, booked trades and cash flows all write
  `audit_events`.

## Roadmap

Next steps in rough priority order: run the live source adapters against the real APIs and
record a replay fixture; extend the dashboard to exposures, risk and the blotter; real market-data
adapters; a transformer sentiment model calibrated on Stocktwits labels; performance attribution
(Brinson, and factor-based); settlement and custodian reconciliation; multi-user auth with roles
(PM / trader / compliance officer); scheduled end-of-day risk and compliance runs with alerting;
Postgres migrations via Alembic; a data-licensing review before selling derived signals.
