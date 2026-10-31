"""Signals layer: screening, NLP, aggregation, the synthetic stream, and the backtester."""

from datetime import date, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import func, select

from lantern.api.app import create_app
from lantern.db import init_db, make_engine, make_session_factory
from lantern.marketdata.synthetic import seed_demo
from lantern.signals import aggregate, nlp, screening, signals
from lantern.signals.models import AuthorStats, SentimentBar, SocialPost, Topic
from lantern.signals.pipeline import Pipeline, build_extractor
from lantern.signals.sources.base import Post
from lantern.signals.sources.synthetic import seed_social_history

T0 = datetime(2025, 6, 2, 14, 0)


def _post(text, author="u1", at=T0, **kw):
    return Post("test", kw.pop("ext", f"{author}-{at.timestamp()}-{abs(hash(text)) % 10**6}"), author, text, at, "en", **kw)


# ---------------------------------------------------------------- screening


def test_clean_post_passes():
    sc = screening.Screener()
    r = sc.screen(_post("Bullish on $ACME, breakout above resistance with volume"), "a1")
    assert not r.screened_out and r.quality == 1.0


def test_burst_and_self_duplicate_are_flagged():
    sc = screening.Screener()
    results = [sc.screen(_post("$ACME TO THE MOON buy now!!!", at=T0 + timedelta(seconds=30 * i), ext=str(i)), "bot") for i in range(10)]
    assert results[0].quality == 1.0
    assert results[1].factors.get("self_duplicate") == 0.2 and results[1].screened_out
    assert "burst" in results[-1].factors or "burst_soft" in results[-1].factors


def test_coordinated_campaign_is_flagged():
    sc = screening.Screener(coord_authors=4)
    text = "$NOVA breaking news insiders buying massive move coming get in now"
    rs = [sc.screen(_post(text, author=f"b{i}", at=T0 + timedelta(minutes=i), ext=f"c{i}"), f"b{i}") for i in range(6)]
    assert not rs[0].screened_out
    assert rs[-1].factors.get("coordinated") == 0.2 and rs[-1].screened_out


def test_text_and_account_heuristics():
    sc = screening.Screener()
    assert sc.screen(_post("$A $B $C $D $E $F $G pump"), "x").factors.get("cashtag_stuffing") == 0.3
    assert sc.screen(_post("https://t.co/abc"), "y").reason == "link_or_empty"
    assert sc.screen(_post("a perfectly normal sentence about markets", followers=0), "z").factors.get("no_followers") == 0.5


def test_simhash_near_duplicates_are_close():
    a = screening.simhash("Acme guidance was excellent, this rally has legs")
    b = screening.simhash("Acme guidance was excellent, this rally has legs!!")
    c = screening.simhash("Regional bank stress and deposit flight talk is back")
    assert screening.hamming(a, b) <= 3 < screening.hamming(a, c)


# ---------------------------------------------------------------- nlp


def test_sentiment_and_fear():
    m = nlp.SentimentModel()
    assert m.score("Bullish, clean breakout, loading calls") > 0.3
    assert m.score("Tanking on a guidance miss, downgrade incoming, bearish") < -0.3
    assert nlp.fear_flag("recession fears are back") and not nlp.fear_flag("earnings next week, any expectations?")


def test_ticker_extraction_by_cashtag_and_alias():
    ex = nlp.TickerExtractor({"ACME", "NOVA"}, {"acme systems": "ACME", "acme": "ACME", "nova semiconductors": "NOVA"})
    assert ex.extract("Loading $acme calls, Nova Semiconductors too") == ["ACME", "NOVA"]
    assert ex.extract("$ZZZ unknown and $ACME") == ["ACME"]
    assert ex.extract("Acme is up") == ["ACME"]


def test_topic_clustering_separates_themes():
    a = [f"Recession fears back, jobless claims jumped, yield curve screaming {i}" for i in range(40)]
    b = [f"AI chip demand insane, semis leading, data center capex climbing {i}" for i in range(40)]
    clusters = nlp.cluster_topics(a + b, max_topics=2)
    assert len(clusters) == 2
    sets = [set(c.indices.tolist()) for c in clusters]
    assert any(s == set(range(40)) for s in sets) and any(s == set(range(40, 80)) for s in sets)
    labels = " ".join(c.label for c in clusters)
    assert "recession" in labels and ("chip" in labels or "semis" in labels or "ai" in labels)


# ---------------------------------------------------------------- pipeline on a tiny DB


def test_pipeline_dedups_and_stores(demo):
    s, _ = demo
    factory = make_session_factory(s.get_bind())
    pipe = Pipeline(factory)
    p1 = _post("Bullish on $ACME, Acme Systems guidance was great", ext="p1")
    n = pipe.process_posts([p1, _post("$ACME again", ext="p1"), _post("Dumping $BYTE, overvalued", ext="p2")])
    assert n == 2 and pipe.counters["duplicates"] == 1
    with factory() as q:
        row = q.execute(select(SocialPost).where(SocialPost.external_id == "p1")).scalar_one()
        assert row.tickers == ["ACME"] and row.sentiment > 0 and len(row.author_hash) == 32
        assert "acme" in build_extractor(q).aliases


# ---------------------------------------------------------------- the synthetic history end to end


@pytest.fixture(scope="module")
def social_engine():
    e = make_engine("sqlite://")
    init_db(e)
    with make_session_factory(e)() as s:
        seed_demo(s, start=date(2022, 11, 1), end=date(2025, 10, 31), seed=7)
        summary = seed_social_history(s, days=160, posts_per_day=70, seed=11, ic=0.10)
    e.social_summary = summary  # type: ignore[attr-defined]
    return e


@pytest.fixture
def social(social_engine):
    with make_session_factory(social_engine)() as s:
        yield s, social_engine.social_summary


def test_history_seeded_and_bots_screened(social):
    s, summary = social
    assert summary["days"] == 160 and summary["posts"] > 160 * 70
    bots = s.execute(select(AuthorStats).where(AuthorStats.author_hash.in_(
        select(SocialPost.author_hash).where(SocialPost.screened_out.is_(True)).distinct()))).scalars().all()
    flagged = [a for a in bots if a.flagged]
    assert len(flagged) >= 15  # the 20 bot accounts, allowing for a few quiet ones
    total = s.execute(select(func.count(SocialPost.id))).scalar_one()
    screened = s.execute(select(func.count(SocialPost.id)).where(SocialPost.screened_out.is_(True))).scalar_one()
    assert 0.05 < screened / total < 0.5
    reasons = dict(s.execute(select(SocialPost.screen_reason, func.count()).where(SocialPost.screened_out.is_(True))
                             .group_by(SocialPost.screen_reason)).all())
    assert "self_duplicate" in reasons and "coordinated" in reasons
    # The screener's quality floor: nothing a human wrote should trip it
    human_screened = s.execute(select(func.count(SocialPost.id)).where(SocialPost.screened_out.is_(True),
                                                                        SocialPost.author_quality > 0.3)).scalar_one()
    assert human_screened == 0


def test_topics_and_bars_exist_with_zscores(social):
    s, _ = social
    topics = aggregate.latest_topics(s)
    assert 2 <= len(topics) <= 10
    assert all(t.volume >= 3 and t.keywords for t in topics)
    # Across the history the narratives must surface as topics, and some topics must persist
    # from one window to the next (otherwise velocity is meaningless).
    all_topics = s.execute(select(Topic)).scalars().all()
    labels = " ".join(t.label for t in all_topics).lower()
    assert sum(k in labels for k in ("recession", "rate cut", "chip", "tariff", "bank", "housing", "oil", "earnings")) >= 4
    matched = [t for t in all_topics if t.velocity != 1.0]
    assert len(matched) / len(all_topics) > 0.3, "most topics should match a predecessor"
    bars = aggregate.latest_sentiment(s)
    assert len(bars) >= 15
    assert bars["sentiment_z"].notna().sum() >= 10
    fear = aggregate.fear_index(s, datetime(2025, 1, 1), datetime(2026, 1, 1), 1440)
    assert 0.0 < fear.mean() < 0.6
    mk = aggregate.latest_markets(s)
    assert len(mk) == 4 and mk["yes_price"].between(0, 1).all() and mk["change_24h"].notna().all()


def test_backtester_detects_the_built_in_edge(social):
    s, summary = social
    start, end = date.fromisoformat(summary["start"]), date.fromisoformat(summary["end"])
    r = signals.evaluate(s, start, end, horizon=1, signal="score")
    assert "error" not in r
    assert r["ic"]["n_days"] > 100
    assert r["ic"]["mean_ic"] > 0.05, r["ic"]
    assert r["ic"]["t_stat"] > 3.0, r["ic"]
    assert r["long_short"]["sharpe"] > 1.0, r["long_short"]
    # Raw sentiment carries the same information; attention alone should not.
    att = signals.evaluate(s, start, end, horizon=1, signal="attention_z")
    assert abs(att["ic"]["mean_ic"]) < r["ic"]["mean_ic"]


def test_no_edge_when_ic_is_zero(demo):
    s, _ = demo
    seed_social_history(s, days=120, posts_per_day=50, seed=5, ic=0.0)
    r = signals.evaluate(s, date(2025, 1, 1), date(2025, 10, 31), horizon=1)
    assert abs(r["ic"]["t_stat"]) < 2.5, r["ic"]


def test_paper_strategy_routes_through_oms(social):
    s, _ = social
    orders = signals.strategy_orders(s, 2, top_n=3, sleeve=0.06, min_score=0.0)
    assert orders and all(o.created_by == signals.STRATEGY_ACTOR for o in orders)
    assert all(o.status in ("APPROVED", "REJECTED") for o in orders)
    n = signals.fill_approved_at_market(s, orders)
    assert n == sum(o.status == "FILLED" for o in orders)
    # Re-running sells what dropped out and tops up what stayed; nothing crashes.
    again = signals.strategy_orders(s, 2, top_n=1, sleeve=0.06, min_score=0.0)
    assert any(o.side == "SELL" for o in again)


# ---------------------------------------------------------------- API


@pytest.fixture(scope="module")
def sclient(social_engine):
    return TestClient(create_app(engine=social_engine))


def test_signals_api(sclient):
    st = sclient.get("/signals/status").json()
    assert st["posts_total"] > 0 and 0 < st["screened_share"] < 1
    b = sclient.get("/signals/bubbles").json()
    assert b["topics"] and {"label", "volume", "sentiment_mean", "velocity"} <= set(b["topics"][0])
    assert sclient.get("/signals/bubbles/history", params={"hours": 72}).json()
    sent = sclient.get("/signals/sentiment").json()
    assert sent and "sentiment_z" in sent[0]
    hist = sclient.get(f"/signals/sentiment/{sent[0]['ticker']}").json()
    assert len(hist) > 20
    assert sclient.get("/signals/fear").json()["series"]
    assert len(sclient.get("/signals/markets").json()) == 4
    bt = sclient.get("/signals/backtest", params={"start": "2025-01-01", "end": "2025-10-31"}).json()
    assert bt["ic"]["n_days"] > 50 and bt["equity_curve"]
    pt = sclient.post("/signals/paper-trade/1", params={"top_n": 2, "min_score": 0.0}).json()
    assert "orders" in pt
    html = sclient.get("/dashboard")
    assert html.status_code == 200 and "bubble-chart" in html.text


def test_topic_count_matches_windows(social):
    s, summary = social
    windows = s.execute(select(func.count(func.distinct(Topic.window_end)))).scalar_one()
    assert windows == summary["days"]
    bars = s.execute(select(func.count(func.distinct(SentimentBar.window_start)))).scalar_one()
    assert bars == summary["days"]
