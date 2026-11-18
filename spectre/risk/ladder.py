"""What a market-wide move would do to the portfolio, with options priced properly.

Delta says how an option moves for a small change in its stock. Over a big move it is wrong in
a way that matters: a bought call gains faster and faster as the stock rises and loses more and
more slowly as it falls, and can never lose more than it cost. So each option here is priced
again at the moved stock price with the Black-Scholes formula, using the volatility implied by
its own current price, instead of being scaled by its delta.

The move is the same percentage for everything held ("everything falls 5% together"): shares,
funds and coins move by it, and each option is priced again on its underlying moved by it.
Bonds and anything else are left where they are. Real sell-offs are not that even, and implied
volatility usually jumps when prices fall (which helps a bought option and is left out), so
this is a map of the book's shape, not a forecast.

Alongside: what one day passing costs the options with nothing else changing (time decay), and
what a one-point rise in implied volatility is worth.

European pricing with no dividends. For the bought, weeks-long contracts held here the
difference from the exact American price is small next to the moves being asked about.
"""

from __future__ import annotations

import math
from datetime import date

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.execution.models import OptionMark
from spectre.marketdata.prices import latest_prices
from spectre.models import Security
from spectre.portfolio.positions import ValuedPositions

MOVES = (-0.10, -0.05, -0.03, -0.02, -0.01, 0.01, 0.02, 0.03, 0.05, 0.10)
RATE = 0.04  # short-term interest rate assumed; the results barely depend on it at these maturities


def _cdf(x: float) -> float:
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def bs_price(kind: str, spot: float, strike: float, years: float, vol: float, rate: float = RATE) -> float:
    """Black-Scholes price of a European call or put on a stock paying no dividend."""
    if years <= 0 or vol <= 0:
        return max(spot - strike, 0.0) if kind == "call" else max(strike - spot, 0.0)
    d1 = (math.log(spot / strike) + (rate + 0.5 * vol * vol) * years) / (vol * math.sqrt(years))
    d2 = d1 - vol * math.sqrt(years)
    if kind == "call":
        return spot * _cdf(d1) - strike * math.exp(-rate * years) * _cdf(d2)
    return strike * math.exp(-rate * years) * _cdf(-d2) - spot * _cdf(-d1)


def implied_vol(kind: str, price: float, spot: float, strike: float, years: float, rate: float = RATE) -> float | None:
    """The volatility at which Black-Scholes gives `price`, or None when no volatility does
    (a price at or below what the option would be worth if exercised now, or absurdly high)."""
    if price <= 0 or spot <= 0 or strike <= 0 or years <= 0:
        return None
    lo, hi = 0.01, 5.0
    if not bs_price(kind, spot, strike, years, lo, rate) < price < bs_price(kind, spot, strike, years, hi, rate):
        return None
    for _ in range(60):
        mid = (lo + hi) / 2
        if bs_price(kind, spot, strike, years, mid, rate) < price:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def _years(expiry: date, today: date) -> float:
    return max((expiry - today).days, 0.5) / 365.0


def ladder(session: Session, valued: ValuedPositions, moves: tuple[float, ...] = MOVES, today: date | None = None,
           rate: float = RATE) -> dict:
    """Profit and loss of the whole book for each market-wide move, by kind of holding."""
    today = today or valued.as_of
    df = valued.positions
    nav = valued.total_value
    linear = {"stocks_and_funds": 0.0, "coins": 0.0}  # market value that moves one for one
    contracts: list[dict] = []  # options that can be priced again
    by_delta: list[dict] = []  # options that cannot: scaled by delta, floored at losing everything
    left_out: list[str] = []
    for sid, row in df.iterrows():
        kind, mv = row["asset_class"], float(row["market_value"])
        if kind in ("Equity", "Fund"):
            linear["stocks_and_funds"] += mv
        elif kind == "Crypto":
            linear["coins"] += mv
        elif kind == "Option":
            mark = session.get(OptionMark, int(sid))
            price = float(row["price"])
            scale = float(row["quantity"]) * float(row["multiplier"]) * float(row["fx_rate"])
            spot = _spot(session, mark, valued.as_of) if mark is not None else None
            if mark is None or not spot or price <= 0:
                left_out.append(str(row["ticker"]))
                continue
            years = _years(mark.expiration, today)
            vol = implied_vol(mark.option_type, price, spot, mark.strike, years, rate) or mark.implied_volatility
            if vol:
                contracts.append({
                    "ticker": row["ticker"], "kind": mark.option_type, "spot": spot, "strike": mark.strike,
                    "years": years, "vol": vol, "price": price, "scale": scale,
                    # anchor on the market's own price, so "no move" is exactly no change
                    "model": bs_price(mark.option_type, spot, mark.strike, years, vol, rate),
                })
            elif mark.delta is not None:
                by_delta.append({"ticker": row["ticker"], "value": price * scale,
                                 "leverage": mark.delta * spot / price})
            else:
                left_out.append(str(row["ticker"]))

    def options_pnl(move: float, days: float = 0.0, vol_shift: float = 0.0) -> float:
        total = 0.0
        for c in contracts:
            left = max(c["years"] - days / 365.0, 0.0)
            then = bs_price(c["kind"], c["spot"] * (1 + move), c["strike"], left, c["vol"] + vol_shift, rate)
            total += max(c["price"] + then - c["model"], 0.0) * c["scale"] - c["price"] * c["scale"]
        for c in by_delta:
            total += c["value"] * max(c["leverage"] * move, -1.0)
        return total

    rows = []
    for move in sorted(moves):
        stocks, coins, options = linear["stocks_and_funds"] * move, linear["coins"] * move, options_pnl(move)
        total = stocks + coins + options
        rows.append({"move": move, "stocks_and_funds": stocks, "coins": coins, "options": options, "total": total,
                     "pct": total / nav if nav else None})
    premium = sum(c["price"] * c["scale"] for c in contracts) + sum(c["value"] for c in by_delta)
    return {
        "as_of": valued.as_of.isoformat(), "nav": nav, "moves": rows,
        "option_premium": premium, "options_priced": len(contracts),
        "options_by_delta_only": [c["ticker"] for c in by_delta], "left_out": left_out,
        "time_decay_per_day": options_pnl(0.0, days=1.0) if contracts else 0.0,
        "per_volatility_point": options_pnl(0.0, vol_shift=0.01) if contracts else 0.0,
    }


def _spot(session: Session, mark: OptionMark, as_of: date) -> float | None:
    """The underlying's latest price: from the price history when it is listed there, else the
    price stored with the option's last quote."""
    under = session.execute(select(Security.id).where(Security.ticker == mark.underlying)).scalar_one_or_none()
    if under is not None:
        px = latest_prices(session, [under], as_of)
        if under in px.index:
            return float(px[under])
    return mark.underlying_price
