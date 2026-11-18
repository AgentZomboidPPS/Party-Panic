"""The trend bot: crowd stance per security, and one trading cycle through compliance and the guard."""

from datetime import datetime, timedelta

import pytest
from sqlalchemy import select

from spectre.db import init_db, make_engine, make_session_factory
from spectre.execution.guard import TradingLimits, set_halt
from spectre.marketdata.universe import seed_universe
from spectre.models import CashFlow, ComplianceRule, Order, Portfolio, Security, Trade
from spectre.portfolio.positions import value_portfolio
from spectre.signals.pipeline import Pipeline
from spectre.signals.sources.base import Post, TrendItem
from spectre.signals.strategy import BOT_ACTOR, live_signals, run_once

T0 = datetime(2026, 11, 18, 15, 0)
LIMITS = TradingLimits(max_order_notional=2_000, max_daily_notional=20_000, max_orders_per_day=20, max_position_weight=0.25)


def _post(i, author, text, label=None, minute=0, prices=None, symbols=("NVDA",)):
    return Post("stocktwits", f"m{i}", author, text, T0 + timedelta(minutes=minute), "en", followers=20, account_age_days=500,
                source_sentiment=label, meta={"symbols": list(symbols), "prices": prices or {}})


def crowd_posts() -> list[Post]:
    """A small crowd: NVDA clearly bullish, TSLA clearly bearish, AMD too thin to count."""
    posts = []
    # NVDA: six authors bullish, one bearish. One of the bulls posts five times: still one vote.
    bulls = ["$NVDA clean breakout above resistance this morning", "Data center demand keeps surprising, long $NVDA",
             "Adding to my $NVDA position before the print", "$NVDA guidance will crush, the supply checks are great",
             "Every hyperscaler is still buying, $NVDA is the trade", "Momentum is back in semis and $NVDA leads it"]
    for a, text in enumerate(bulls):
        posts.append(_post(f"n{a}", f"bull{a}", text, "Bullish", a, {"NVDA": 150.0}))
    repeats = ["Told you all about $NVDA yesterday", "Chart on $NVDA keeps getting better and better",
               "Not selling a single share of $NVDA here", "Options flow in $NVDA is wildly one sided today"]
    for k, text in enumerate(repeats):
        posts.append(_post(f"nx{k}", "bull0", text, "Bullish", 10 + k, {"NVDA": 150.0}))
    posts.append(_post("nb", "bear0", "$NVDA looks like it is topping out to me", "Bearish", 7, {"NVDA": 150.0}))
    # TSLA: five authors, four bearish.
    bears = ["$TSLA breaking down through support", "Deliveries miss incoming, short $TSLA",
             "Margins keep shrinking at $TSLA and nobody cares yet", "$TSLA valuation makes no sense after this quarter"]
    for a, text in enumerate(bears):
        posts.append(_post(f"t{a}", f"tb{a}", text, "Bearish", a, {"TSLA": 400.0}, ("TSLA",)))
    posts.append(_post("tu", "tu0", "$TSLA holding the line so far, staying long", "Bullish", 5, {"TSLA": 400.0}, ("TSLA",)))
    # AMD: bullish but only two authors: not enough people to count.
    posts += [_post("a1", "am1", "$AMD nice", "Bullish", 1, {"AMD": 200.0}, ("AMD",)),
              _post("a2", "am2", "$AMD nice move", "Bullish", 2, {"AMD": 200.0}, ("AMD",))]
    return posts


@pytest.fixture
def book():
    e = make_engine("sqlite://")
    init_db(e)
    factory = make_session_factory(e)
    with factory() as s:
        seed_universe(s)
        pf = Portfolio(name="Bot", base_currency="USD")
        s.add(pf)
        s.flush()
        s.add(CashFlow(portfolio_id=pf.id, date=T0.date(), amount=10_000))
        s.add(ComplianceRule(portfolio_id=pf.id, name="No overdraft", rule_type="no_negative_cash", params={}))
        s.add(ComplianceRule(portfolio_id=pf.id, name="No shorts", rule_type="no_short_positions", params={}))
        s.commit()
        pid = pf.id
    pipe = Pipeline(factory)
    pipe.process_posts(crowd_posts())
    return factory, pid, pipe


def test_one_author_one_vote_and_minimum_crowd(book):
    factory, _, _ = book
    with factory() as s:
        sig = {x.ticker: x for x in live_signals(s, lookback_minutes=60, min_posts=5, min_authors=4)}
    assert set(sig) == {"NVDA", "TSLA"}, "AMD has too few authors to count"
    nvda, tsla = sig["NVDA"], sig["TSLA"]
    assert nvda.n_posts == 11 and nvda.n_authors == 7
    assert nvda.bull_share == pytest.approx(6 / 7) and nvda.bear_share == pytest.approx(1 / 7)
    assert nvda.net == pytest.approx(5 / 7), "the five-post author counts once"
    assert tsla.net == pytest.approx(1 / 5 - 4 / 5) and tsla.score < 0 < nvda.score
    assert nvda.price == 150.0 and nvda.labelled_share == 1.0 and not nvda.trending


def test_trending_search_boosts_the_score(book):
    factory, _, pipe = book
    with factory() as s:
        before = next(x for x in live_signals(s) if x.ticker == "NVDA").score
    pipe.process_trends([TrendItem("google_trends", "US", "nvidia earnings", T0, T0, 200_000, ["Nvidia tops estimates"])])
    with factory() as s:
        after = next(x for x in live_signals(s) if x.ticker == "NVDA")
    assert after.trending and after.score == pytest.approx(before * 1.25)


def test_cycle_buys_the_strong_name_within_limits_then_sells_when_the_crowd_turns(book):
    factory, pid, pipe = book
    with factory() as s:
        dry = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, dry_run=True)
        assert dry.targets == ["NVDA"] and dry.actions[0]["outcome"] == "dry run"
        assert s.execute(select(Order)).first() is None, "a dry run creates nothing"

        r = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)
        # 10,000 x 50% / 2 names = 2,500 per name, capped by the 2,000 order limit -> 13 shares at 150
        (buy,) = r.actions
        assert buy["ticker"] == "NVDA" and buy["side"] == "BUY" and buy["quantity"] == 13 and buy["outcome"] == "executed"
        nvda_id = s.execute(select(Security.id).where(Security.ticker == "NVDA")).scalar_one()
        v = value_portfolio(s, pid)
        assert v.positions.at[nvda_id, "quantity"] == 13 and v.cash == pytest.approx(10_000 - 13 * 150)
        assert s.execute(select(Order.created_by)).scalar_one() == BOT_ACTOR

        again = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)
        assert [a["quantity"] for a in again.actions] == [3], "tops up toward the 2,500 target, no more"

    # The crowd turns: eight new authors go bearish on NVDA.
    turns = ["$NVDA rolling over hard now", "That $NVDA guide was a disaster", "Out of $NVDA completely, the trade is done",
             "Export rules just gutted the $NVDA story", "$NVDA breaking the 50 day, this is not a dip to buy",
             "Margins guided down at $NVDA, sell the news", "Short $NVDA from here with a tight stop",
             "Everyone is trapped long $NVDA at the highs"]
    pipe.process_posts([_post(f"z{a}", f"turn{a}", t, "Bearish", 30 + a, {"NVDA": 140.0}) for a, t in enumerate(turns)])
    with factory() as s:
        r = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)
        (sell,) = r.actions
        assert sell["side"] == "SELL" and sell["quantity"] == 14 and sell["outcome"] == "executed"
        assert sell["fill_price"] == 140.0
        v = value_portfolio(s, pid)
        assert v.positions.at[nvda_id, "quantity"] == 2, "a 2,000 order cap at 140 sells 14 of 16; the rest goes next cycle"


def test_an_order_the_broker_does_not_fill_is_withdrawn_not_left_open(book):
    from spectre.execution.brokers import BrokerReject

    class Never:
        name, live = "never", False

        def submit(self, session, order):
            raise BrokerReject("no fill")

    factory, pid, _ = book
    with factory() as s:
        r = run_once(s, pid, broker=Never(), limits=LIMITS, top_n=2, invest=0.5)
        assert r.actions[0]["outcome"] == "blocked" and "no fill" in r.actions[0]["detail"]
        assert s.execute(select(Order.status)).scalar_one() == "CANCELLED"


def test_invest_caps_the_whole_stock_book_not_just_each_name(book):
    factory, pid, _ = book
    with factory() as s:
        # An AMD holding the bot did not choose this cycle already fills most of the 50% allowance.
        amd = s.execute(select(Security).where(Security.ticker == "AMD")).scalar_one()
        s.add(Trade(portfolio_id=pid, security_id=amd.id, side="BUY", quantity=22, price=200.0, currency="USD", trade_date=T0.date()))
        s.commit()
        r = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)
        (buy,) = r.actions
        # 5,000 allowed in stocks, 4,400 already in AMD: 600 of room buys 4 NVDA at 150, not the 13 its own target asks for.
        assert buy["ticker"] == "NVDA" and buy["quantity"] == 4
        assert run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5).actions == [], "no room left"


def test_kill_switch_stops_the_bot(book):
    factory, pid, _ = book
    with factory() as s:
        set_halt(s, True, actor="owner", reason="stop")
        r = run_once(s, pid, limits=LIMITS, top_n=2)
        assert r.actions[0]["outcome"] == "blocked" and "halted" in r.actions[0]["detail"]
        assert value_portfolio(s, pid).positions.empty
