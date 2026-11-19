"""KAIROS options sleeve: express the strongest crowd reads with bought calls and puts.

Only buying. A bought option can lose what was paid for it and no more, and a bought put is the
one way this bot can act on a bearish read. Nothing here sells an option, so nothing here can
be naked; the compliance rule `no_naked_options` enforces that independently.

Each cycle:
1. refresh quotes and greeks for the contracts already held;
2. close a holding when it is within `exit_dte` days of expiry (never held into expiry week, so
   nothing is exercised or assigned), when it has hit the profit target or the loss stop, or
   when the crowd has clearly turned against it and the position is no longer young;
3. for the strongest reads not already covered, buy one contract series: a call when the crowd
   is bullish, a put when bearish; an expiry a few weeks out, the standard monthly one when
   there is one in range (far more heavily traded than the weeklies, so cheaper to get in and
   out of); the strike whose delta is nearest `target_delta`; and only if the bid/ask spread
   is tight enough to trade. A name whose calls
   (or puts) were sold today is not bought back the same day: a stop that is re-entered ten
   minutes later is not a stop.

Orders are limit orders a few percent through the quoted ask (buys) or bid (sells): option
spreads are too wide for market orders, and the free quote is not exact enough for a limit
placed right on it. Each goes through the OMS and the execution guard like any other order.

Prices on Alpaca's free plan are "indicative", not the full real-time feed. Nothing here has a
demonstrated edge.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.execution.alpaca import (
    AlpacaClient,
    AlpacaError,
    OptionQuote,
    ensure_option_security,
    parse_occ,
    store_option_mark,
)
from spectre.execution.brokers import Broker, PaperBroker
from spectre.execution.guard import TradingLimits, execute
from spectre.models import OrderType, Security, Side, Trade
from spectre.portfolio.positions import average_costs, value_portfolio
from spectre.portfolio.settlement import sale_restrictions
from spectre.risk.options import market_exposure
from spectre.signals.sources.base import utcnow
from spectre.signals.strategy import (
    BOT_ACTOR,
    BotReport,
    TrendSignal,
    last_bought,
    live_signals,
    record_reason,
    withdraw_unfilled,
)
from spectre.trading import oms


@dataclass(frozen=True)
class OptionRules:
    budget: float = 0.20  # share of the portfolio that may sit in option premium in total
    per_trade: float = 0.03  # share of the portfolio spent on one new position
    enter: float = 1.0  # how strong the crowd read must be (absolute score)
    min_authors: int = 10
    max_new: int = 3  # new positions per cycle
    dte_min: int = 21  # days to expiry at entry: far enough out that time decay is not brutal
    dte_max: int = 50
    target_delta: float = 0.45  # roughly at the money
    max_spread: float = 0.12  # (ask - bid) / mid; wider than this is too expensive to trade
    # How far past the quoted ask (buying) or bid (selling) the limit price may go. The free
    # quote is indicative and can lag the real market, so a limit placed exactly on it often
    # misses; the order still fills at the real price when that is better than the limit.
    limit_cushion: float = 0.03
    # The most market the whole portfolio may carry, as a multiple of its value, counting each
    # option as the amount of stock it behaves like (its delta-equivalent). An option costs a
    # fraction of that, so a premium budget alone lets exposure run to several times the
    # account. 1.0 means "never carry more market than the account is worth"; None = no cap.
    # It only stops new calls being added: nothing is sold to get back under it, and a put
    # (which lowers net exposure) is always allowed.
    max_exposure: float | None = None
    strike_band: float = 0.15  # only look at strikes within this fraction of the stock price
    exit_dte: int = 7
    take_profit: float = 1.0  # +100%
    stop_loss: float = -0.5  # -50%
    # Selling because the crowd changed its mind costs the bid/ask gap, several percent of the
    # position, so it takes more than a wobble: the read must be clearly the other way (a call
    # is sold at a score of -`turn` or lower, a put at +`turn` or higher), and not before the
    # position is `min_hold_minutes` old. The stop, the profit target and expiry do not wait.
    turn: float = 0.5
    min_hold_minutes: float = 240.0


def is_monthly(expiry: date) -> bool:
    """A standard monthly expiry: the third Friday of its month."""
    return expiry.weekday() == 4 and 15 <= expiry.day <= 21


def pick_contract(chain: list[OptionQuote], spot: float, rules: OptionRules, today: date) -> OptionQuote | None:
    """One contract from a chain of a single type: tradable, in the expiry window, delta nearest target."""
    usable = [
        q for q in chain
        if q.bid and q.ask and q.mid and (q.ask - q.bid) / q.mid <= rules.max_spread
        and rules.dte_min <= (q.expiration - today).days <= rules.dte_max
    ]
    if not usable:
        return None
    # Monthly contracts (the third Friday) are where the trading is: on live chains they showed
    # many times the volume of the weeklies either side and a fraction of the bid/ask gap. So a
    # monthly expiry inside the window wins; otherwise, and between two of a kind, the one
    # nearest the middle of the window.
    middle = (rules.dte_min + rules.dte_max) / 2
    expiry = min({q.expiration for q in usable}, key=lambda e: (not is_monthly(e), abs((e - today).days - middle)))
    candidates = [q for q in usable if q.expiration == expiry]
    with_delta = [q for q in candidates if q.delta is not None]
    if with_delta:
        return min(with_delta, key=lambda q: abs(abs(q.delta) - rules.target_delta))
    # No greeks on the feed: take the first strike out of the money.
    if candidates[0].type == "call":
        otm = [q for q in candidates if q.strike >= spot]
        return min(otm, key=lambda q: q.strike) if otm else max(candidates, key=lambda q: q.strike)
    otm = [q for q in candidates if q.strike <= spot]
    return max(otm, key=lambda q: q.strike) if otm else min(candidates, key=lambda q: q.strike)


def _sold_today(session: Session, portfolio_id: int, today: date) -> set[tuple[str, str]]:
    """(underlying, call|put) pairs this portfolio has sold option contracts on today."""
    rows = session.execute(
        select(Security.ticker).join(Trade, Trade.security_id == Security.id).where(
            Trade.portfolio_id == portfolio_id, Trade.side == Side.SELL.value, Trade.trade_date >= today,
            Security.asset_class == "Option",
        )
    ).scalars()
    return {(p[0], p[2]) for p in map(parse_occ, rows) if p}


def run_options_once(
    session: Session,
    portfolio_id: int,
    client: AlpacaClient,
    broker: Broker | None = None,
    limits: TradingLimits | None = None,
    rules: OptionRules | None = None,
    lookback_minutes: int = 60,
    dry_run: bool = False,
    at: datetime | None = None,
    today: date | None = None,
    allow_buys: bool = True,
    evidence: bool = False,
    buy_scale: float = 1.0,
) -> BotReport:
    broker = broker or PaperBroker()
    limits = limits or TradingLimits.from_settings()
    rules = rules or OptionRules()
    today = today or utcnow().date()
    signals = live_signals(session, lookback_minutes, min_posts=5, min_authors=rules.min_authors, at=at)
    if evidence:  # what else is known about each name: a call needs less of a crowd read on a name in a strong trend
        from spectre.signals.evidence import describe, weigh

        signals = weigh(session, signals, at)
    by_ticker: dict[str, TrendSignal] = {s.ticker: s for s in signals}

    valued = value_portfolio(session, portfolio_id)
    held = valued.positions[(valued.positions["asset_class"] == "Option") & (valued.positions["quantity"] > 0)]
    report = BotReport(at=(at or datetime.now()).isoformat(timespec="seconds"), portfolio_id=portfolio_id,
                       nav=valued.total_value, cash=valued.cash, signals=signals, targets=[], dry_run=dry_run)
    cash = valued.cash

    def trade(sec: Security, side: Side, qty: int, limit_price: float, why: str) -> bool:
        action = {"ticker": sec.ticker, "side": side.value, "quantity": qty, "price": limit_price, "why": why}
        ok = dry_run
        if dry_run:
            action["outcome"] = "dry run"
        else:
            order = oms.create_order(session, portfolio_id=portfolio_id, security_id=sec.id, side=side, quantity=qty,
                                     order_type=OrderType.LIMIT, limit_price=limit_price, actor=BOT_ACTOR)
            record_reason(session, order, why)
            if order.status != "APPROVED":
                action.update(outcome="rejected by compliance", detail=order.reject_reason)
            else:
                res = execute(session, order.id, broker, limits, actor=BOT_ACTOR)
                action.update(outcome=res.outcome, detail="; ".join(res.reasons), order_id=order.id, fill_price=res.price)
                ok = res.outcome == "executed"
                withdraw_unfilled(session, order)
        report.actions.append(action)
        return ok

    # --- 1 and 2: mark what is held, then decide exits
    covered: set[str] = set()
    closed = _sold_today(session, portfolio_id, today)
    on_hold = sale_restrictions(session, portfolio_id) if len(held) else {}
    costs = average_costs(session, portfolio_id) if len(held) else {}
    bought = last_bought(session, portfolio_id, [int(i) for i in held.index]) if len(held) else {}
    now = at or utcnow()
    premium_held = 0.0
    if len(held):
        try:
            quotes = {q.symbol: q for q in client.option_snapshots(list(held["ticker"]))}
        except AlpacaError as exc:
            quotes = {}
            report.actions.append({"ticker": "-", "side": "-", "quantity": 0, "price": None, "outcome": "skipped",
                                   "why": f"could not refresh option quotes: {exc}"})
        for sid, row in held.iterrows():
            parsed = parse_occ(row["ticker"])
            if parsed is None:
                continue
            root, expiry, kind, _ = parsed
            sec = session.get(Security, int(sid))
            q = quotes.get(row["ticker"])
            if q is not None:
                spot = by_ticker[root].price if root in by_ticker else None
                store_option_mark(session, sec, q, spot)
            qty = int(row["quantity"])
            bid = q.bid if q is not None and q.bid else None
            cost = costs.get(int(sid))
            pnl = (bid / cost - 1.0) if bid and cost else None
            dte = (expiry - today).days
            sig = by_ticker.get(root)
            reason = None
            if dte <= rules.exit_dte:
                reason = f"{dte} days to expiry"
            elif pnl is not None and pnl >= rules.take_profit:
                reason = f"up {pnl:+.0%}: profit target"
            elif pnl is not None and pnl <= rules.stop_loss:
                reason = f"down {pnl:+.0%}: stop"
            elif sig is not None and ((kind == "call" and sig.score <= -rules.turn) or (kind == "put" and sig.score >= rules.turn)):
                reason = f"crowd has turned (score {sig.score:+.2f})"
                age = (now - bought[int(sid)]).total_seconds() / 60 if int(sid) in bought else None
                if age is not None and age < rules.min_hold_minutes:
                    report.actions.append({"ticker": row["ticker"], "side": "SELL", "quantity": qty, "price": bid, "outcome": "skipped",
                                           "why": f"{reason}; but it was bought {age:.0f} minutes ago and is kept at least "
                                                  f"{rules.min_hold_minutes:.0f} before a change of mind counts"})
                    reason = None
            if reason and row["ticker"] in on_hold and dte > 2:
                # Bought with money from a sale that has not settled yet: selling today would be
                # a good-faith violation. (With expiry two days off, getting out matters more.)
                report.actions.append({"ticker": row["ticker"], "side": "SELL", "quantity": qty, "price": bid, "outcome": "skipped",
                                       "why": f"{reason}; held until {on_hold[row['ticker']][1]}, when the money that paid for it settles"})
                reason = None
            if reason and bid is None and dte > 2:
                # No quote to price the sale against: wait for one rather than sell at any price.
                report.actions.append({"ticker": row["ticker"], "side": "SELL", "quantity": qty, "price": None,
                                       "outcome": "skipped", "why": f"wanted to sell ({reason}) but there is no bid"})
                reason = None
            # With expiry two days off and still no quote, a one-cent limit takes whatever the bid
            # is: better than being exercised.
            floor = max(round(bid * (1 - rules.limit_cushion), 2), 0.01) if bid else 0.01
            if reason and trade(sec, Side.SELL, qty, floor, reason):
                cash += qty * floor * 100
                closed.add((root, kind))
            else:
                covered.add(root)
                premium_held += float(row["market_value"])
        session.commit()

    # --- 3: new positions
    if not allow_buys:  # a brake is on: this cycle only sells
        return report
    buy_scale = min(max(buy_scale, 0.0), 1.0)  # below 1 in a turbulent market: smaller and fewer new positions
    budget_left = rules.budget * valued.total_value * buy_scale - premium_held
    exposure_room = None
    if rules.max_exposure is not None:
        now = value_portfolio(session, portfolio_id)  # after any exits above
        exposure_room = rules.max_exposure * now.total_value - market_exposure(session, now)["net"]
    wanted = sorted(
        (s for s in signals if abs(s.strength) >= rules.enter and s.price and s.ticker not in covered
         and (s.ticker, "call" if s.score > 0 else "put") not in closed),
        key=lambda s: -abs(s.strength),
    )
    report.targets = [s.ticker for s in wanted[: rules.max_new]]
    for sig in wanted[: rules.max_new]:
        spend = min(rules.per_trade * valued.total_value * buy_scale, budget_left, cash)
        if spend <= 0:
            break
        kind = "call" if sig.score > 0 else "put"
        note = {"ticker": sig.ticker, "side": "BUY", "quantity": 0, "price": None, "outcome": "skipped"}
        try:
            chain = client.option_chain(
                sig.ticker, option_type=kind,
                expiration_date_gte=today + timedelta(days=rules.dte_min),
                expiration_date_lte=today + timedelta(days=rules.dte_max),
                strike_price_gte=round(sig.price * (1 - rules.strike_band), 2),
                strike_price_lte=round(sig.price * (1 + rules.strike_band), 2),
            )
        except AlpacaError as exc:
            report.actions.append({**note, "why": f"no option chain: {exc}"})
            continue
        q = pick_contract(chain, sig.price, rules, today)
        if q is None:
            report.actions.append({**note, "why": f"no {kind} with a tight enough market ({len(chain)} contracts seen)"})
            continue
        limit = math.ceil(q.ask * (1 + rules.limit_cushion) * 100) / 100  # the most it may pay, per share
        qty = math.floor(spend / (limit * 100))
        if qty < 1:
            report.actions.append({**note, "ticker": q.symbol, "price": limit,
                                   "why": f"one contract costs up to {limit * 100:,.0f}, more than the {spend:,.0f} available"})
            continue
        # What one contract adds to the market the portfolio carries: 100 shares x delta.
        carries = 100 * (q.delta if q.delta is not None else (0.5 if kind == "call" else -0.5)) * sig.price
        if exposure_room is not None and carries > 0:
            qty = min(qty, math.floor(max(exposure_room, 0.0) / carries))
            if qty < 1:
                report.actions.append({**note, "ticker": q.symbol, "price": limit,
                                       "why": (f"one contract behaves like {carries:,.0f} of {sig.ticker}; that would take market "
                                               f"exposure past {rules.max_exposure:.0%} of the portfolio")})
                continue
        delta = f"delta {q.delta:+.2f}" if q.delta is not None else "no greeks"
        why = (f"{'bullish' if kind == 'call' else 'bearish'} read on {sig.ticker} (score {sig.score:+.2f}, "
               f"{sig.n_authors} authors{describe(sig) if evidence else ''}); {(q.expiration - today).days}d, {delta}"
               + (f"; at {buy_scale:.0%} of normal size because the market is turbulent" if buy_scale < 0.95 else ""))
        if dry_run:
            report.actions.append({"ticker": q.symbol, "side": "BUY", "quantity": qty, "price": limit,
                                   "outcome": "dry run", "why": why})
            cash -= qty * limit * 100
            budget_left -= qty * limit * 100
            if exposure_room is not None:
                exposure_room -= qty * carries
            continue
        sec = ensure_option_security(session, q)
        store_option_mark(session, sec, q, sig.price)
        session.commit()
        if trade(sec, Side.BUY, qty, limit, why):
            paid = report.actions[-1].get("fill_price") or limit
            cash -= qty * paid * 100
            budget_left -= qty * paid * 100
            if exposure_room is not None:
                exposure_room -= qty * carries
    return report
