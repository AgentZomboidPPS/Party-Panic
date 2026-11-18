"""Source adapters, tested against payloads shaped like the real API responses.

The payloads are hand-written to mirror the field names and types the live services returned
on 2026-11-18 (prices as dollar strings on Kalshi, JSON-encoded lists on Polymarket, and so
on). The content is invented: no real user posts are stored in this repository.
"""

from datetime import datetime, timedelta

import pytest
from sqlalchemy import select

from lantern.db import init_db, make_engine, make_session_factory
from lantern.marketdata.universe import UNIVERSE, firehose_keywords, seed_universe
from lantern.signals import aggregate
from lantern.signals.models import PredictionMarket, SearchTrend, SocialPost
from lantern.signals.pipeline import Pipeline, build_extractor
from lantern.signals.sources import bluesky, kalshi, polymarket, stocktwits, trends
from lantern.signals.sources.base import MarketQuote, Post, TrendItem

NOW = datetime(2026, 11, 18, 17, 0, 0)

# ---------------------------------------------------------------- Kalshi


def _kalshi_market(ticker, sub, bid, ask, last, vol, **extra):
    return {"ticker": ticker, "yes_sub_title": sub, "status": "active", "market_type": "binary",
            "yes_bid_dollars": bid, "yes_ask_dollars": ask, "last_price_dollars": last, "volume_fp": vol,
            "open_interest_fp": "100.00", "close_time": "2026-12-09T19:00:00Z", **extra}


def test_kalshi_event_parsing_uses_dollar_strings_and_ranks_by_volume():
    event = {
        "event_ticker": "KXFEDDECISION-26DEC", "title": "Fed decision in December?", "category": "Economics",
        "markets": [
            _kalshi_market("KXFED-26DEC-H0", "Hold", "0.8100", "0.8300", "0.8000", "52000.00"),
            _kalshi_market("KXFED-26DEC-C25", "Cut 25bp", "0.1500", "0.1700", "0.1600", "91000.50"),
            _kalshi_market("KXFED-26DEC-C50", "Cut 50bp", "0.0000", "0.0000", "0.0000", "0.00"),  # never traded
            _kalshi_market("KXFED-26DEC-WIDE", "Hike", "0.0100", "0.6000", "0.0200", "300.00"),  # wide book
            _kalshi_market("KXMVE-X", "parlay", "0.3000", "0.3200", "0.3100", "9e9", mve_collection_ticker="KXMVE"),
        ],
    }
    quotes = kalshi.parse_event(event, NOW, max_markets=3)
    assert [q.market_id for q in quotes] == ["KXFED-26DEC-C25", "KXFED-26DEC-H0", "KXFED-26DEC-WIDE"]
    cut, hold, wide = quotes
    assert cut.yes_price == pytest.approx(0.16) and cut.volume == pytest.approx(91000.5)
    assert cut.title == "Fed decision in December? — Cut 25bp" and cut.category == "Economics"
    assert cut.close_time == datetime(2026, 12, 9, 19, 0)
    assert hold.yes_price == pytest.approx(0.82)
    assert wide.yes_price == pytest.approx(0.02), "a wide book falls back to the last trade, not the mid"


def test_kalshi_single_market_event_keeps_plain_title():
    event = {"title": "Recession in 2027?", "category": "Economics",
             "markets": [_kalshi_market("KXREC-27", "Before 2028", "0.3000", "0.3400", "0.3100", "5000.00")]}
    (q,) = kalshi.parse_event(event, NOW)
    assert q.title == "Recession in 2027?" and q.yes_price == pytest.approx(0.32)


# ---------------------------------------------------------------- Polymarket


def _poly_market(mid, question, yes, vol24, **extra):
    return {"id": mid, "question": question, "outcomes": '["Yes", "No"]', "outcomePrices": f'["{yes}", "{1 - yes}"]',
            "volume": "3507493.65", "volume24hr": str(vol24), "liquidity": "198562.42", "endDate": "2026-12-09T23:59:00Z",
            "active": True, "closed": False, **extra}


def test_polymarket_event_parsing():
    event = {"title": "Fed Decision in December?", "markets": [
        _poly_market("1", "Fed cuts 25 bps in December?", 0.16, 500_000),
        _poly_market("2", "Fed holds in December?", 0.82, 900_000),
        _poly_market("3", "Closed one", 0.5, 9_999_999, closed=True),
        {"id": "4", "question": "Team A vs Team B", "outcomes": '["Team A", "Team B"]', "outcomePrices": '["0.4", "0.6"]',
         "volume24hr": "8000000"},
    ]}
    quotes = polymarket.parse_event(event, NOW, "fed", max_markets=5)
    assert [q.market_id for q in quotes] == ["2", "1"], "ranked by 24h volume; closed and non-binary skipped"
    assert quotes[0].yes_price == pytest.approx(0.82) and quotes[0].category == "fed"
    assert quotes[0].volume == pytest.approx(3507493.65) and quotes[0].close_time == datetime(2026, 12, 9, 23, 59)
    assert polymarket.parse_market({"id": "9", "outcomes": "not json", "outcomePrices": "[]"}, NOW) is None


# ---------------------------------------------------------------- Stocktwits


def test_stocktwits_message_parsing():
    msg = {"id": 669492151, "body": "$NVDA loading calls into earnings", "created_at": "2026-11-18T17:15:27Z",
           "user": {"id": 12345, "followers": 17, "join_date": "2022-10-24", "username": "someone"},
           "entities": {"media": [], "sentiment": {"basic": "Bullish"}, "discussable": None},
           "symbols": [{"symbol": "NVDA"}, {"symbol": "SPY"}],
           "prices": [{"id": 2925, "symbol": "NVDA", "symbol_mic": "NVDA.XNAS", "price": "151.43"},
                      {"symbol": "SPY", "price": "not a number"}]}
    p = stocktwits.parse_message(msg)
    assert p.meta["prices"] == {"NVDA": 151.43}, "prices arrive as strings; junk is dropped"
    assert p.external_id == "669492151" and p.author_id == "12345" and p.source_sentiment == "Bullish"
    assert p.created_at == datetime(2026, 11, 18, 17, 15, 27) and p.followers == 17
    assert p.account_age_days == (datetime(2026, 11, 18, 17, 15, 27) - datetime(2022, 10, 24)).days
    assert p.meta["symbols"] == ["NVDA", "SPY"]
    unlabelled = stocktwits.parse_message({**msg, "id": 2, "entities": {"sentiment": None}})
    assert unlabelled.source_sentiment is None
    assert stocktwits.parse_message({"id": 3, "created_at": "2026-11-18T17:15:27Z", "body": ""}) is None


# ---------------------------------------------------------------- Bluesky


def _commit(text, langs=("en",), created=None, **record):
    from lantern.signals.sources.base import utcnow

    created = created or (utcnow().isoformat() + "Z")
    return {"did": "did:plc:abc123", "time_us": 1, "kind": "commit",
            "commit": {"rev": "r", "operation": "create", "collection": "app.bsky.feed.post", "rkey": "3kabc", "cid": "c",
                       "record": {"$type": "app.bsky.feed.post", "createdAt": created, "langs": list(langs), "text": text,
                                  **record}}}


def test_bluesky_commit_parsing_and_non_posts():
    p = bluesky.parse_commit(_commit("Nvidia earnings tonight", reply={"root": {}}))
    assert p.external_id == "did:plc:abc123/3kabc" and p.author_id == "did:plc:abc123" and p.lang == "en"
    assert p.meta["is_reply"] is True and p.url.endswith("/post/3kabc")
    assert bluesky.parse_commit({"kind": "identity", "did": "did:plc:x"}) is None
    delete = _commit("x")
    delete["commit"]["operation"] = "delete"
    assert bluesky.parse_commit(delete) is None
    like = _commit("x")
    like["commit"]["collection"] = "app.bsky.feed.like"
    assert bluesky.parse_commit(like) is None


def test_bluesky_client_clock_is_not_trusted():
    from lantern.signals.sources.base import utcnow

    p = bluesky.parse_commit(_commit("backdated", created="2019-01-01T00:00:00.000Z"))
    assert abs((utcnow() - p.created_at).total_seconds()) < 5
    ahead = (utcnow() + timedelta(minutes=2)).isoformat() + "Z"
    p = bluesky.parse_commit(_commit("device clock runs fast", created=ahead))
    assert p.created_at <= utcnow(), "a post can never be dated in the future"


def test_bluesky_filtering_matches_whole_words_and_cashtags():
    src = bluesky.BlueskyJetstream(keywords=["the fed", "stocks", "s&p 500"])
    keep = lambda text, langs=("en",): src.wanted(bluesky.parse_commit(_commit(text, langs)))  # noqa: E731
    assert keep("The Fed is meeting next week")
    assert keep("S&P 500 at a record")
    assert keep("no keyword here but $TSLA is moving")
    assert not keep("I am fed up with this"), "'fed' inside another phrase must not match 'the fed'"
    assert not keep("restocks of the new console")
    assert not keep("the fed is meeting", langs=("ja",))
    everything = bluesky.BlueskyJetstream(sample=0.2, seed=1)
    kept = sum(everything.wanted(bluesky.parse_commit(_commit(f"post {i}"))) for i in range(2000))
    assert 300 < kept < 500


# ---------------------------------------------------------------- Google Trends

TRENDS_XML = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<rss xmlns:atom="http://www.w3.org/2005/Atom" xmlns:ht="https://trends.google.com/trending/rss" version="2.0">
  <channel><title>Daily Search Trends</title>
    <item><title>nvidia earnings</title><ht:approx_traffic>200K+</ht:approx_traffic>
      <pubDate>Wed, 18 Nov 2026 09:00:00 -0800</pubDate>
      <ht:news_item><ht:news_item_title>Nvidia tops estimates as data center sales surge</ht:news_item_title>
        <ht:news_item_source>Example News</ht:news_item_source></ht:news_item>
      <ht:news_item><ht:news_item_title>What analysts expect next</ht:news_item_title></ht:news_item>
    </item>
    <item><title>celebrity wedding</title><ht:approx_traffic>5000+</ht:approx_traffic>
      <pubDate>Wed, 18 Nov 2026 07:30:00 -0800</pubDate></item>
    <item><title></title></item>
  </channel></rss>"""


def test_trends_rss_parsing():
    items = trends.parse_trends_rss(TRENDS_XML, "US", NOW)
    assert [i.term for i in items] == ["nvidia earnings", "celebrity wedding"]
    assert items[0].approx_traffic == 200_000 and items[1].approx_traffic == 5_000
    assert items[0].started_at == datetime(2026, 11, 18, 17, 0), "pubDate converted to UTC"
    assert items[0].headlines == ["Nvidia tops estimates as data center sales surge", "What analysts expect next"]
    assert trends.parse_traffic("2M+") == 2_000_000 and trends.parse_traffic(None) is None
    with pytest.raises(ValueError):
        trends.parse_trends_rss('<!DOCTYPE x [<!ENTITY a "b">]><rss/>', "US", NOW)


# ---------------------------------------------------------------- universe + extractor + pipeline


@pytest.fixture
def real_db():
    e = make_engine("sqlite://")
    init_db(e)
    factory = make_session_factory(e)
    with factory() as s:
        summary = seed_universe(s)
        assert summary["added"] == len(UNIVERSE)
        assert seed_universe(s)["added"] == 0, "seeding twice adds nothing"
    return factory


def test_extractor_handles_ambiguous_company_names(real_db):
    with real_db() as s:
        ex = build_extractor(s).extract
    assert ex("Nvidia just reported") == ["NVDA"], "unambiguous name needs no context"
    assert ex("$AAPL and $brk.b on watch") == ["AAPL", "BRK.B"]
    assert ex("I ate an apple and went to Target") == [], "ordinary words are not companies"
    assert ex("Apple earnings beat, shares up") == ["AAPL"], "same word with market context is"
    assert ex("Meta stock is down after the CEO spoke") == ["META"]
    assert ex("the meta of this game is stale") == []
    assert ex("NVDA and AMD ripping") == ["NVDA", "AMD"], "bare symbols of 3+ letters"
    assert ex("ALL CAPS POST ABOUT MY CAT") == [], "CAT the symbol needs market context"
    assert ex("CAT earnings tomorrow") == ["CAT"]
    assert ex("my visa got approved") == [] and ex("Visa shares fell") == ["V"]
    assert ex("S&P 500 closes at a record") == ["SPY"]
    assert ex("bitcoin is pumping") == ["IBIT"]
    assert "goldman sachs" in firehose_keywords({"GS", "AAPL"}) and "apple" not in firehose_keywords({"GS", "AAPL"})


def test_pipeline_stores_real_shaped_items(real_db):
    pipe = Pipeline(real_db)
    post = stocktwits.parse_message({
        "id": 1, "body": "this is going much higher, loading calls", "created_at": "2026-11-18T17:15:27Z",
        "user": {"id": 7, "followers": 40, "join_date": "2020-01-01"},
        "entities": {"sentiment": {"basic": "Bullish"}}, "symbols": [{"symbol": "NVDA"}, {"symbol": "ZZZZ"}]})
    assert pipe.process_posts([post]) == 1
    quote = MarketQuote("kalshi", "KXFED-26DEC-C25", "Fed decision — Cut 25bp", 0.16, NOW, "Economics", 91000.5, 100.0)
    assert pipe.process_quotes([quote, quote]) == 1, "same market, same second: one snapshot"
    assert pipe.process_quotes([quote]) == 0, "and replaying it later is harmless"
    item = TrendItem("google_trends", "US", "nvidia earnings", NOW, NOW - timedelta(hours=2), 200_000,
                     ["Nvidia tops estimates"])
    assert pipe.process_trends([item]) == 1
    later = TrendItem("google_trends", "US", "nvidia earnings", NOW + timedelta(minutes=10), NOW - timedelta(hours=2),
                      500_000, ["Nvidia tops estimates"])
    assert pipe.process_trends([later]) == 0, "same spike is updated, not duplicated"
    with real_db() as s:
        row = s.execute(select(SocialPost)).scalar_one()
        assert row.tickers == ["NVDA"], "symbols attached by the platform count; unknown ones are dropped"
        assert row.source_sentiment == "Bullish" and row.sentiment == 0.7 and row.model_sentiment > 0
        assert s.execute(select(PredictionMarket)).scalar_one().yes_price == pytest.approx(0.16)
        trend = s.execute(select(SearchTrend)).scalar_one()
        assert trend.approx_traffic == 500_000 and trend.tickers == ["NVDA"]
        assert trend.last_seen == NOW + timedelta(minutes=10)
        (t,) = aggregate.latest_trends(s)
        assert t["term"] == "nvidia earnings" and t["tickers"] == ["NVDA"]
        assert aggregate.feed_status(s)["search_trends"] == 1


def test_prices_attached_to_posts_become_ticks_and_the_daily_close(real_db):
    from lantern.models import Portfolio, Price, Security, Side, Trade
    from lantern.portfolio.positions import value_portfolio
    from lantern.signals.models import PriceTick

    pipe = Pipeline(real_db)

    def msg(i, minute, px):
        return Post("stocktwits", str(i), f"u{i}", "$NVDA moving", NOW + timedelta(minutes=minute), "en", followers=5,
                    account_age_days=300, meta={"symbols": ["NVDA"], "prices": {"NVDA": px, "ZZZZ": 1.0}})

    pipe.process_posts([msg(1, 0, 150.0), msg(2, 5, 151.5)])
    pipe.process_posts([msg(3, 2, 150.7)])  # arrives late: a tick, but must not overwrite the newer close
    with real_db() as s:
        nvda = s.execute(select(Security).where(Security.ticker == "NVDA")).scalar_one()
        ticks = s.execute(select(PriceTick).order_by(PriceTick.observed_at)).scalars().all()
        assert [t.price for t in ticks] == [150.0, 150.7, 151.5] and {t.ticker for t in ticks} == {"NVDA"}
        close = s.execute(select(Price).where(Price.security_id == nvda.id)).scalar_one()
        assert close.close == 151.5 and close.date == NOW.date()
        # Those prices are enough to value a real position.
        pf = Portfolio(name="Real paper", base_currency="USD")
        s.add(pf)
        s.flush()
        s.add(Trade(portfolio_id=pf.id, security_id=nvda.id, side=Side.BUY.value, quantity=10, price=150.0,
                    currency="USD", trade_date=NOW.date()))
        s.commit()
        v = value_portfolio(s, pf.id)
        assert v.positions.at[nvda.id, "market_value"] == pytest.approx(1515.0)
    assert pipe.counters["price_ticks"] == 3


def test_calibration_against_user_labels(real_db):
    pipe = Pipeline(real_db)

    def msg(i, body, label):
        return Post("stocktwits", str(i), f"u{i}", body, NOW + timedelta(minutes=i), "en", followers=10,
                    account_age_days=400, source_sentiment=label, meta={"symbols": ["NVDA"]})

    pipe.process_posts([
        msg(1, "$NVDA bullish breakout, loading calls", "Bullish"),
        msg(2, "$NVDA great quarter, this rally has legs", "Bullish"),
        msg(3, "$NVDA overvalued, selloff incoming, buying puts", "Bearish"),
        msg(4, "$NVDA watching the tape here", "Bearish"),          # model sees nothing: neutral
        msg(5, "$NVDA love this dip, amazing entry", "Bearish"),    # user is bearish, text reads bullish
        msg(6, "$NVDA no label on this one", None),
    ])
    with real_db() as s:
        r = aggregate.sentiment_calibration(s)
    assert r["labelled_posts"] == 5 and r["label_bullish_share"] == pytest.approx(0.4)
    assert r["confusion"]["bull_as_bull"] == 2 and r["confusion"]["bear_as_bear"] == 1
    assert r["confusion"]["bear_as_neutral"] == 1 and r["confusion"]["bear_as_bull"] == 1
    assert r["coverage"] == pytest.approx(0.8) and r["accuracy"] == pytest.approx(0.75)
    assert r["majority_baseline"] == pytest.approx(0.6)
    with real_db() as s:
        stored = dict(s.execute(select(SocialPost.external_id, SocialPost.sentiment)).all())
    assert stored["5"] == -0.7, "the author said bearish, so aggregates treat it as bearish"
    assert stored["6"] != 0.7 and stored["6"] != -0.7, "unlabelled posts keep the model's score"
