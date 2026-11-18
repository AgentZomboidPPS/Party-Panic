"""Alpaca: paper trading, live prices and option chains through the official API.

Facts taken from Alpaca's own documentation and confirmed against the live service on
2026-11-18:
- paper accounts trade on paper-api.alpaca.markets; prices come from data.alpaca.markets
- paper keys and live keys are separate and cannot be used for each other
- requests carry the `APCA-API-KEY-ID` and `APCA-API-SECRET-KEY` headers
- the free plan gives real-time IEX stock prices and "indicative" option prices

`AlpacaPaperBroker` refuses to exist unless it points at the paper host, so this module cannot
move real money. A live broker would be a separate class with `live = True`, which the
execution guard only lets through in live mode with a named approver per order.
"""

from __future__ import annotations

import re
import time
import uuid
from dataclasses import asdict, dataclass
from datetime import date, datetime
from urllib.parse import urlparse

import httpx
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from spectre.config import settings
from spectre.execution.brokers import BrokerFill, BrokerReject
from spectre.execution.models import OptionMark
from spectre.marketdata.prices import latest_prices, upsert_prices
from spectre.models import Order, OrderType, Security, Trade
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
    """Store the latest traded price of each US stock or fund in the book: one tick each, and
    the day's close updated to it. Returns how many securities were priced."""
    q = select(Security).where(Security.currency == "USD", Security.asset_class.in_(("Equity", "Fund")))
    if tickers:
        q = q.where(Security.ticker.in_([t.upper() for t in tickers]))
    secs = {s.ticker: s for s in session.execute(q).scalars()}
    if not secs:
        return 0
    trades = client.latest_trades(sorted(secs))
    stamps = {at.replace(microsecond=0) for _, at in trades.values()}
    taken = set(
        session.execute(
            select(PriceTick.security_id, PriceTick.observed_at).where(
                PriceTick.source == "alpaca", PriceTick.observed_at.in_(stamps)
            )
        ).all()
    )
    closes = []
    for ticker, (price, at) in trades.items():
        sec, at = secs[ticker], at.replace(microsecond=0)
        if (sec.id, at) not in taken:
            session.add(PriceTick(security_id=sec.id, ticker=ticker, observed_at=at, price=price, source="alpaca"))
        closes.append({"security_id": sec.id, "date": at.date(), "close": price})
    upsert_prices(session, closes)
    session.commit()
    return len(trades)


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
    if mark is not None and mark > 0:
        upsert_prices(session, [{"security_id": sec.id, "date": utcnow().date(), "close": mark}])
    session.flush()
    return mark


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
    unders = {s.ticker: s.id for s in session.execute(
        select(Security).where(Security.ticker.in_({q.underlying for q in quotes}))).scalars()}
    spots = latest_prices(session, unders.values(), utcnow().date())
    for q in quotes:
        uid = unders.get(q.underlying)
        store_option_mark(session, by_symbol[q.symbol], q, float(spots[uid]) if uid in spots.index else None)
    session.commit()
    return len(quotes)


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
        try:
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
            body = {
                "symbol": security.ticker, "qty": _qty(order.remaining_quantity), "side": order.side.lower(),
                "type": "market", "time_in_force": "day",
                "client_order_id": f"spectre-{order.id}-{uuid.uuid4().hex[:8]}",
            }
            if order.order_type == OrderType.LIMIT.value and order.limit_price is not None:
                body.update(type="limit", limit_price=f"{order.limit_price:.2f}")
            placed = self.client.submit_order(body)
            deadline = time.monotonic() + self.fill_timeout
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
        except AlpacaError as exc:
            raise BrokerReject(f"alpaca: {exc}") from exc
        filled = float(placed.get("filled_qty") or 0)
        if filled <= 0 or not placed.get("filled_avg_price"):
            raise BrokerReject(f"not filled within {self.fill_timeout:.0f}s; cancelled")
        return BrokerFill(filled, float(placed["filled_avg_price"]), utcnow(), broker_order_id=placed["id"])
