"""Company news: fetched once, tied to the securities it names, shown newest first with holdings ahead."""

from datetime import datetime, timedelta

from sqlalchemy import func, select

from spectre.db import init_db, make_engine, make_session_factory
from spectre.marketdata.universe import seed_universe
from spectre.signals.models import NewsItem
from spectre.signals.news import recent_news, sync_news
from tests.test_strategy import book  # noqa: F401  (the fixture)

NOW = datetime(2026, 11, 18, 21, 0)


class Feed:
    def __init__(self, articles):
        self.articles, self.calls = articles, []

    def news(self, symbols, start=None, limit=50):
        self.calls.append((list(symbols), start))
        return [a for a in self.articles if set(a["symbols"]) & set(symbols)]


def article(i, headline, symbols, minutes_ago, summary=""):
    when = (NOW - timedelta(minutes=minutes_ago)).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {"id": i, "headline": headline, "summary": summary, "symbols": symbols, "created_at": when, "source": "wire",
            "url": f"https://news.example/{i}"}


def test_headlines_are_stored_once_with_their_tickers_and_tone():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        seed_universe(s)
        feed = Feed([
            article(1, "Amazon beats estimates, shares surge on strong cloud growth", ["AMZN"], 30),
            article(2, "Microsoft and Intel announce joint investment", ["MSFT", "INTC", "ZZZZ"], 60, "A new plan."),
            article(3, "Bitcoin plunges as fear spreads; investors dump crypto", ["BTCUSD"], 90),
            article(4, "Something about a company SPECTRE has never heard of", ["ZZZZ"], 10),
            {"id": 5, "headline": "", "symbols": ["AMZN"], "created_at": "2026-11-18T20:00:00Z"},
        ])
        assert sync_news(s, feed, now=NOW) == 3, "the unknown company and the empty headline are left out"
        asked = [sym for symbols, _ in feed.calls for sym in symbols]
        assert "AMZN" in asked and "BTCUSD" in asked and len(feed.calls) == 2, "coins are asked for as pairs; forty symbols a request"
        assert feed.calls[0][1] == NOW - timedelta(hours=24)

        rows = {n.id: n for n in s.execute(select(NewsItem)).scalars()}
        assert rows["alpaca:2"].tickers == ["MSFT", "INTC"] and rows["alpaca:2"].summary == "A new plan."
        assert rows["alpaca:3"].tickers == ["BTC"] and rows["alpaca:3"].sentiment < -0.2 < 0.2 < rows["alpaca:1"].sentiment
        assert rows["alpaca:1"].published_at == NOW - timedelta(minutes=30)

        assert sync_news(s, feed, now=NOW) == 0 and s.execute(select(func.count(NewsItem.id))).scalar_one() == 3
        assert feed.calls[-1][1] == NOW - timedelta(minutes=35), "next time it only asks from just before the newest it has"

        latest = recent_news(s, now=NOW)
        assert [r["tickers"][0] for r in latest] == ["AMZN", "MSFT", "BTC"], "newest first"
        mine = recent_news(s, held={"BTC", "INTC"}, now=NOW)
        assert [(r["tickers"][0], r["held"]) for r in mine] == [("MSFT", True), ("BTC", True), ("AMZN", False)], "holdings first"
        assert [r["id"] for r in recent_news(s, ticker="intc", now=NOW)] == ["alpaca:2"]
        assert recent_news(s, now=NOW + timedelta(days=5)) == [], "old headlines drop off the list"


def test_the_api_puts_news_about_holdings_first(book):  # noqa: F811
    from fastapi.testclient import TestClient

    from spectre.api.app import create_app
    from spectre.signals.sources.base import utcnow
    from spectre.signals.strategy import run_once
    from tests.test_strategy import LIMITS

    factory, pid, _ = book
    with factory() as s:
        run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)  # holds NVDA
        recent = utcnow().replace(microsecond=0)
        s.add_all([NewsItem(id="a:1", source="w", headline="Tesla news", tickers=["TSLA"], published_at=recent, sentiment=0.0),
                   NewsItem(id="a:2", source="w", headline="Nvidia news", tickers=["NVDA"], published_at=recent - timedelta(hours=1), sentiment=0.3)])
        s.commit()
        web = TestClient(create_app(engine=s.get_bind()))
        assert [r["headline"] for r in web.get("/signals/news").json()] == ["Tesla news", "Nvidia news"]
        first = web.get(f"/signals/news?portfolio_id={pid}").json()[0]
        assert first["headline"] == "Nvidia news" and first["held"] and first["tone"] == 0.3
