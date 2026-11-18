"""What trading actually costs, measured from SPECTRE's own fills.

Every order remembers the market price SPECTRE held when it was decided (its arrival price: for
stocks the last trade, for coins and options the middle of the quote). The cost of an order is
how much worse its fills were than that: paying more on a buy, or receiving less on a sale.
A fill better than the arrival price is a negative cost. Fees are counted separately, by book.

Two things this is for:
- seeing whether orders are being worked well (a wide gap on options means the ladder is
  crossing too much of the spread);
- replacing guesses about costs with measurements. An edge the signal check finds is only worth
  trading if it is bigger than one trip in and out, and `round_trip` is that trip, measured.

One order tells nothing: prices move between deciding and filling, for or against, by more than
the cost itself. The average over many orders is what means something, so a book's figure is
only offered as measured once it rests on `ENOUGH_ORDERS` of them.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.models import Order, Security, Side, Trade
from spectre.portfolio.performance import sleeve_of

ENOUGH_ORDERS = 20
BOOKS = ("Stocks and funds", "Options", "Coins")


def execution_costs(session: Session, portfolio_id: int | None = None, since: datetime | None = None) -> dict:
    """Slippage against the arrival price and fees, by book, over every filled order (of one
    portfolio, or all of them) since `since`."""
    q = (select(Order, Security).join(Security, Security.id == Order.security_id)
         .where(Order.filled_quantity > 0, Order.avg_fill_price.is_not(None)))
    if portfolio_id is not None:
        q = q.where(Order.portfolio_id == portfolio_id)
    if since is not None:
        q = q.where(Order.created_at >= since)
    def empty() -> dict:
        return {"orders": 0, "traded": 0.0, "slippage": 0.0}

    books = {name: {"book": name, **empty(), "not_measured": 0, "fees": 0.0, "ledger_traded": 0.0,
                    "buys": empty(), "sells": empty()} for name in BOOKS}
    lines = []
    for order, sec in session.execute(q.order_by(Order.created_at)).all():
        book = books.get(sleeve_of(sec.asset_class))
        if book is None:
            continue
        if not order.arrival_price:
            book["not_measured"] += 1
            continue
        sign = 1.0 if order.side == Side.BUY.value else -1.0
        traded = order.filled_quantity * order.arrival_price * sec.multiplier
        cost = sign * (order.avg_fill_price - order.arrival_price) * order.filled_quantity * sec.multiplier
        side = book["buys" if sign > 0 else "sells"]
        for bucket in (book, side):
            bucket["orders"] += 1
            bucket["traded"] += traded
            bucket["slippage"] += cost
        lines.append({"order_id": order.id, "at": order.created_at.isoformat(timespec="seconds"), "book": book["book"],
                      "ticker": sec.ticker, "side": order.side, "quantity": order.filled_quantity,
                      "arrival_price": order.arrival_price, "fill_price": order.avg_fill_price, "cost": cost,
                      "cost_pct": cost / traded if traded else None})

    # Fees by book as a share of everything traded in it, both from the ledger (coin fees are
    # taken in coin and booked there as their own lines, which carry no order).
    fq = (select(Trade.fees, Trade.quantity, Trade.price, Trade.order_id, Security.asset_class, Security.multiplier)
          .join(Security, Security.id == Trade.security_id))
    if portfolio_id is not None:
        fq = fq.where(Trade.portfolio_id == portfolio_id)
    if since is not None:
        fq = fq.where(Trade.trade_date >= since.date())
    for fees, quantity, price, order_id, asset_class, multiplier in session.execute(fq).all():
        book = books.get(sleeve_of(asset_class))
        if book is None:
            continue
        book["fees"] += fees or 0.0
        if order_id is not None:
            book["ledger_traded"] += quantity * price * multiplier

    out = []
    for book in books.values():
        if not book["orders"] and not book["not_measured"]:
            continue
        for bucket in (book, book["buys"], book["sells"]):
            bucket["slippage_pct"] = bucket["slippage"] / bucket["traded"] if bucket["traded"] else None
        book["fees_pct"] = book["fees"] / book["ledger_traded"] if book["ledger_traded"] else None
        book["enough"] = book["orders"] >= ENOUGH_ORDERS
        book["round_trip_pct"] = _round_trip(book)
        out.append(book)
    worst = sorted(lines, key=lambda r: r["cost"], reverse=True)[:5]
    return {"books": out, "orders": sum(b["orders"] for b in out), "not_measured": sum(b["not_measured"] for b in out),
            "slippage": sum(b["slippage"] for b in out), "fees": sum(b["fees"] for b in out), "worst": worst,
            "recent": lines[-10:][::-1], "enough_orders": ENOUGH_ORDERS}


def _round_trip(book: dict) -> float | None:
    """One trip in and out as a share of the money moved: the buying gap, the selling gap and
    the fee each way. With only one side measured the other is taken to cost the same."""
    buy, sell = book["buys"].get("slippage_pct"), book["sells"].get("slippage_pct")
    if buy is None and sell is None:
        return None
    buy = sell if buy is None else buy
    sell = buy if sell is None else sell
    return buy + sell + 2 * (book.get("fees_pct") or 0.0)


def round_trip(session: Session, book: str, fallback: float) -> tuple[float, bool]:
    """The cost of one trip in and out for a book: (measured figure, True) once enough of
    SPECTRE's own orders stand behind it, else (`fallback`, False). Never below zero: a run of
    lucky fills is not a reason to treat trading as free."""
    for b in execution_costs(session)["books"]:
        if b["book"] == book and b["enough"] and b["round_trip_pct"] is not None:
            return max(b["round_trip_pct"], 0.0), True
    return fallback, False


def backfill_arrival_prices(session: Session, client, portfolio_id: int | None = None) -> dict:
    """Give orders made before arrival prices were kept one from history: the close of the last
    full minute before the order was created, from Alpaca's one-minute prices. Stocks, funds
    and coins only; there is no such history for an option's quote."""
    from spectre.signals.intraday import PricePath

    q = (select(Order, Security).join(Security, Security.id == Order.security_id)
         .where(Order.arrival_price.is_(None), Order.filled_quantity > 0, Security.asset_class != "Option"))
    if portfolio_id is not None:
        q = q.where(Order.portfolio_id == portfolio_id)
    rows = session.execute(q).all()
    if not rows:
        return {"filled_in": 0, "left": 0}
    start = min(o.created_at for o, _ in rows).replace(tzinfo=None) - timedelta(minutes=30)
    coins = sorted({s.ticker for _, s in rows if s.asset_class == "Crypto"})
    stocks = sorted({s.ticker for _, s in rows if s.asset_class != "Crypto"})
    bars: dict = {}
    if stocks:
        bars.update(client.stock_bars(stocks, start, timeframe="1Min", adjustment="raw"))
    if coins:
        bars.update(client.crypto_bars(coins, start, timeframe="1Min"))
    path = PricePath(bars, bar_minutes=1, stale_minutes=10)
    done = 0
    for order, sec in rows:
        price = path.at(sec.ticker, order.created_at.replace(tzinfo=None))
        if price:
            order.arrival_price = price
            done += 1
    session.commit()
    return {"filled_in": done, "left": len(rows) - done}
