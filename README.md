# SPECTRE

**S**ignal **P**rocessing, **E**xecution, **C**ompliance, **T**rading & **R**isk **E**ngine.

| codename | part | where |
|---|---|---|
| **SPECTRE** | the whole system | this repository |
| **KAIROS** | the trading bot (Greek: *the decisive moment*) | `spectre/signals/strategy.py`, `spectre/signals/options_strategy.py`, `spectre bot`, `spectre autopilot` |
| **WRAITH** | crowd listening: sources, screening, topics, sentiment | `spectre/signals` |
| **RAVEN** | risk analytics | `spectre/risk` |
| **AEGIS** | compliance rules, trading limits, kill switch | `spectre/compliance`, `spectre/execution` |
| **REAPER** | order routing and brokers | `spectre/trading`, `spectre/execution/brokers.py` |

**Status, plainly.** Live data flows from five social and prediction-market sources, plus the
Treasury yield curve, FRED credit spreads and Alpaca prices and option chains. KAIROS trades
stocks, bought options and coins on paper only, either in the built-in simulation or through an
Alpaca paper account, with cash only (no borrowing), never an uncovered option, and settlement
simulated so it behaves like a real cash account. Nothing here has a demonstrated edge on real
data yet, and no live (real-money) broker exists in the code.

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

spectre seed-demo            # 21 securities, 3y of prices, 2 portfolios, rules, orders -> ./spectre.db
spectre portfolios
spectre positions 1
spectre exposures 1 --by sector
spectre risk 1               # VaR x3, component VaR, stress, factor model, bond analytics
spectre compliance 1
spectre orders
spectre serve                # REST API with interactive docs at http://127.0.0.1:8000/docs
```

Point at another database with `--db postgresql://...` or `SPECTRE_DATABASE_URL=...`. SQLite is the
default for development; the schema is plain SQLAlchemy and runs unchanged on Postgres.

Run the tests with `pytest` (about 150 tests, ~35 s; most of it is seeding synthetic social
history). Lint with `ruff check spectre tests`.

## Running it nonstop

`spectre run` is everything in one process: the dashboard and API, the live feeds, and KAIROS
deciding every ten minutes. It creates the portfolio if it does not exist. With Alpaca paper
keys it trades that account, switches margin off, and on a fresh database starts from what the
account already holds; without keys it uses the built-in simulation. If the feeds or the bot
fall over they are restarted.

**On your own computer** (Windows, Mac or Linux; needs Python 3.11 or newer and Git):

```bash
git clone https://github.com/agentzomboidpps/party-panic && cd party-panic
git checkout claude/quirky-hopper-5yk8zk   # until this branch is merged into the main one
pip install -e .
# optional: your Alpaca paper keys, in a file named .env in this folder
#   SPECTRE_ALPACA_KEY_ID=PK...
#   SPECTRE_ALPACA_SECRET_KEY=...
spectre run                  # then open http://localhost:8000
```

It only runs while that window is open and the computer is awake.

**On a cloud host.** The `Dockerfile` builds one container that runs `spectre run`. Any host
that can run a container with a small persistent disk will do. It needs:

| setting | what to put there |
|---|---|
| `SPECTRE_DASHBOARD_PASSWORD` | a password you choose. Required: `run` refuses to listen on a public address without one, because the API can place orders. The browser asks for it once; any user name works. |
| `SPECTRE_ALPACA_KEY_ID`, `SPECTRE_ALPACA_SECRET_KEY` | your Alpaca **paper** keys, entered in the host's secrets settings, never in the repository |
| a disk mounted at `/data` | the database lives there, so history survives restarts and new versions |
| `PORT` | most hosts set this themselves; the default is 8000 |

Optional: `SPECTRE_INVEST` (0.70), `SPECTRE_OPTIONS` (true), `SPECTRE_OPTIONS_BUDGET` (0.20),
`SPECTRE_MAX_EXPOSURE` (1.0), `SPECTRE_CRYPTO` (true), `SPECTRE_CRYPTO_INVEST` (0.10), `SPECTRE_STOP_LOSS` (0.08),
`SPECTRE_CRYPTO_STOP_LOSS` (0.12), `SPECTRE_EVERY` (10 minutes),
`SPECTRE_SYMBOLS`, `SPECTRE_PORTFOLIO` (KAIROS). `GET /health` needs no password, for the
host's health check.

Checked: the image builds, starts, serves the dashboard behind the password and keeps its
database on the volume. Not yet checked: a deployment on a public host.

## What each module does

### Portfolio (`spectre/portfolio`)
- `value_portfolio(session, portfolio_id, as_of)` → holdings from the ledger, latest prices on or
  before `as_of`, FX-converted to the portfolio's base currency, weights relative to total value
  including cash. Bonds are quoted per 100 face (`multiplier = 0.01`), quantity is face amount.
- `exposure_by(valued, dimension)` for `asset_class | sector | country | currency | issuer`.
- `active_weights` / `active_exposures` versus a benchmark (security-level or bucketed).
- `apply_trades(session, valued, [ProposedTrade...])` – what-if analysis that never touches the ledger.
- **Settlement (`portfolio/settlement.py`).** A trade is agreed today and the money moves later:
  stocks, funds and options settle the next business day (two days before 28 May 2024, three
  before September 2017), coins at once; weekends and exchange holidays are worked out, not
  looked up. `simulate` replays the ledger and splits cash into what has settled, what is
  arriving and what is owed, and tracks the rule a cash account lives by: something bought with
  the proceeds of a sale that has not settled may not be sold until it has. Doing so anyway is
  a *good-faith violation*, and it is counted (three in twelve months gets a real account
  restricted for 90 days). `spectre settlement N` and `GET /portfolios/N/settlement` show it;
  the dashboard has a settlement card.

### Risk (`spectre/risk`)
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
- **Options** (`risk/options.py`) have no useful price history, so they are counted through
  their delta: an option's return is its underlying's return times `delta × underlying price ÷
  option price`, never worse than −100% for a bought option. VaR, component VaR and stress
  scenarios all use this, and the report lists which contracts were treated this way and any
  that could not be included. It is a first-order estimate: gamma, volatility and time decay
  are ignored.
- **Coins** trade at weekends and stocks do not; when both are held, history is sampled on
  business days so a coin's weekend move lands in Monday's return.
- **Real price history**: `spectre prices-backfill` loads about two years of daily closes from
  Alpaca (split- and dividend-adjusted) for every real stock, fund and coin in the book.
  Without it a new holding has no history and the risk numbers cannot be computed.

### Compliance (`spectre/compliance`)
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
| `no_naked_options` | – (a sold call needs 100 shares per contract, a sold put needs strike × 100 in cash) |
| `no_good_faith_violations` | – (blocks selling something bought with sale proceeds that have not settled) |
| `settled_funds_only` | – (stricter: only money that has settled may be spent) |

Adding a rule type is one decorated function in `rules.py`. An unknown rule type evaluates as a hard
breach rather than silently passing.

**Pre-trade logic**: breaches are evaluated before and after the proposed trade. A hard breach that
is *introduced or worsened* blocks the order. A breach that already existed and is not made worse
is reported but does not block, so a portfolio already over a limit can still trade back into line.
Every check is recorded in `compliance_checks`.

### Trading (`spectre/trading`)
`create_order` runs pre-trade compliance and returns the order as `APPROVED` or `REJECTED` (with
the breach messages as the reason). `fill_order` accepts partial fills, enforces limit prices, writes
a `Trade` to the ledger, and tracks average fill price. `cancel_order`, `blotter`. Every status
transition writes an `audit_events` row with actor and detail.

### Signals (`spectre/signals`) — what the crowd is saying, made tradeable

```
sources ──► screening ──► NLP ──► store ──► aggregation ──► signals ──► backtest / paper strategy
bluesky     bots, spam    sentiment          topic bubbles   z-scores      IC, long/short, OMS orders
reddit      bursts        fear vocabulary    sentiment bars                      │
stocktwits  duplicates    ticker + alias     fear index                          ▼
rss, x      coordination  extraction         market snapshots              /dashboard (live viewer)
kalshi
polymarket
```

- **Sources** (`sources/`). Adding one is a class with an `async run(emit, stop)`.

  | source | what it gives | status |
  |---|---|---|
  | `bluesky` | every public post in real time (~48/s, ~34/s English); filter by keyword or sample | verified live |
  | `stocktwits` | per-stock chatter, users' own Bullish/Bearish labels, and the price at posting time | verified live |
  | `kalshi` | prediction-market odds by category (economics, politics, elections, companies…) | verified live |
  | `polymarket` | prediction-market odds by topic tag (economy, fed, finance, geopolitics, crypto…) | verified live |
  | `trends` | Google "trending now" searches per country, with traffic and attached headlines | verified live |
  | `reddit` | subreddit posts | written, unverified: Reddit refuses unauthenticated servers |
  | `x` | recent search | written, unverified: needs a paid bearer token |
  | `rss` | news headlines from feeds you supply | written; no default feeds (see below) |
  | `synthetic`, `replay` | offline demo stream; JSONL recordings | tested |

  "Verified live" means run against the real service on 2026-11-18. Things learned that day:
  Kalshi quotes prices as dollar strings and its plain market list is mostly sports parlays (so
  the adapter reads categorised events); Polymarket's top-by-volume list is mostly esports (so it
  reads topic tags); the WSJ markets RSS feed has been frozen since January 2025 and CNBC blocks
  automated clients; Google's interest-over-time endpoint answers servers with HTTP 429.
  Facebook and Instagram do not expose public conversation to third parties and are absent.
- **Real tickers** (`marketdata/universe.py`): `spectre seed-universe` loads ~60 real companies
  and funds with hand-written recognition rules, because names are ambiguous: "nvidia" always
  counts, "apple" / "meta" / "visa" count only when the post also reads like market talk, and
  short or word-like symbols (`CAT`, `GM`, `V`) are never matched on their own.
- **Prices from the conversation**: every Stocktwits message carries the stock's price at
  posting time. The pipeline keeps each one as a tick and the day's latest as the close, which is
  enough to value positions and paper trade real names. It is not an execution-grade quote.
- **Screening** (`screening.py`): a post's quality is the product of independent heuristics —
  text shape (stuffing, link-only, shouting), author burst rate, self-duplication (SimHash),
  cross-author coordination (same text from many accounts in minutes), and account metadata when
  the source provides it. Below 0.35 a post is kept but excluded from every aggregate, so the
  screening itself is auditable. On the demo stream the bot population is caught with zero human
  posts screened out.
- **NLP** (`nlp.py`): VADER with a finance lexicon, a fear vocabulary, cashtag + company-name
  extraction mapped to the securities table, and topic clustering (agglomerative on TF-IDF cosine
  for ordinary windows, mini-batch k-means for firehose-sized ones).
  **Known weakness, measured:** against 123 real posts whose authors labelled themselves
  (`spectre calibrate`), the lexicon model took a side 64% of the time and was right 67% of the
  time, worse than always guessing "bullish" (72%). So where an author declares a stance, that
  label is used instead of the model's guess, and the model's own score is kept separately so it
  can keep being measured. A classifier trained on those labels is the next step.
- **Aggregation** (`aggregate.py`): per-window **topic bubbles** (volume, unique authors, sentiment,
  fear share, velocity vs. the matching topic in the previous window), per-security **sentiment
  bars** with attention and sentiment z-scores against the security's own history, a **fear
  index**, and prediction-market snapshots with 24h change.
- **Signals & evaluation** (`signals.py`): daily signal matrix; **information coefficient** (daily
  cross-sectional rank correlation with forward returns, with t-stat and hit rate) and a
  **long/short backtest** reported before and after trading costs (`--cost-bps`, the one-way
  cost per trade; the demo strategy replaces most of its book daily, so costs matter); a **paper
  strategy** that trades the top names inside a sleeve of a portfolio *through the OMS*, so
  compliance can reject it like any other order.

```bash
spectre seed-social                  # synthetic history aligned to the demo prices (daily bubbles + bars)
spectre bubbles · spectre sentiment · spectre markets
spectre backtest                     # does the signal predict returns? IC + long/short
spectre paper-trade 2 --fill         # trade it on paper through compliance
spectre ingest --sources synthetic --minutes 5 --topic-window 1   # offline live pipeline, then open /dashboard

# real data (needs outbound access to the sources' hosts)
spectre seed-universe                # real tickers, reference data only
spectre ingest --sources bluesky,stocktwits,kalshi,polymarket,trends --symbols NVDA,TSLA,SPY --minutes 0
spectre trends · spectre calibrate   # trending searches; sentiment model vs users' own labels
```

### Execution (`spectre/execution`) — the last gate before a broker

An approved order reaches a broker only if every gate is open:

1. compliance approved it when it was created;
2. the **kill switch** is off (`spectre halt "reason"` / `spectre resume`; stored in the database,
   so it stops every process);
3. it fits the **trading limits**: per-order size, daily total, orders per day, position size
   after the trade, and an optional symbol list. Defaults are small (1,000 per order, 5,000 a day);
4. for a live broker only: `SPECTRE_TRADING_MODE=live` is set **and** a named person approved that
   specific order. Without both, nothing is sent.

`PaperBroker` fills at the latest known price (optionally with slippage against you) and is the
only broker in the repository. Paper orders take exactly the path a live order would, so what
works on paper has already passed every check. A live broker is one more class; it must use the
broker's official API with a scoped, revocable key, never an account password.

```bash
spectre portfolio-create "My paper book" --cash 100000   # also adds no-overdraft / no-shorts rules
spectre order 1 NVDA BUY 5          # compliance decides immediately; nothing is sent
spectre execute 7                   # paper fill, subject to limits and the kill switch
spectre limits · spectre halt "something looks wrong" · spectre resume
```

### Alpaca (`execution/alpaca.py`) — paper trading, live prices, option chains

Written from Alpaca's published API definition and confirmed against a live paper account.

- **Paper trading.** `--broker alpaca` on `bot`, `autopilot` and `execute` routes orders to your
  Alpaca paper account. Paper keys and live keys are separate at Alpaca, and the broker class
  refuses to be constructed for any address other than the paper host, so this path cannot move
  real money. It sends nothing while the market is closed, waits briefly for a fill, cancels what
  is left, and reports broker refusals as plain reasons.
- **Prices.** `spectre prices-sync` stores Alpaca's latest traded price for every US stock and
  fund in the book (free plan: real-time IEX).
- **Option chains.** `spectre options NVDA` shows bid, ask, implied volatility and greeks per
  contract (free plan: "indicative" prices that can lag the market; the full real-time feed is a
  paid plan).
- **Option orders.** An option is a security whose ticker is its contract symbol
  (`NVDA261224C00155000`) with a multiplier of 100, so positions, cash, compliance and the
  ledger treat it like anything else. Orders go to the same endpoint as whole contracts with a
  limit price. Quotes and greeks of held contracts are stored in `option_marks`.
- **Cash only.** `spectre alpaca-margin 1` sets the account's margin multiplier to 1, so buying
  power equals cash. While `SPECTRE_ALPACA_CASH_ONLY` is true (the default) the broker refuses
  to send any order if the account is able to borrow.
- **Crypto.** Coins (BTC, ETH, SOL and nine more) are securities like any other, priced from
  the bid/ask midpoint and traded in millionths. Orders go out as pairs (`BTC/USD`), good till
  cancelled, at any hour; coins cannot be bought on margin or sold short at Alpaca. The fee
  (0.25%) is taken in coin at once, so a purchase leaves slightly fewer coins than were bought.
- **Reconciliation.** `spectre alpaca-reconcile N` compares every position and the cash balance
  with Alpaca's own figures. With `--apply` (the autopilot does this each cycle) the small,
  explainable differences are booked: coin fees as a sale whose proceeds are all fee, and a few
  dollars of option fees and price rounding as a `FEE` cash movement. Anything larger is
  reported and left alone.
- `spectre alpaca-status --portfolio N` shows the account and checks Alpaca's positions against
  the ledger.

```bash
# keys live in a git-ignored .env, never in the repository
echo 'SPECTRE_ALPACA_KEY_ID=PK...'       >> .env
echo 'SPECTRE_ALPACA_SECRET_KEY=...'     >> .env
spectre portfolio-create "KAIROS Alpaca" --cash 100000
spectre autopilot 2 --broker alpaca      # live feeds in, a paper decision every 10 minutes
```

### Rates (`spectre/rates`) — the bond market

- **US Treasury yield curve** from the Treasury's own daily file: every maturity from 1 month to
  30 years, with changes over a day, a week and a month, the 10y-2y and 10y-3m slopes and an
  inversion flag.
- **Credit and policy** from FRED: investment-grade and high-yield spreads, the Fed funds rate,
  the 10-year real yield and breakeven inflation. FRED returns a ZIP when asked for several
  series at once, so each is fetched separately.

```bash
spectre rates-sync --credit      # two years of curve history plus the FRED series
spectre rates
```

### KAIROS, the trend bot (`signals/strategy.py`) — paper only

`spectre autopilot <portfolio>` runs the live data feeds and a trading decision every few minutes
in one process; `spectre bot <portfolio>` runs a single decision cycle against data already
collected. Each cycle:

1. read the last `--lookback` minutes of screened posts;
2. per security, give **each author one vote** (their average stance) so one loud account cannot
   move the result; `net` = bullish authors minus bearish authors;
3. `score` = net × log(1 + authors), boosted 25% if the name is also in a trending search;
4. buy the top names above `--enter`, sell holdings whose score fell to `--exit-below`; long
   only, whole shares, each order through compliance and then the execution gate.

`--invest` caps the whole stock book as a share of the portfolio. A holding is sold when the
crowd turns against it, and held when there is no fresh read, with one exception: the
**stop-loss** (`--stop-loss`, 8% for stocks; `--crypto-stop-loss`, 12% for coins; 0 turns it
off) sells anything that has fallen that far below its average cost, whatever the crowd says
and even when nobody is talking about it. There is no profit target on shares. Nothing sold
today is bought back today.
If the book is more than five points over its allowance, the weakest reads outside the top
names are sold until it fits. An order the broker does not fill is withdrawn, not left open.

**Coin book (`--crypto`).** The same rule on coins, with its own allowance (`--crypto-invest`,
10%) and its own top list (`--crypto-top`, 3). It runs at every cycle, including nights and
weekends when the stock market is closed; stocks and options are only traded while it is open.

**Settlement holds.** When the portfolio has the `no_good_faith_violations` rule (new ones do),
KAIROS does not try to sell something it bought with unsettled sale proceeds until the money
has arrived, normally the next business day. It says so in its log instead.

**Options sleeve (`--options`, `signals/options_strategy.py`).** On the strongest reads it buys
a call (bullish) or a put (bearish): an expiry three to seven weeks out, the strike whose delta
is nearest 0.45, and only where the bid/ask spread is tight. It spends `--options-per-trade`
(3%) of the portfolio per position and at most `--options-budget` (20%) in total premium. A
holding is sold at +100%, at −50%, a week before expiry (so nothing is exercised or assigned),
or when the crowd turns; a contract sold today is not bought back the same day. Orders are
worked rather than thrown at the market: the first try is at the midpoint of the bid and ask,
then halfway to the far side, then the quote, and only last the order's own limit (3% past the
quote), so the spread is paid only as far as it has to be. It only ever
buys options, so the most a position can lose is what was paid for it, and the
`no_naked_options` rule would reject an uncovered sale regardless.

**Exposure cap (`--max-exposure`, default 1.0).** An option costs a fraction of the stock it
behaves like, so a premium budget alone lets the portfolio carry several times its own value
in market exposure while borrowing nothing. `spectre risk N` and the dashboard show that
figure (each option counted as contracts × 100 × delta × the stock price). The cap stops new
calls being bought once the portfolio would carry more market than `--max-exposure` times its
value; puts, which lower net exposure, are always allowed, and nothing is sold to get back
under it. 0 switches the cap off.

`--dry-run` shows the decisions without creating an order. These rules are a transparent
starting point to measure, not a proven edge: they have not been backtested on real data,
because real data only started flowing on 2026-11-18.

### Fundamentals (`spectre/fundamentals`) — filed results, quarter against quarter

Reads the SEC's EDGAR company-facts data and reduces it to one value per fiscal quarter for
revenue, gross profit, operating income, net income, diluted EPS and operating cash flow.
Filings do not state every quarter directly (cash flow is year-to-date only; the fourth quarter
exists only inside the annual figure), so missing quarters are derived by subtraction and
flagged. `spectre earnings NVDA` compares the latest quarter with the previous one and the same
quarter a year ago, with margin changes in points.

```bash
# The SEC only answers tools that declare a contact. Set it yourself; it is never stored here.
echo 'SPECTRE_SEC_USER_AGENT="Your Name you@example.com"' >> .env
spectre fundamentals-sync --tickers NVDA,AAPL,MSFT
spectre earnings NVDA
```

*Not yet run against the live SEC service; the quarter arithmetic is covered by tests.*

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

Start with `spectre serve` and open `/docs`. Main endpoints:

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
POST /orders/{id}/execute (paper, guarded)  ·  GET /trading/status  ·  POST /trading/halt  ·  POST /trading/resume
GET/POST /securities  ·  POST /prices  ·  POST /fx  ·  GET/POST /benchmarks
POST /portfolios/{id}/trades (book external trades)  ·  POST /portfolios/{id}/cashflows
GET  /audit
GET  /dashboard                                   night mode by default (toggle is remembered); one screen: Portfolio view (NAV, holdings with sentiment
                                                  overlay, exposures vs benchmark, VaR, stress, compliance,
                                                  blotter) and Signals view (bubbles, sentiment, markets, fear)
GET  /signals/status · /signals/bubbles · /signals/bubbles/history?hours=
GET  /signals/sentiment · /signals/sentiment/{ticker} · /signals/fear · /signals/markets
GET  /fundamentals/{ticker}                        latest quarter vs previous quarter and a year ago
GET  /rates/curve · /rates/history/{tenor} · /rates/macro   Treasury curve, one maturity over time, credit and policy
GET  /signals/trends · /signals/live (crowd stance the bot trades on) · /signals/calibration
GET  /signals/markets?min_prob=0.05&max_prob=0.95   contested markets only
GET  /signals/backtest?start=&end=&horizon=&signal=&cost_bps=
POST /signals/paper-trade/{portfolio_id}?top_n=&sleeve=&fill=
```

Errors map to HTTP status: not found → 404, bad input → 400, order-state conflicts → 409.

## Demo data

`spectre seed-demo` builds a deterministic universe: 12 US equities across 9 sectors, 3 EUR
equities, 4 bonds (two Treasuries, an IG corporate, a HY corporate), a commodity ETF and one
restricted tobacco name. Prices are generated from a **known** five-factor model (market, rates,
credit, size, EURUSD), which is what lets the test suite check that the factor estimator recovers
the betas that produced the data. Two portfolios (a global balanced fund against a 60/40 benchmark,
a US growth fund against an equal-weight index), eleven compliance rules, and three orders in
different states (approved, rejected by the restricted list, filled).

Replace it with real data by loading `securities`, `prices`, `fx_rates`, `cash_flows` and `trades`
through the API or directly into the tables.

## Configuration

Environment variables, all prefixed `SPECTRE_`: `DATABASE_URL`, `BASE_CURRENCY`, `VAR_CONFIDENCE`
(0.99), `VAR_HORIZON_DAYS` (1), `LOOKBACK_DAYS` (500), `MC_SIMULATIONS` (20000), `MC_SEED` (42).
Alpaca: `ALPACA_KEY_ID`, `ALPACA_SECRET_KEY`, `ALPACA_TRADING_URL` (paper host), `ALPACA_STOCK_FEED` (iex),
`ALPACA_OPTION_FEED` (indicative), `ALPACA_CASH_ONLY` (true: refuse to trade while the account can borrow). Trading guardrails: `TRADING_MODE` (paper), `TRADING_MAX_ORDER_NOTIONAL` (1000),
`TRADING_MAX_DAILY_NOTIONAL` (5000), `TRADING_MAX_ORDERS_PER_DAY` (20), `TRADING_MAX_POSITION_WEIGHT`
(0.20), `TRADING_REQUIRE_APPROVAL` (true), `TRADING_ALLOWED_SYMBOLS` (empty = any).

## Design notes

- **Single data model.** The reason integrated platforms win over best-of-breed point tools is that
  risk, compliance and trading all see the same positions at the same instant. SPECTRE gets that by
  construction: there is no positions table to fall out of sync.
- **Point-in-time everywhere.** Every valuation, exposure and risk call takes `as_of`; trades dated
  after it are ignored, prices are the latest on or before it.
- **Compliance is a gate, not a report.** Orders cannot be filled unless they were approved, and
  approval means the pre-trade check ran and was recorded.
- **Audit by default.** Order transitions, rule changes, booked trades and cash flows all write
  `audit_events`.

## Roadmap

Next steps in rough priority order: deploy the container to a permanent host so KAIROS can
build a track record (and prune old posts there); measure the crowd signal against real prices once weeks of data exist; train a sentiment
classifier on the Stocktwits labels and adopt it only if it beats the baseline out of sample; use
rates and credit as a risk-on / risk-off filter; SEC earnings against the live service; covered
calls, cash-secured puts and defined-risk spreads (never an uncovered sale); price history for
a record of performance over time, by sleeve and against the index;
Reddit via a registered app; performance attribution;
multi-user auth; scheduled end-of-day risk and compliance runs; Postgres migrations via Alembic; a
data-licensing review before selling derived signals. A live broker would come last, behind the
live-mode and per-order approval gates, and only after paper results justify it.
