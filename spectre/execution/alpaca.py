"""Alpaca: paper trading, live prices and option chains through the official API.

Facts taken from Alpaca's own documentation and confirmed against the live service on
2026-11-18:
- paper accounts trade on paper-api.alpaca.markets; prices come from data.alpaca.markets
- paper keys and live keys are separate and cannot be used for each other
- requests carry the `APCA-API-KEY-ID` and `APCA-API-SECRET-KEY` headers
- the free plan gives real-time IEX stock prices and "indicative" option prices
- crypto trades around the clock on the same orders endpoint as pairs ("BTC/USD"), in fractions,
  with `time_in_force` gtc or ioc; it cannot be bought on margin or sold short; the fee
  (0.25% at the entry tier) is taken from what you receive, so a coin purchase leaves slightly
  fewer coins than were bought (the documentation says fees post at the end of the day; on the
  paper account the position was already net of the fee seconds after the fill)
- positions report coins without the slash ("BTCUSD") and with `asset_class` "crypto"

`AlpacaPaperBroker` refuses to exist unless it points at the paper host, so this module cannot
move real money. A live broker would be a separate class with `live = True`, which the
execution guard only lets through in live mode with a named approver per order.
"""

from __future__ import annotations

import math
import re
import time
import uuid
from dataclasses import asdict, dataclass
from datetime import date, datetime, timedelta
from urllib.parse import urlparse

import httpx
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from spectre import audit
from spectre.config import settings
from spectre.execution.brokers import BrokerFill, BrokerReject
from spectre.execution.models import OptionMark
from spectre.marketdata.prices import latest_prices, upsert_prices
from spectre.marketdata.universe import BY_TICKER, crypto_base, option_view
from spectre.models import CashFlow, Fill, Order, OrderType, Security, Side, Trade
from spectre.portfolio.positions import value_portfolio
from spectre.portfolio.settlement import settlement_date
from spectre.signals.models import PriceTick
from spectre.signals.sources.base import to_naive_utc, utcnow

PAPER_HOST = "paper-api.alpaca.markets"
DONE_BADLY = {"rejected", "canceled", "expired", "suspended", "stopped", "done_for_day"}
_OCC = re.compile(r"^([A-Z.]{1,6})(\d{2})(\d{2})(\d{2})([CP])(\d{8})$")
_FRACTION = re.compile(r"(\.\d{6})\d+")


class AlpacaError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status


def _stamp(when: date | datetime) -> str:
    """A date as YYYY-MM-DD; a moment as an RFC 3339 UTC timestamp."""
    return when.strftime("%Y-%m-%dT%H:%M:%SZ") if isinstance(when, datetime) else when.isoformat()


def parse_time(s: str) -> datetime:
    """Alpaca timestamps carry nanoseconds; Python keeps microseconds."""
    return to_naive_utc(datetime.fromisoformat(_FRACTION.sub(r"\1", s).replace("Z", "+00:00")))


def parse_occ(symbol: str) -> tuple[str, date, str, float] | None:
    """NVDA261218C00150000 -> ("NVDA", 2026-12-18, "call", 150.0)."""
    m = _OCC.match(symbol)
    if not m:
        return None
    root, yy, mm, dd, cp, strike = m.groups()
    return root, date(2000 + int(yy), int(mm), int(dd)), "call" if cp == "C" else "put", int(strike) / 1000.0


@dataclass
class OptionQuote:
    symbol: str
    underlying: str
    expiration: date
    type: str
    strike: float
    bid: float | None
    ask: float | None
    last: float | None
    implied_volatility: float | None
    delta: float | None
    gamma: float | None
    theta: float | None
    vega: float | None
    volume: int | None

    @property
    def mid(self) -> float | None:
        if self.bid is None or self.ask is None or self.ask <= 0:
            return None
        return (self.bid + self.ask) / 2.0

    def to_dict(self) -> dict:
        d = asdict(self)
        d["expiration"] = self.expiration.isoformat()
        d["mid"] = self.mid
        return d


def quote_from_snapshot(symbol: str, snap: dict) -> OptionQuote | None:
    parsed = parse_occ(symbol)
    if parsed is None:
        return None
    root, expiry, kind, strike = parsed
    quote, trade = snap.get("latestQuote") or {}, snap.get("latestTrade") or {}
    greeks = snap.get("greeks") or {}
    return OptionQuote(
        symbol=symbol, underlying=root, expiration=expiry, type=kind, strike=strike,
        bid=quote.get("bp"), ask=quote.get("ap"), last=trade.get("p"),
        implied_volatility=snap.get("impliedVolatility"), delta=greeks.get("delta"), gamma=greeks.get("gamma"),
        theta=greeks.get("theta"), vega=greeks.get("vega"), volume=(snap.get("dailyBar") or {}).get("v"),
    )


class AlpacaClient:
    def __init__(
        self,
        key_id: str | None = None,
        secret_key: str | None = None,
        trading_url: str | None = None,
        data_url: str | None = None,
        transport: httpx.BaseTransport | None = None,
        timeout: float = 30.0,
    ):
        self.trading_url = (trading_url or settings.alpaca_trading_url).rstrip("/")
        self.data_url = (data_url or settings.alpaca_data_url).rstrip("/")
        key_id = settings.alpaca_key_id if key_id is None else key_id
        secret_key = settings.alpaca_secret_key if secret_key is None else secret_key
        headers = {"User-Agent": "spectre/0.1", "Accept": "application/json"}
        if key_id:
            headers["APCA-API-KEY-ID"] = key_id
        if secret_key:
            headers["APCA-API-SECRET-KEY"] = secret_key
        self._http = httpx.Client(timeout=timeout, headers=headers, transport=transport)

    @property
    def paper(self) -> bool:
        return urlparse(self.trading_url).hostname == PAPER_HOST

    def _call(self, method: str, url: str, **kwargs):
        try:
            r = self._http.request(method, url, **kwargs)
        except httpx.HTTPError as exc:
            raise AlpacaError(0, f"{type(exc).__name__}: {exc}") from exc
        if r.status_code >= 400:
            try:
                message = r.json().get("message") or r.text[:200]
            except ValueError:
                message = r.text[:200]
            raise AlpacaError(r.status_code, message)
        return r.json() if r.content else None

    # --- trading
    def account(self) -> dict:
        return self._call("GET", f"{self.trading_url}/v2/account")

    def clock(self) -> dict:
        return self._call("GET", f"{self.trading_url}/v2/clock")

    def authorised(self) -> bool:
        """True when the account answers: either keys are configured here, or the network this
        runs on adds the credentials itself (a hosting environment's saved secret)."""
        try:
            self.account()
        except AlpacaError:
            return False
        return True

    def activities(self, page_size: int = 100) -> list[dict]:
        """Everything that has happened in the account, oldest first: fills, fees, dividends,
        deposits. This is the broker's own record, and a ledger can be rebuilt from it."""
        out: list[dict] = []
        params: dict = {"direction": "asc", "page_size": page_size}
        while True:
            page = self._call("GET", f"{self.trading_url}/v2/account/activities", params=params) or []
            out.extend(page)
            if len(page) < page_size:
                return out
            params["page_token"] = page[-1]["id"]

    def starting_value(self) -> float | None:
        """What the account was worth at the start of the last month of its history; for a
        young account that is what it was opened with."""
        try:
            body = self._call("GET", f"{self.trading_url}/v2/account/portfolio/history", params={"period": "1M", "timeframe": "1D"})
        except AlpacaError:
            return None
        value = (body or {}).get("base_value")
        return float(value) if value else None

    def configurations(self) -> dict:
        """Account switches, including `max_margin_multiplier` ("1" means no borrowing)."""
        return self._call("GET", f"{self.trading_url}/v2/account/configurations")

    def set_configurations(self, **changes) -> dict:
        return self._call("PATCH", f"{self.trading_url}/v2/account/configurations", json=changes)

    def positions(self) -> list[dict]:
        return self._call("GET", f"{self.trading_url}/v2/positions")

    def submit_order(self, body: dict) -> dict:
        return self._call("POST", f"{self.trading_url}/v2/orders", json=body)

    def get_order(self, order_id: str) -> dict:
        return self._call("GET", f"{self.trading_url}/v2/orders/{order_id}")

    def cancel_order(self, order_id: str) -> None:
        self._call("DELETE", f"{self.trading_url}/v2/orders/{order_id}")

    # --- market data
    def latest_trades(self, symbols: list[str], feed: str | None = None) -> dict[str, tuple[float, datetime]]:
        """Latest trade price and time per symbol (symbols with no trade are simply absent)."""
        out: dict[str, tuple[float, datetime]] = {}
        for i in range(0, len(symbols), 100):
            body = self._call(
                "GET", f"{self.data_url}/v2/stocks/trades/latest",
                params={"symbols": ",".join(symbols[i : i + 100]), "feed": feed or settings.alpaca_stock_feed},
            )
            for sym, t in (body.get("trades") or {}).items():
                if t and t.get("p"):
                    out[sym] = (float(t["p"]), parse_time(t["t"]))
        return out

    def stock_bars(self, symbols: list[str], start: date | datetime, end: date | datetime | None = None,
                   timeframe: str = "1Day", feed: str = "sip", adjustment: str = "all") -> dict[str, list[tuple[datetime, float]]]:
        """(bar start time, closing price) per stock or fund, oldest first. The free plan serves
        full-market ("sip") history as long as it is at least 15 minutes old."""
        out: dict[str, list[tuple[datetime, float]]] = {}
        for i in range(0, len(symbols), 50):
            params: dict = {"symbols": ",".join(symbols[i : i + 50]), "timeframe": timeframe, "start": _stamp(start),
                            "limit": 10000, "adjustment": adjustment, "feed": feed}
            if end is not None:
                params["end"] = _stamp(end)
            while True:
                body = self._call("GET", f"{self.data_url}/v2/stocks/bars", params=params)
                for sym, bars in (body.get("bars") or {}).items():
                    out.setdefault(sym, []).extend((parse_time(b["t"]), float(b["c"])) for b in bars or [])
                if not body.get("next_page_token"):
                    break
                params["page_token"] = body["next_page_token"]
        return out

    def crypto_bars(self, coins: list[str], start: date | datetime, end: date | datetime | None = None,
                    timeframe: str = "1Day") -> dict[str, list[tuple[datetime, float]]]:
        """(bar start time, closing price) per coin against the dollar; daily bars run midnight to midnight UTC."""
        out: dict[str, list[tuple[datetime, float]]] = {}
        if not coins:
            return out
        params: dict = {"symbols": ",".join(f"{c}/USD" for c in coins), "timeframe": timeframe, "start": _stamp(start), "limit": 10000}
        if end is not None:
            params["end"] = _stamp(end)
        while True:
            body = self._call("GET", f"{self.data_url}/v1beta3/crypto/us/bars", params=params)
            for pair, bars in (body.get("bars") or {}).items():
                out.setdefault(pair.split("/")[0], []).extend((parse_time(b["t"]), float(b["c"])) for b in bars or [])
            if not body.get("next_page_token"):
                break
            params["page_token"] = body["next_page_token"]
        return out

    def daily_bars(self, symbols: list[str], start: date, end: date | None = None,
                   feed: str = "sip") -> dict[str, list[tuple[date, float]]]:
        """Daily closing prices per stock or fund, oldest first, adjusted for splits and dividends
        so that day-to-day changes are true returns."""
        return {sym: [(at.date(), close) for at, close in bars] for sym, bars in self.stock_bars(symbols, start, end, feed=feed).items()}

    def crypto_daily_bars(self, coins: list[str], start: date) -> dict[str, list[tuple[date, float]]]:
        """Daily closing prices per coin against the dollar (days run midnight to midnight UTC)."""
        return {coin: [(at.date(), close) for at, close in bars] for coin, bars in self.crypto_bars(coins, start).items()}

    def news(self, symbols: list[str], start: datetime | None = None, limit: int = 50) -> list[dict]:
        """The latest news articles that mention any of the symbols, newest first (one page)."""
        params: dict = {"symbols": ",".join(symbols), "limit": min(limit, 50), "sort": "desc"}
        if start is not None:
            params["start"] = _stamp(start)
        return (self._call("GET", f"{self.data_url}/v1beta1/news", params=params) or {}).get("news") or []

    def crypto_quotes(self, coins: list[str]) -> dict[str, tuple[float, float, datetime]]:
        """Latest (bid, ask, time) per coin against the dollar; coins with no two-sided quote are absent."""
        out: dict[str, tuple[float, float, datetime]] = {}
        if not coins:
            return out
        body = self._call("GET", f"{self.data_url}/v1beta3/crypto/us/latest/quotes",
                          params={"symbols": ",".join(f"{c}/USD" for c in coins)})
        for pair, q in (body.get("quotes") or {}).items():
            if q and q.get("bp") and q.get("ap"):
                out[pair.split("/")[0]] = (float(q["bp"]), float(q["ap"]), parse_time(q["t"]))
        return out

    def option_chain(
        self,
        underlying: str,
        expiration_date: date | None = None,
        expiration_date_gte: date | None = None,
        expiration_date_lte: date | None = None,
        option_type: str | None = None,
        strike_price_gte: float | None = None,
        strike_price_lte: float | None = None,
        feed: str | None = None,
        max_pages: int = 10,
    ) -> list[OptionQuote]:
        """Every contract on the underlying that matches the filters, with quote and greeks."""
        params: dict = {"feed": feed or settings.alpaca_option_feed, "limit": 1000}
        for key, value in (
            ("expiration_date", expiration_date), ("expiration_date_gte", expiration_date_gte),
            ("expiration_date_lte", expiration_date_lte), ("type", option_type),
            ("strike_price_gte", strike_price_gte), ("strike_price_lte", strike_price_lte),
        ):
            if value is not None:
                params[key] = value.isoformat() if isinstance(value, date) else value
        out: list[OptionQuote] = []
        for _ in range(max_pages):
            body = self._call("GET", f"{self.data_url}/v1beta1/options/snapshots/{underlying.upper()}", params=params)
            for symbol, snap in (body.get("snapshots") or {}).items():
                quote = quote_from_snapshot(symbol, snap)
                if quote is not None:
                    out.append(quote)
            token = body.get("next_page_token")
            if not token:
                break
            params["page_token"] = token
        return sorted(out, key=lambda q: (q.expiration, q.strike, q.type))

    def option_snapshots(self, symbols: list[str], feed: str | None = None) -> list[OptionQuote]:
        """Quote and greeks for specific contracts (at most 100 per request)."""
        out: list[OptionQuote] = []
        for i in range(0, len(symbols), 100):
            params: dict = {"symbols": ",".join(symbols[i : i + 100]), "feed": feed or settings.alpaca_option_feed}
            while True:
                body = self._call("GET", f"{self.data_url}/v1beta1/options/snapshots", params=params)
                for symbol, snap in (body.get("snapshots") or {}).items():
                    quote = quote_from_snapshot(symbol, snap)
                    if quote is not None:
                        out.append(quote)
                if not body.get("next_page_token"):
                    break
                params["page_token"] = body["next_page_token"]
        return out


def sync_prices(session: Session, client: AlpacaClient, tickers: list[str] | None = None) -> int:
    """Store the latest price of each US stock, fund and coin in the book: one tick each, and
    the day's close updated to it. Stocks and funds use the last trade; coins use the midpoint
    of the bid and ask, because trades on Alpaca's own crypto venue can be many minutes apart.
    Returns how many securities were priced."""
    q = select(Security).where(Security.currency == "USD", Security.asset_class.in_(("Equity", "Fund", "Crypto")))
    if tickers:
        q = q.where(Security.ticker.in_([t.upper() for t in tickers]))
    secs = {s.ticker: s for s in session.execute(q).scalars()}
    if not secs:
        return 0
    seen: dict[str, tuple[float, datetime]] = {}
    stocks = sorted(t for t, s in secs.items() if s.asset_class != "Crypto")
    coins = sorted(t for t, s in secs.items() if s.asset_class == "Crypto")
    if stocks:
        seen.update(client.latest_trades(stocks))
    for coin, (bid, ask, at) in client.crypto_quotes(coins).items():
        seen[coin] = ((bid + ask) / 2.0, at)
    stamps = {at.replace(microsecond=0) for _, at in seen.values()}
    taken = set(
        session.execute(
            select(PriceTick.security_id, PriceTick.observed_at).where(
                PriceTick.source == "alpaca", PriceTick.observed_at.in_(stamps)
            )
        ).all()
    )
    closes = []
    for ticker, (price, at) in seen.items():
        sec, at = secs[ticker], at.replace(microsecond=0)
        if (sec.id, at) not in taken:
            session.add(PriceTick(security_id=sec.id, ticker=ticker, observed_at=at, price=price, source="alpaca"))
        closes.append({"security_id": sec.id, "date": at.date(), "close": price})
    upsert_prices(session, closes)
    session.commit()
    return len(seen)


def backfill_prices(session: Session, client: AlpacaClient, days: int = 750, tickers: list[str] | None = None,
                    everything: bool = False) -> dict:
    """Store daily closing prices going back `days` calendar days, so risk numbers that need a
    history (volatility, value at risk) work on real holdings.

    Covers the US stocks, funds and coins of the curated real-world universe; `everything`
    extends that to any other dollar security in the book (not the default, because a made-up
    demo ticker that happens to match a real symbol would have its prices overwritten).
    Today's price is left alone: the live one is fresher. Prices are adjusted as of now, so run
    this again after a stock split."""
    q = select(Security).where(Security.currency == "USD", Security.asset_class.in_(("Equity", "Fund", "Crypto")))
    if tickers:
        q = q.where(Security.ticker.in_([t.upper() for t in tickers]))
    secs = {s.ticker: s for s in session.execute(q).scalars() if everything or tickers or s.ticker in BY_TICKER}
    today = utcnow().date()
    start = today - timedelta(days=days)
    bars = client.daily_bars(sorted(t for t, s in secs.items() if s.asset_class != "Crypto"), start)
    bars.update(client.crypto_daily_bars(sorted(t for t, s in secs.items() if s.asset_class == "Crypto"), start))
    stored = 0
    for ticker, series in bars.items():
        sec = secs.get(ticker)
        if sec is None:
            continue
        stored += upsert_prices(session, [{"security_id": sec.id, "date": day, "close": close}
                                          for day, close in series if day < today and close > 0])
    session.commit()
    return {"securities": len([t for t in secs if bars.get(t)]), "prices": stored, "from": start.isoformat(),
            "missing": sorted(t for t in secs if not bars.get(t))}


def ensure_option_security(session: Session, q: OptionQuote) -> Security:
    """The ledger's record of an option contract: one contract controls 100 shares."""
    sec = session.execute(select(Security).where(Security.ticker == q.symbol)).scalar_one_or_none()
    if sec is not None:
        return sec
    under = session.execute(select(Security).where(Security.ticker == q.underlying)).scalar_one_or_none()
    sec = Security(
        ticker=q.symbol, name=f"{q.underlying} {q.expiration:%Y-%m-%d} {q.strike:g} {q.type}", asset_class="Option",
        currency="USD", sector=under.sector if under else None, country=under.country if under else "US",
        issuer=under.name if under else q.underlying, multiplier=100.0, maturity_date=q.expiration,
    )
    session.add(sec)
    session.flush()
    return sec


def store_option_mark(session: Session, sec: Security, q: OptionQuote, underlying_price: float | None) -> float | None:
    """Record the contract's latest quote and greeks, and its mark as today's price.
    The mark is the bid/ask midpoint when there is a two-sided quote, else the last trade."""
    mark = q.mid if q.mid is not None else (q.last if q.last else (q.bid or None))
    row = session.get(OptionMark, sec.id)
    if row is None:
        row = OptionMark(security_id=sec.id, underlying=q.underlying, option_type=q.type, strike=q.strike,
                         expiration=q.expiration, as_of=utcnow())
        session.add(row)
    row.as_of, row.bid, row.ask, row.mark = utcnow(), q.bid, q.ask, mark
    row.implied_volatility, row.delta, row.gamma, row.theta, row.vega = q.implied_volatility, q.delta, q.gamma, q.theta, q.vega
    row.underlying_price = underlying_price
    if row.delta is None and mark and underlying_price:
        # The feed carries no greeks for index options. Work the delta out from the price, so
        # the position still counts as the amount of market it behaves like.
        row.implied_volatility, row.delta = implied_delta(q, underlying_price, mark)
    if mark is not None and mark > 0:
        upsert_prices(session, [{"security_id": sec.id, "date": utcnow().date(), "close": mark}])
    session.flush()
    return mark


def implied_delta(q: OptionQuote, spot: float, price: float | None = None, today: date | None = None) -> tuple[float | None, float | None]:
    """(implied volatility, delta) of a contract worked out from its price and the price of its
    underlying, for when the feed gives no greeks. (None, None) when no volatility explains the price."""
    from spectre.risk.ladder import bs_delta, implied_vol

    price = price if price is not None else q.mid
    if not price or not spot:
        return None, None
    years = max((q.expiration - (today or utcnow().date())).days, 0.5) / 365.0
    vol = implied_vol(q.type, price, spot, q.strike, years)
    return (vol, bs_delta(q.type, spot, q.strike, years, vol)) if vol else (None, None)


def sync_option_marks(session: Session, client: AlpacaClient) -> int:
    """Refresh quote, greeks and price for every option contract currently held in any portfolio."""
    held = session.execute(
        select(Security)
        .join(Trade, Trade.security_id == Security.id)
        .where(Security.asset_class == "Option")
        .group_by(Security.id)
        .having(func.abs(func.sum(case((Trade.side == "BUY", Trade.quantity), else_=-Trade.quantity))) > 1e-9)
    ).scalars().all()
    if not held:
        return 0
    by_symbol = {s.ticker: s for s in held}
    quotes = client.option_snapshots(sorted(by_symbol))
    views = {q.underlying: option_view(q.underlying) for q in quotes}  # an index option is priced off its fund
    unders = {s.ticker: s.id for s in session.execute(
        select(Security).where(Security.ticker.in_({name for name, _ in views.values()}))).scalars()}
    spots = latest_prices(session, unders.values(), utcnow().date())
    for q in quotes:
        name, per_share = views[q.underlying]
        uid = unders.get(name)
        store_option_mark(session, by_symbol[q.symbol], q, float(spots[uid]) * per_share if uid in spots.index else None)
    session.commit()
    return len(quotes)


def trading_day_state(clock: dict, lead_minutes: float = 90.0) -> tuple[bool, str]:
    """Whether a bot that is meant to run "during the day" should be running now, from
    Alpaca's market clock, and why in words: yes while the stock market is open and for
    `lead_minutes` before it opens (time to gather the morning's posts). The clock knows about
    holidays, half days and daylight saving, which a fixed timetable would get wrong."""
    now, opens = parse_time(clock["timestamp"]), parse_time(clock["next_open"])
    if clock.get("is_open"):
        left = (parse_time(clock["next_close"]) - now).total_seconds() / 60
        return True, f"the stock market is open (it closes in {left:.0f} minutes)"
    to_open = (opens - now).total_seconds() / 60
    if to_open <= lead_minutes:
        return True, f"the stock market opens in {to_open:.0f} minutes"
    return False, f"the stock market is closed; it opens in {to_open / 60:.1f} hours"


def position_ticker(position: dict) -> str:
    """The ledger ticker for one of Alpaca's positions: coins come back as "BTCUSD"."""
    if position.get("asset_class") == "crypto":
        return crypto_base(position["symbol"]) or position["symbol"]
    return position["symbol"]


def mark_to_broker(session: Session, client: AlpacaClient) -> int:
    """Value what is held at the broker's own prices, so the account is worth the same here as
    in Alpaca's app. It matters most for options: SPECTRE's own mark is the middle of a quote
    that can be a tenth wide, while the broker marks nearer what a sale would fetch, and five
    contracts were enough to make the two totals differ by 0.6% of the account. Returns how
    many holdings were marked."""
    rows = []
    for position in client.positions():
        price = float(position.get("current_price") or 0.0)
        sec = session.execute(select(Security).where(Security.ticker == position_ticker(position))).scalar_one_or_none()
        if sec is not None and price > 0:
            rows.append({"security_id": sec.id, "date": utcnow().date(), "close": price})
    if rows:
        upsert_prices(session, rows)
        session.commit()
    return len(rows)


def position_quantities(positions: list[dict]) -> dict[str, float]:
    return {position_ticker(p): float(p.get("qty_available") or p["qty"]) for p in positions}


def reconcile(session: Session, client: AlpacaClient, portfolio_id: int, apply: bool = False,
              actor: str = "reconcile") -> dict:
    """Compare the ledger with the broker's own figures and list every difference.

    Two kinds of small difference are expected and, with `apply`, are booked so the books agree:
    - a coin position slightly smaller at the broker (the trading fee, taken in coin): booked
      as a sale of that sliver whose whole proceeds are a fee, so cash is untouched;
    - a few dollars of cash (regulatory fees on options, rounding of average fill prices):
      booked as a FEE or ADJUSTMENT cash movement.
    Anything larger, or a position the broker has and the ledger does not, is reported and
    left alone: that needs a person, not a plug."""
    acct = client.account()
    at_broker = {position_ticker(p): float(p["qty"]) for p in client.positions()}
    v = value_portfolio(session, portfolio_id)
    ledger = {r.ticker: r for r in v.positions.itertuples() if abs(r.quantity) > 1e-9}
    out: dict = {"portfolio_id": portfolio_id, "positions": [], "cash": None, "applied": apply, "clean": True}
    today = utcnow().date()

    for ticker in sorted(set(at_broker) | set(ledger)):
        row = ledger.get(ticker)
        mine, theirs = (float(row.quantity) if row is not None else 0.0), at_broker.get(ticker, 0.0)
        diff = theirs - mine
        if abs(diff) <= 1e-7:
            continue
        item = {"ticker": ticker, "ledger": mine, "broker": theirs, "difference": diff, "action": "unexplained: left alone"}
        fee_in_kind = row is not None and row.asset_class == "Crypto" and diff < 0 and -diff <= 0.01 * mine
        if fee_in_kind:
            item["action"] = "fee taken in coin"
            if apply:
                session.add(Trade(portfolio_id=portfolio_id, security_id=int(row.Index), side=Side.SELL.value,
                                  quantity=-diff, price=float(row.price), currency="USD",
                                  fees=-diff * float(row.price) * float(row.multiplier), trade_date=today, settle_date=today))
                item["action"] = "booked: fee taken in coin"
        else:
            out["clean"] = False
        out["positions"].append(item)

    cash_diff = float(acct["cash"]) - v.cash
    if abs(cash_diff) >= 0.005:
        small = abs(cash_diff) <= max(5.0, 0.0005 * max(v.total_value, 0.0))
        item = {"ledger": v.cash, "broker": float(acct["cash"]), "difference": cash_diff,
                "action": "fees and rounding" if small else "unexplained: left alone"}
        if small and apply:
            session.add(CashFlow(portfolio_id=portfolio_id, date=today, amount=cash_diff,
                                 kind="FEE" if cash_diff < 0 else "ADJUSTMENT",
                                 memo="Broker fees and rounding found in reconciliation"))
            item["action"] = "booked: fees and rounding"
        elif not small:
            out["clean"] = False
        out["cash"] = item
    if apply and (out["cash"] or out["positions"]):
        audit.record(session, actor=actor, entity_type="portfolio", entity_id=portfolio_id, action="reconciled",
                     detail={"positions": out["positions"], "cash": out["cash"]})
        session.commit()
    return out


# What a non-trade activity with a cash amount is, for the ledger.
_CASH_KINDS = {
    "CSD": "EXTERNAL", "CSW": "EXTERNAL", "JNLC": "EXTERNAL", "ACATC": "EXTERNAL", "TRANS": "EXTERNAL",
    "FEE": "FEE", "DIVFEE": "FEE", "PTC": "FEE",
    "DIV": "INCOME", "INT": "INCOME", "CGD": "INCOME", "PTR": "INCOME", "DIVNRA": "INCOME", "INTNRA": "INCOME",
}


def _security_for(session: Session, symbol: str) -> Security:
    """The ledger's security for a symbol in the broker's records, created if it is new here."""
    ticker = crypto_base(symbol) or symbol
    sec = session.execute(select(Security).where(Security.ticker == ticker)).scalar_one_or_none()
    if sec is not None:
        return sec
    parsed = parse_occ(ticker)
    if parsed:
        root, expiry, kind, strike = parsed
        return ensure_option_security(session, OptionQuote(ticker, root, expiry, kind, strike, *([None] * 9)))
    sec = Security(ticker=ticker, name=ticker, asset_class="Crypto" if crypto_base(symbol) else "Equity", currency="USD",
                   country="US", issuer=ticker, multiplier=1.0)
    session.add(sec)
    session.flush()
    return sec


def rebuild_ledger(session: Session, client: AlpacaClient, portfolio_id: int) -> dict:
    """Rebuild an empty ledger from the broker's own record of every fill, so a fresh database
    (a new machine, a replaced container) has the same trades, costs, settlement dates and
    banked profit as the one before it, not just the same positions.

    Every fill becomes an order, a fill and a trade dated as it happened; fees, dividends and
    deposits become cash movements; and the opening balance is whatever makes the cash add up
    to the broker's. Before anything is saved the rebuilt holdings are checked against the
    broker's positions; if they do not agree (history the broker no longer serves, say) nothing
    is written and the caller can fall back to `adopt_account`. Does nothing if the ledger
    already has history."""
    used = session.execute(select(func.count(Trade.id)).where(Trade.portfolio_id == portfolio_id)).scalar_one() or \
        session.execute(select(func.count(CashFlow.id)).where(CashFlow.portfolio_id == portfolio_id)).scalar_one()
    if used:
        return {"rebuilt": False, "reason": "the ledger already has history"}
    acct, held, acts = client.account(), client.positions(), client.activities()
    fills = [a for a in acts if a.get("activity_type") == "FILL"]
    if not fills:
        return {"rebuilt": False, "reason": "the broker has no fills on record"}

    cash_effect, first_day, skipped = 0.0, None, []
    orders: dict[str, Order] = {}
    quantity: dict[str, float] = {}
    for a in acts:
        kind = a.get("activity_type")
        if kind == "FILL":
            when = parse_time(a["transaction_time"])
            sec = _security_for(session, a["symbol"])
            qty, price, side = float(a["qty"]), float(a["price"]), a["side"].upper()
            order = orders.get(a["order_id"])
            if order is None:
                order = Order(portfolio_id=portfolio_id, security_id=sec.id, side=side, quantity=0.0, status="FILLED",
                              filled_quantity=0.0, avg_fill_price=0.0, created_by="alpaca-import", created_at=when)
                session.add(order)
                session.flush()
                orders[a["order_id"]] = order
            order.avg_fill_price = (order.avg_fill_price * order.filled_quantity + price * qty) / (order.filled_quantity + qty)
            order.quantity = order.filled_quantity = order.filled_quantity + qty
            session.add(Fill(order_id=order.id, quantity=qty, price=price, filled_at=when))
            session.add(Trade(portfolio_id=portfolio_id, security_id=sec.id, order_id=order.id, side=side, quantity=qty,
                              price=price, currency="USD", trade_date=when.date(),
                              settle_date=settlement_date(sec.asset_class, when.date(), sec.sector)))
            signed = qty if side == Side.BUY.value else -qty
            cash_effect -= signed * price * sec.multiplier
            quantity[sec.ticker] = quantity.get(sec.ticker, 0.0) + signed
            first_day = first_day or when.date()
        elif kind == "CFEE" and a.get("qty") and a.get("price") and a.get("symbol"):
            # A fee taken in coin: the sliver leaves the position and brings in no cash.
            sec, sliver, price = _security_for(session, a["symbol"]), abs(float(a["qty"])), float(a["price"])
            day = date.fromisoformat(a["date"]) if a.get("date") else utcnow().date()
            session.add(Trade(portfolio_id=portfolio_id, security_id=sec.id, side=Side.SELL.value, quantity=sliver, price=price,
                              currency="USD", fees=sliver * price, trade_date=day, settle_date=day))
            quantity[sec.ticker] = quantity.get(sec.ticker, 0.0) - sliver
        elif a.get("net_amount") not in (None, "", "0"):
            amount = float(a["net_amount"])
            day = date.fromisoformat(a["date"]) if a.get("date") else utcnow().date()
            session.add(CashFlow(portfolio_id=portfolio_id, date=day, amount=amount, kind=_CASH_KINDS.get(kind, "ADJUSTMENT"),
                                 memo=f"{kind}: {a.get('description') or a.get('symbol') or 'from the Alpaca account'}"[:200]))
            cash_effect += amount
            first_day = first_day or day
        else:
            skipped.append(kind)

    # The rebuilt holdings must be the broker's holdings (a coin position may be a shade
    # smaller there: its fee is taken in coin and booked by the reconciliation that follows).
    at_broker = {position_ticker(p): float(p["qty"]) for p in held}
    for ticker in set(quantity) | set(at_broker):
        mine, theirs = quantity.get(ticker, 0.0), at_broker.get(ticker, 0.0)
        if abs(mine - theirs) > 1e-7 and not (crypto_base(f"{ticker}USD") and 0 < mine - theirs <= 0.01 * mine):
            session.rollback()
            return {"rebuilt": False, "reason": f"the broker's fills do not add up to its positions ({ticker}: "
                                                 f"{mine:g} from fills, {theirs:g} held)"}

    opening = float(acct["cash"]) - cash_effect
    base = client.starting_value()
    if base and abs(opening - base) <= max(5.0, 0.0005 * base):
        opening = base  # the few dollars of difference are fees, which the reconciliation books as fees
    if abs(opening) >= 0.005:
        session.add(CashFlow(portfolio_id=portfolio_id, date=first_day or utcnow().date(), amount=opening,
                             memo="Opening balance (from the Alpaca account)"))
    audit.record(session, actor="rebuild", entity_type="portfolio", entity_id=portfolio_id, action="rebuilt_from_broker",
                 detail={"fills": len(fills), "orders": len(orders), "opening_balance": opening, "not_understood": skipped})
    session.commit()

    sync_prices(session, client)
    sync_option_marks(session, client)
    today = utcnow().date()
    marks = {}
    for p in held:
        sec = session.execute(select(Security).where(Security.ticker == position_ticker(p))).scalar_one_or_none()
        if sec is not None and p.get("current_price"):
            marks[sec.id] = float(p["current_price"])
    priced = set(latest_prices(session, list(marks), today).index)
    upsert_prices(session, [{"security_id": sid, "date": today, "close": px} for sid, px in marks.items() if sid not in priced])
    session.commit()
    rec = reconcile(session, client, portfolio_id, apply=True, actor="rebuild")
    return {"rebuilt": True, "fills": len(fills), "orders": len(orders), "opening_balance": opening,
            "positions": sorted(t for t, q in quantity.items() if abs(q) > 1e-9), "clean": rec["clean"],
            "not_understood": sorted(set(skipped))}


def adopt_account(session: Session, client: AlpacaClient, portfolio_id: int) -> dict:
    """Start an empty ledger from what the broker already holds, so a fresh database (a new
    machine, a new deployment) carries on with the same account instead of disagreeing with it.

    Each position is booked as bought at the broker's average entry price, already settled, and
    the portfolio is funded so that its cash equals the broker's. Does nothing if the ledger
    already has a trade or a cash movement. Short positions are reported, not adopted."""
    used = session.execute(select(func.count(Trade.id)).where(Trade.portfolio_id == portfolio_id)).scalar_one() or \
        session.execute(select(func.count(CashFlow.id)).where(CashFlow.portfolio_id == portfolio_id)).scalar_one()
    if used:
        return {"adopted": False, "reason": "the ledger already has history"}
    acct, held = client.account(), client.positions()
    today, cost, taken, skipped = utcnow().date(), 0.0, [], []
    fallback: dict[int, float] = {}  # the broker's own mark, for anything the price feeds cannot price
    kinds = {"us_equity": "Equity", "crypto": "Crypto", "us_option": "Option"}
    for p in held:
        ticker, qty, price = position_ticker(p), float(p["qty"]), float(p["avg_entry_price"])
        if qty <= 0:
            skipped.append(ticker)
            continue
        sec = session.execute(select(Security).where(Security.ticker == ticker)).scalar_one_or_none()
        if sec is None:
            parsed = parse_occ(ticker) if p.get("asset_class") == "us_option" else None
            if parsed:
                root, expiry, kind, strike = parsed
                sec = ensure_option_security(session, OptionQuote(ticker, root, expiry, kind, strike, *([None] * 9)))
            else:
                sec = Security(ticker=ticker, name=ticker, asset_class=kinds.get(p.get("asset_class"), "Equity"),
                               currency="USD", country="US", issuer=ticker, multiplier=1.0)
                session.add(sec)
                session.flush()
        session.add(Trade(portfolio_id=portfolio_id, security_id=sec.id, side=Side.BUY.value, quantity=qty, price=price,
                          currency="USD", trade_date=today, settle_date=today))
        cost += qty * price * sec.multiplier
        taken.append(ticker)
        fallback[sec.id] = float(p.get("current_price") or price)
    session.add(CashFlow(portfolio_id=portfolio_id, date=today, amount=float(acct["cash"]) + cost,
                         memo="Opening balance adopted from the Alpaca account"))
    audit.record(session, actor="adopt", entity_type="portfolio", entity_id=portfolio_id, action="adopted_broker_account",
                 detail={"positions": taken, "skipped_short": skipped, "cash": float(acct["cash"])})
    session.commit()
    sync_prices(session, client)
    sync_option_marks(session, client)
    priced = set(latest_prices(session, list(fallback), today).index)
    upsert_prices(session, [{"security_id": sid, "date": today, "close": px} for sid, px in fallback.items() if sid not in priced])
    session.commit()
    return {"adopted": True, "positions": taken, "skipped_short": skipped, "cash": float(acct["cash"])}


def _qty(q: float) -> str:
    return str(int(q)) if float(q).is_integer() else f"{q:.6f}".rstrip("0").rstrip(".")


class AlpacaPaperBroker:
    """Routes orders to an Alpaca paper account and waits briefly for the fill."""

    name = "alpaca-paper"
    live = False  # paper keys cannot reach real money

    def __init__(self, client: AlpacaClient | None = None, fill_timeout: float = 20.0, poll_seconds: float = 1.0,
                 sleep=time.sleep):
        self.client = client or AlpacaClient()
        if not self.client.paper:
            raise ValueError(
                f"AlpacaPaperBroker only talks to {PAPER_HOST}; got {self.client.trading_url}. "
                "Live trading needs a separate broker that passes the live-mode and approval gates."
            )
        self.fill_timeout = fill_timeout
        self.poll_seconds = poll_seconds
        self._sleep = sleep

    def submit(self, session: Session, order: Order) -> BrokerFill:
        security = session.get(Security, order.security_id)
        coin = security.asset_class == "Crypto"
        quantity = order.remaining_quantity
        try:
            if not coin:  # coins trade around the clock
                clock = self.client.clock()
                if not clock.get("is_open"):
                    raise BrokerReject(f"market is closed; next open {clock.get('next_open')}")
            if settings.alpaca_cash_only:
                multiplier = str(self.client.account().get("multiplier"))
                if multiplier != "1":
                    raise BrokerReject(
                        f"cash-only mode, but the Alpaca account can borrow (margin multiplier {multiplier}); "
                        "run `spectre alpaca-margin 1` to turn margin off"
                    )
            if coin and order.side == Side.SELL.value:
                # The fee on a coin purchase is taken in coin, so the broker can hold a shade
                # less than the ledger until that fee is booked. Sell what is really there.
                have = position_quantities(self.client.positions()).get(security.ticker, 0.0)
                quantity = min(quantity, math.floor(have * 1e6) / 1e6)
                if quantity <= 0:
                    raise BrokerReject(f"the broker holds no {security.ticker} to sell")
            limit = order.limit_price if order.order_type == OrderType.LIMIT.value else None
            prices = self._ladder(security, order.side, limit)
            wait = self.fill_timeout / len(prices)
            done, paid, last_id = 0.0, 0.0, None
            for price in prices:
                body = {
                    "symbol": f"{security.ticker}/USD" if coin else security.ticker, "qty": _qty(quantity - done),
                    "side": order.side.lower(), "type": "market", "time_in_force": "gtc" if coin else "day",
                    "client_order_id": f"spectre-{order.id}-{uuid.uuid4().hex[:8]}",
                }
                if price is not None:
                    body.update(type="limit", limit_price=f"{price:.2f}")
                placed = self._work(body, wait)
                got = float(placed.get("filled_qty") or 0)
                if got > 0 and placed.get("filled_avg_price"):
                    done += got
                    paid += got * float(placed["filled_avg_price"])
                    last_id = placed["id"]
                if quantity - done <= 1e-9:
                    break
        except AlpacaError as exc:
            raise BrokerReject(f"alpaca: {exc}") from exc
        if done <= 0:
            raise BrokerReject(f"not filled within {self.fill_timeout:.0f}s; cancelled")
        return BrokerFill(done, paid / done, utcnow(), broker_order_id=last_id)

    def _work(self, body: dict, wait: float) -> dict:
        """Place one order, give it `wait` seconds, cancel whatever is left, and return how it ended."""
        placed = self.client.submit_order(body)
        deadline = time.monotonic() + wait
        while placed.get("status") != "filled":
            if placed.get("status") in DONE_BADLY:
                raise BrokerReject(f"alpaca order ended as {placed.get('status')}")
            if time.monotonic() >= deadline:
                break
            self._sleep(self.poll_seconds)
            placed = self.client.get_order(placed["id"])
        if placed.get("status") != "filled":
            # Out of time: cancel what is left and keep whatever did fill.
            try:
                self.client.cancel_order(placed["id"])
            except AlpacaError:
                pass  # already filled or already gone; the re-read below tells us which
            placed = self.client.get_order(placed["id"])
        return placed

    def _ladder(self, security: Security, side: str, limit: float | None) -> list[float | None]:
        """The prices to try, in order. A market order has none; a limit order has its limit.

        An option's bid and ask sit far apart, and an order placed at the far side pays the whole
        gap. So an option order starts at the midpoint and steps toward the far side (halfway,
        then the quote, then the order's own limit), taking the first price someone will trade
        at. The order's limit is always the last and worst price tried."""
        if limit is None:
            return [None]
        if security.asset_class != "Option":
            return [limit]
        try:
            quotes = self.client.option_snapshots([security.ticker])
        except AlpacaError:
            return [limit]
        q = quotes[0] if quotes else None
        if q is None or q.mid is None or not q.bid:
            return [limit]
        if side == Side.BUY.value:
            steps = [p for p in (q.mid, (q.mid + q.ask) / 2, q.ask) if p < limit]
        else:
            steps = [p for p in (q.mid, (q.mid + q.bid) / 2, q.bid) if p > limit]
        out: list[float | None] = []
        for p in [*steps, limit]:
            p = round(p, 2)
            if p > 0 and p not in out:
                out.append(p)
        return out
