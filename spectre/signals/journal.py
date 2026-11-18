"""The bot's journal: every decision cycle written down, so the dashboard can show what KAIROS
is doing and why without anyone reading a log file."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.models import BotDecision


def _now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def record_cycle(session: Session, portfolio_id: int, actions: list[tuple[str, dict]], notes: list[str],
                 buy_zone: list[str] | None = None, at: datetime | None = None) -> int:
    """Write one cycle to the journal. `actions` are (book, action) pairs as the strategies
    report them; `notes` are plain remarks (market closed, a fee booked). A cycle that did
    nothing still leaves one line, so "when did it last look?" always has an answer."""
    at = at or _now()
    rows = [BotDecision(portfolio_id=portfolio_id, at=at, book="system", outcome="note", why=note) for note in notes]
    for book, a in actions:
        why = a.get("why") or ""
        detail = a.get("detail") or ""
        if detail and a.get("outcome") != "executed":
            why = f"{why} — {detail}" if why else detail
        rows.append(BotDecision(
            portfolio_id=portfolio_id, at=at, book=book, ticker=a.get("ticker"), side=a.get("side"),
            quantity=a.get("quantity"), price=a.get("fill_price") or a.get("price"), outcome=a.get("outcome", "?"),
            why=why, order_id=a.get("order_id"),
        ))
    if not actions:
        zone = ", ".join(buy_zone or []) or "nothing"
        rows.append(BotDecision(portfolio_id=portfolio_id, at=at, book="system", outcome="idle",
                                why=f"Looked and found nothing to do. In the buy zone: {zone}."))
    session.add_all(rows)
    session.commit()
    return len(rows)


def recent(session: Session, portfolio_id: int, limit: int = 60, include_idle: bool = False) -> dict:
    """The newest journal lines, and when the bot last looked at all."""
    last = session.execute(
        select(BotDecision.at).where(BotDecision.portfolio_id == portfolio_id).order_by(BotDecision.at.desc()).limit(1)
    ).scalar_one_or_none()
    q = select(BotDecision).where(BotDecision.portfolio_id == portfolio_id)
    if not include_idle:
        q = q.where(BotDecision.outcome != "idle")
    rows = session.execute(q.order_by(BotDecision.at.desc(), BotDecision.id.desc()).limit(limit)).scalars().all()
    return {
        "last_looked_at": last.isoformat(timespec="seconds") if last else None,
        "minutes_since": (_now() - last).total_seconds() / 60 if last else None,
        "decisions": [
            {"at": r.at.isoformat(timespec="seconds"), "book": r.book, "ticker": r.ticker, "side": r.side, "quantity": r.quantity,
             "price": r.price, "outcome": r.outcome, "why": r.why, "order_id": r.order_id}
            for r in rows
        ],
    }
