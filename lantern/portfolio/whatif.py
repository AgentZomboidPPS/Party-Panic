"""What-if analysis: apply hypothetical trades to a valued portfolio without touching the ledger."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from sqlalchemy.orm import Session

from lantern.marketdata.fx import fx_rate
from lantern.marketdata.prices import latest_prices
from lantern.models import Security, Side
from lantern.portfolio.positions import EPS, ValuedPositions, position_row, reweight, securities_value_of


@dataclass(frozen=True)
class ProposedTrade:
    security_id: int
    side: Side
    quantity: float
    price: float | None = None  # None = use latest market price

    @property
    def signed_quantity(self) -> float:
        return self.quantity if self.side == Side.BUY else -self.quantity


def apply_trades(
    session: Session,
    valued: ValuedPositions,
    trades: list[ProposedTrade],
    as_of: date | None = None,
) -> ValuedPositions:
    as_of = as_of or valued.as_of
    df = valued.positions.copy()
    cash = valued.cash

    for t in trades:
        if t.quantity <= 0:
            raise ValueError("Proposed trade quantity must be positive")
        sid = t.security_id
        if sid in df.index:
            price = t.price if t.price is not None else float(df.at[sid, "price"])
            fx = float(df.at[sid, "fx_rate"])
            mult = float(df.at[sid, "multiplier"])
            df.at[sid, "quantity"] = float(df.at[sid, "quantity"]) + t.signed_quantity
        else:
            sec = session.get(Security, sid)
            if sec is None:
                raise LookupError(f"Security {sid} not found")
            if t.price is not None:
                price = t.price
            else:
                px = latest_prices(session, [sid], as_of)
                if sid not in px.index:
                    raise LookupError(f"No price for {sec.ticker} on or before {as_of}")
                price = float(px[sid])
            fx = fx_rate(session, sec.currency, valued.base_currency, as_of)
            mult = float(sec.multiplier)
            df.loc[sid] = position_row(sec, t.signed_quantity, price, fx)
        cash -= t.signed_quantity * price * mult * fx

    df = df[df["quantity"].abs() > EPS]
    df = reweight(df, securities_value_of(df) + cash)
    df.index.name = "security_id"
    return ValuedPositions(
        portfolio_id=valued.portfolio_id,
        portfolio_name=valued.portfolio_name,
        as_of=as_of,
        base_currency=valued.base_currency,
        positions=df,
        cash=cash,
    )
