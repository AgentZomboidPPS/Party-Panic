"""Company news: the latest headlines about the names SPECTRE holds and watches.

From Alpaca's news feed (the same account as prices; no extra key). Each headline is stored
once with the tickers it names and the tone the sentiment scorer reads in it. This is context
for a person, shown on the dashboard beside what the crowd is saying. The bot does not trade
on it: nothing here has been measured against prices yet.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.marketdata.universe import BY_TICKER, crypto_base
from spectre.models import Security
from spectre.signals.models import NewsItem
from spectre.signals.nlp import SentimentModel
from spectre.signals.sources.base import to_naive_utc, utcnow


def sync_news(session: Session, client, hours: float = 24.0, sentiment: SentimentModel | None = None,
              now: datetime | None = None) -> int:
    """Fetch recent headlines for the real stocks, funds and coins in the book and store the new ones."""
    now = now or utcnow()
    secs = session.execute(
        select(Security.ticker, Security.asset_class).where(Security.asset_class.in_(("Equity", "Fund", "Crypto")))
    ).all()
    known = {t for t, _ in secs}
    symbols = sorted(f"{t}USD" if kind == "Crypto" else t for t, kind in secs if t in BY_TICKER)
    if not symbols:
        return 0
    newest = session.execute(select(NewsItem.published_at).order_by(NewsItem.published_at.desc()).limit(1)).scalar_one_or_none()
    start = max(newest - timedelta(minutes=5), now - timedelta(hours=hours)) if newest else now - timedelta(hours=hours)
    sentiment = sentiment or SentimentModel()
    added = 0
    for i in range(0, len(symbols), 40):
        articles = client.news(symbols[i : i + 40], start=start)
        ids = [f"alpaca:{a['id']}" for a in articles if a.get("id") is not None and a.get("headline")]
        have = set(session.execute(select(NewsItem.id).where(NewsItem.id.in_(ids))).scalars()) if ids else set()
        for a in articles:
            key = f"alpaca:{a.get('id')}"
            if a.get("id") is None or not a.get("headline") or key in have:
                continue
            tickers = [t for t in dict.fromkeys(crypto_base(sym) or sym for sym in a.get("symbols") or []) if t in known]
            if not tickers:
                continue
            text = a["headline"] + (". " + a["summary"] if a.get("summary") else "")
            session.add(NewsItem(
                id=key, source=(a.get("source") or "alpaca")[:64], headline=a["headline"], summary=a.get("summary") or None,
                url=(a.get("url") or None), tickers=tickers, sentiment=sentiment.score(text),
                published_at=to_naive_utc(datetime.fromisoformat(a["created_at"].replace("Z", "+00:00"))),
            ))
            have.add(key)
            added += 1
    session.commit()
    return added


def recent_news(session: Session, limit: int = 25, ticker: str | None = None, held: set[str] | None = None,
                hours: float = 48.0, now: datetime | None = None) -> list[dict]:
    """The latest headlines, newest first. With `held`, headlines about those names come first
    (still newest first within each group) and are marked."""
    now = now or utcnow()
    rows = session.execute(
        select(NewsItem).where(NewsItem.published_at >= now - timedelta(hours=hours)).order_by(NewsItem.published_at.desc()).limit(400)
    ).scalars().all()
    held = held or set()
    out = []
    for n in rows:
        if ticker and ticker.upper() not in n.tickers:
            continue
        out.append({"id": n.id, "at": n.published_at.isoformat(timespec="minutes"), "tickers": n.tickers, "headline": n.headline,
                    "summary": n.summary, "url": n.url, "source": n.source, "tone": n.sentiment,
                    "held": bool(held & set(n.tickers))})
    out.sort(key=lambda r: not r["held"])  # stable: keeps newest-first inside each group
    return out[:limit]
