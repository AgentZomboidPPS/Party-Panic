"""Settlement: a trade is agreed today, but the money and the securities change hands later.

US conventions, by trade date:
- stocks, funds and corporate bonds settle one business day after the trade ("T+1") since
  28 May 2024; two days from 5 September 2017; three before that;
- listed options and Treasuries settle T+1;
- coins settle at once.
Business days skip weekends and the stock-exchange holidays, which are computed here rather
than looked up, so the calendar works offline and for any year.

Why it matters in an account that cannot borrow: money from a sale is not really yours until
the sale settles. A cash account may spend it straight away, but if it then sells what it
bought before the original sale has settled, that is a **good-faith violation**; three in
twelve months and a real broker restricts the account to settled money for 90 days. `simulate`
replays the ledger in order and tracks exactly that:

- `funds_available`: settled money not yet committed to a purchase;
- each purchase is a lot; a lot paid for (even partly) with unsettled sale proceeds is
  *restricted* until those proceeds settle;
- selling a restricted lot early is recorded as a violation.

This is bookkeeping on top of the ledger. It never changes positions or cash.
"""

from __future__ import annotations

from collections import deque
from dataclasses import asdict, dataclass, field
from datetime import UTC, date, datetime, timedelta
from functools import lru_cache

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.marketdata.fx import fx_rate
from spectre.marketdata.prices import latest_prices
from spectre.models import CashFlow, ComplianceRule, Portfolio, Security, Side, Trade
from spectre.portfolio.whatif import ProposedTrade

EPS = 1e-9
T1_SINCE = date(2024, 5, 28)
T2_SINCE = date(2017, 9, 5)


# --------------------------------------------------------------------------- calendar


def _easter(year: int) -> date:
    """Western Easter Sunday (the anonymous Gregorian algorithm)."""
    a, b, c = year % 19, year // 100, year % 100
    d, e = b // 4, b % 4
    g = (8 * b + 13) // 25
    h = (19 * a + b - d - g + 15) % 30
    j, k = c // 4, c % 4
    m = (a + 11 * h) // 319
    r = (2 * e + 2 * j - k - h + m + 32) % 7
    month = (h - m + r + 90) // 25
    return date(year, month, (h - m + r + month + 19) % 32)


def _nth_weekday(year: int, month: int, weekday: int, n: int) -> date:
    first = date(year, month, 1)
    return first + timedelta(days=(weekday - first.weekday()) % 7 + 7 * (n - 1))


def _last_weekday(year: int, month: int, weekday: int) -> date:
    last = date(year + (month == 12), month % 12 + 1, 1) - timedelta(days=1)
    return last - timedelta(days=(last.weekday() - weekday) % 7)


@lru_cache(maxsize=64)
def market_holidays(year: int) -> frozenset[date]:
    """Days the US stock exchanges are closed, other than weekends."""

    def observed(d: date, saturday_moves: bool = True) -> date | None:
        if d.weekday() == 6:
            return d + timedelta(days=1)
        if d.weekday() == 5:
            return d - timedelta(days=1) if saturday_moves else None
        return d

    days = {
        observed(date(year, 1, 1), saturday_moves=False),  # a Saturday New Year's Day is not made up
        _nth_weekday(year, 1, 0, 3),  # Martin Luther King Jr. Day
        _nth_weekday(year, 2, 0, 3),  # Washington's Birthday
        _easter(year) - timedelta(days=2),  # Good Friday
        _last_weekday(year, 5, 0),  # Memorial Day
        observed(date(year, 7, 4)),
        _nth_weekday(year, 9, 0, 1),  # Labor Day
        _nth_weekday(year, 11, 3, 4),  # Thanksgiving
        observed(date(year, 12, 25)),
    }
    if year >= 2022:
        days.add(observed(date(year, 6, 19)))  # Juneteenth
    return frozenset(d for d in days if d is not None)


def is_business_day(d: date) -> bool:
    return d.weekday() < 5 and d not in market_holidays(d.year)


def add_business_days(d: date, n: int) -> date:
    while n > 0:
        d += timedelta(days=1)
        if is_business_day(d):
            n -= 1
    return d


def settlement_days(asset_class: str, trade_date: date, sector: str | None = None) -> int:
    if asset_class == "Crypto":
        return 0
    if asset_class == "Option" or (asset_class == "Fixed Income" and sector == "Government"):
        return 1
    return 1 if trade_date >= T1_SINCE else 2 if trade_date >= T2_SINCE else 3


def settlement_date(asset_class: str, trade_date: date, sector: str | None = None) -> date:
    return add_business_days(trade_date, settlement_days(asset_class, trade_date, sector))


def today() -> date:
    """The ledger dates trades by the UTC calendar day, so settlement does too."""
    return datetime.now(UTC).date()


# --------------------------------------------------------------------------- simulation


@dataclass
class Lot:
    ticker: str
    quantity: float
    bought_on: date
    clean_on: date | None  # the day it may be sold without a violation; None = already free


@dataclass
class Violation:
    date: date
    ticker: str
    quantity: float
    bought_on: date
    funds_settle_on: date
    proposed: bool = False  # True when it comes from a trade being tested, not one in the ledger

    def describe(self) -> str:
        return (f"selling {self.quantity:g} {self.ticker} on {self.date}: bought {self.bought_on} with money from a sale "
                f"that does not settle until {self.funds_settle_on}")


@dataclass
class SettlementState:
    portfolio_id: int
    as_of: date
    cash: float  # what the ledger shows: every trade counted the moment it is made
    settled_cash: float  # what has actually changed hands
    receivable: float  # sale proceeds still to arrive
    payable: float  # purchases still to be paid for
    funds_available: float  # settled money not committed to a purchase; negative = leaning on unsettled proceeds
    pending: list[dict] = field(default_factory=list)  # trades still to settle, soonest first
    restricted: list[dict] = field(default_factory=list)  # holdings that cannot yet be sold cleanly
    violations: list[Violation] = field(default_factory=list)

    def restricted_quantity(self, ticker: str) -> float:
        return sum(r["quantity"] for r in self.restricted if r["ticker"] == ticker)

    def free_on(self, ticker: str) -> date | None:
        dates = [date.fromisoformat(r["sell_freely_on"]) for r in self.restricted if r["ticker"] == ticker]
        return max(dates) if dates else None

    def recent_violations(self, months: int = 12) -> list[Violation]:
        cutoff = self.as_of - timedelta(days=round(months * 30.44))
        return [v for v in self.violations if v.date >= cutoff and not v.proposed]

    def to_dict(self) -> dict:
        d = asdict(self)
        d["as_of"] = self.as_of.isoformat()
        d["violations"] = [{**asdict(v), "date": v.date.isoformat(), "bought_on": v.bought_on.isoformat(),
                            "funds_settle_on": v.funds_settle_on.isoformat(), "what": v.describe()} for v in self.violations]
        d["violations_last_12_months"] = len(self.recent_violations())
        return d


def simulate(session: Session, portfolio_id: int, as_of: date | None = None,
             proposed: list[ProposedTrade] | None = None) -> SettlementState:
    """Replay the ledger up to `as_of` (default today), then any `proposed` trades as if made that day."""
    as_of = as_of or today()
    pf = session.get(Portfolio, portfolio_id)
    if pf is None:
        raise LookupError(f"Portfolio {portfolio_id} not found")
    base = pf.base_currency

    events: list[tuple] = []  # (date, sequence, kind, payload)
    for cf in session.execute(select(CashFlow).where(CashFlow.portfolio_id == portfolio_id, CashFlow.date <= as_of)).scalars():
        events.append((cf.date, 0, cf.id, "cash", cf))
    rows = session.execute(
        select(Trade, Security).join(Security, Security.id == Trade.security_id)
        .where(Trade.portfolio_id == portfolio_id, Trade.trade_date <= as_of)
    ).all()
    for t, sec in rows:
        fx = fx_rate(session, t.currency, base, t.trade_date)
        gross = t.quantity * t.price * sec.multiplier * fx
        settle = t.settle_date or settlement_date(sec.asset_class, t.trade_date, sec.sector)
        events.append((t.trade_date, 1, t.id, "trade", (sec, t.side, t.quantity, gross, t.fees * fx, settle, False)))
    for i, p in enumerate(proposed or []):
        sec = session.get(Security, p.security_id)
        price = p.price
        if price is None:
            px = latest_prices(session, [sec.id], as_of)
            if sec.id not in px.index:
                raise LookupError(f"No price for {sec.ticker} on or before {as_of}")
            price = float(px[sec.id])
        gross = p.quantity * price * sec.multiplier * fx_rate(session, sec.currency, base, as_of)
        events.append((as_of, 2, i, "trade", (sec, p.side.value, p.quantity, gross, 0.0,
                                               settlement_date(sec.asset_class, as_of, sec.sector), True)))
    events.sort(key=lambda e: e[:3])

    funds = 0.0  # settled money not committed to a purchase
    settled = 0.0  # money that has actually changed hands
    owed_in: list[tuple[date, float]] = []  # sale proceeds awaiting settlement
    owed_out: list[tuple[date, float]] = []  # purchases awaiting payment
    lots: dict[int, deque[Lot]] = {}
    violations: list[Violation] = []
    pending: list[dict] = []

    def settle_through(day: date) -> None:
        nonlocal funds, settled
        for _when, amount in [x for x in owed_in if x[0] <= day]:
            funds += amount
            settled += amount
        owed_in[:] = [x for x in owed_in if x[0] > day]
        for _when, amount in [x for x in owed_out if x[0] <= day]:
            settled -= amount
        owed_out[:] = [x for x in owed_out if x[0] > day]

    for day, _, _, kind, payload in events:
        settle_through(day)
        if kind == "cash":
            funds += payload.amount
            settled += payload.amount
            continue
        sec, side, qty, gross, fees, settle, is_proposed = payload
        if side == Side.BUY.value:
            cost = gross + fees
            clean_on = None
            if cost - funds > 0.005:
                # Paid for, at least in part, with sale proceeds that have not arrived: the lot
                # is restricted until enough of them have. `funds` below zero means earlier
                # purchases already lean on those proceeds, so this one needs the ones after.
                needed, covered = cost - funds, 0.0
                for when, amount in sorted(owed_in):
                    covered += amount
                    clean_on = when
                    if covered + 0.005 >= needed:
                        break
                else:
                    clean_on = clean_on or settle  # nothing owed in covers it: free once it is itself paid for
            funds -= cost
            if settle <= day:
                settled -= cost
            else:
                owed_out.append((settle, cost))
            lots.setdefault(sec.id, deque()).append(Lot(sec.ticker, qty, day, clean_on))
            if settle > as_of:
                pending.append({"settles_on": settle.isoformat(), "ticker": sec.ticker, "side": "BUY", "quantity": qty,
                                "amount": -cost, "traded_on": day.isoformat(), "proposed": is_proposed})
        else:
            proceeds = gross - fees
            left = qty
            queue = lots.get(sec.id, deque())
            while left > EPS and queue:
                lot = queue[0]
                used = min(left, lot.quantity)
                # A sliver sold only to pay a fee in kind brings in nothing and is no violation.
                if lot.clean_on is not None and day < lot.clean_on and abs(proceeds) > 0.005:
                    violations.append(Violation(day, sec.ticker, used, lot.bought_on, lot.clean_on, is_proposed))
                lot.quantity -= used
                left -= used
                if lot.quantity <= EPS:
                    queue.popleft()
            if settle <= day:
                funds += proceeds
                settled += proceeds
            else:
                owed_in.append((settle, proceeds))
            if settle > as_of and abs(proceeds) > 0.005:
                pending.append({"settles_on": settle.isoformat(), "ticker": sec.ticker, "side": "SELL", "quantity": qty,
                                "amount": proceeds, "traded_on": day.isoformat(), "proposed": is_proposed})
    settle_through(as_of)

    restricted: dict[tuple[str, date], float] = {}
    for queue in lots.values():
        for lot in queue:
            if lot.clean_on is not None and lot.clean_on > as_of and lot.quantity > EPS:
                restricted[(lot.ticker, lot.clean_on)] = restricted.get((lot.ticker, lot.clean_on), 0.0) + lot.quantity
    receivable, payable = sum(a for _, a in owed_in), sum(a for _, a in owed_out)
    return SettlementState(
        portfolio_id=portfolio_id, as_of=as_of, cash=settled + receivable - payable, settled_cash=settled,
        receivable=receivable, payable=payable, funds_available=funds,
        pending=sorted(pending, key=lambda p: (p["settles_on"], p["ticker"])),
        restricted=[{"ticker": t, "quantity": q, "sell_freely_on": d.isoformat()} for (t, d), q in sorted(restricted.items())],
        violations=violations,
    )


def sale_restrictions(session: Session, portfolio_id: int, as_of: date | None = None) -> dict[str, tuple[float, date]]:
    """{ticker: (quantity that cannot be sold cleanly yet, the day it can)}, but only when the
    portfolio has the `no_good_faith_violations` rule switched on. A strategy uses this to hold
    off on a sale that compliance would reject anyway."""
    on = session.execute(
        select(ComplianceRule.id).where(
            ComplianceRule.active.is_(True), ComplianceRule.rule_type == "no_good_faith_violations",
            (ComplianceRule.portfolio_id == portfolio_id) | (ComplianceRule.portfolio_id.is_(None)),
        ).limit(1)
    ).first()
    if on is None:
        return {}
    state = simulate(session, portfolio_id, as_of)
    return {r["ticker"]: (state.restricted_quantity(r["ticker"]), state.free_on(r["ticker"])) for r in state.restricted}


def backfill_settlement_dates(session: Session) -> int:
    """Stamp a settlement date on trades booked before SPECTRE recorded one. Returns how many."""
    rows = session.execute(
        select(Trade, Security).join(Security, Security.id == Trade.security_id).where(Trade.settle_date.is_(None))
    ).all()
    for t, sec in rows:
        t.settle_date = settlement_date(sec.asset_class, t.trade_date, sec.sector)
    if rows:
        session.commit()
    return len(rows)
