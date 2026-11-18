"""Options in the risk numbers.

An option has no useful price history of its own: the contract is weeks old and its price is
driven by the stock underneath. So for risk it is treated through its **delta**: an option
moves about `leverage` percent for each one percent move in the underlying, where

    leverage = delta x underlying price / option price

(negative for a put). A bought option cannot lose more than was paid for it, so its modelled
return is floored at -100%.

This is the first-order picture only. It ignores how delta itself changes on a large move
(gamma), changes in implied volatility (vega) and the passing of time (theta), so it overstates
the loss on a bought option in a big move and says nothing about decay. Good enough to stop
options showing up as riskless or breaking the calculation; not a pricing model.
"""

from __future__ import annotations

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.execution.models import OptionMark
from spectre.marketdata.prices import latest_prices
from spectre.models import Security
from spectre.portfolio.positions import ValuedPositions

COLUMNS = ["ticker", "underlying", "underlying_id", "underlying_class", "delta", "leverage"]


def option_exposures(session: Session, valued: ValuedPositions) -> pd.DataFrame:
    """One row per option position (indexed by security id). `leverage` is missing when the
    contract has no stored delta or its underlying cannot be priced; such a position is left
    out of the risk numbers and named, never silently treated as safe."""
    opts = valued.positions[valued.positions["asset_class"] == "Option"]
    rows: dict[int, dict] = {}
    for sid, row in opts.iterrows():
        mark = session.get(OptionMark, int(sid))
        under = None
        if mark is not None:
            under = session.execute(select(Security).where(Security.ticker == mark.underlying)).scalar_one_or_none()
        out = {"ticker": row["ticker"], "underlying": mark.underlying if mark else None,
               "underlying_id": under.id if under else None, "underlying_class": under.asset_class if under else None,
               "delta": mark.delta if mark else None, "leverage": None}
        price = float(row["price"])
        if mark is not None and mark.delta is not None and under is not None and price > 0:
            spot = mark.underlying_price
            if not spot:
                px = latest_prices(session, [under.id], valued.as_of)
                spot = float(px[under.id]) if under.id in px.index else None
            if spot:
                out["leverage"] = float(mark.delta) * float(spot) / price
        rows[int(sid)] = out
    df = pd.DataFrame.from_dict(rows, orient="index", columns=COLUMNS)
    df.index.name = "security_id"
    return df


def market_exposure(session: Session, valued: ValuedPositions, options: pd.DataFrame | None = None) -> dict:
    """How much market the portfolio is really carrying, as money and as a share of its value.

    A share or a coin counts at its market value. An option counts at its **delta-equivalent**:
    the amount of the underlying it behaves like (contracts x multiplier x delta x underlying
    price; negative for a put). That is usually many times what the option cost, which is why a
    portfolio that borrows nothing can still carry more market than it is worth. A contract
    with no delta is counted at its cost and listed under `not_modelled`."""
    opts = option_exposures(session, valued) if options is None else options
    df = valued.positions
    parts = {"stocks_and_funds": 0.0, "coins": 0.0, "options_delta_equivalent": 0.0, "other": 0.0}
    premium, unmodelled = 0.0, []
    for sid, row in df.iterrows():
        mv, kind = float(row["market_value"]), row["asset_class"]
        if kind == "Option":
            premium += mv
            lev = opts.at[sid, "leverage"] if sid in opts.index else None
            if lev is None or pd.isna(lev):
                unmodelled.append(str(row["ticker"]))
                parts["options_delta_equivalent"] += mv
            else:
                parts["options_delta_equivalent"] += mv * float(lev)
        elif kind in ("Equity", "Fund"):
            parts["stocks_and_funds"] += mv
        elif kind == "Crypto":
            parts["coins"] += mv
        else:
            parts["other"] += mv
    net = sum(parts.values())
    nav = valued.total_value
    return {
        "net": net, "net_pct": net / nav if nav else None, "by": parts, "option_premium": premium,
        "option_premium_pct": premium / nav if nav else None, "not_modelled": unmodelled,
    }
