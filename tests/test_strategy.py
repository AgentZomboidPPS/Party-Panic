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


def _set_price(s, ticker, close):
    from spectre.marketdata.prices import upsert_prices

    sid = s.execute(select(Security.id).where(Security.ticker == ticker)).scalar_one()
    upsert_prices(s, [{"security_id": sid, "date": T0.date(), "close": close}])
    s.commit()
    return sid


def test_average_cost_follows_buys_and_starts_afresh_after_a_full_exit(book):
    from spectre.portfolio.positions import average_costs

    factory, pid, _ = book
    with factory() as s:
        amd = _set_price(s, "AMD", 200.0)

        def trade(side, qty, price):
            s.add(Trade(portfolio_id=pid, security_id=amd, side=side, quantity=qty, price=price, currency="USD", trade_date=T0.date()))
            s.commit()

        trade("BUY", 10, 200.0)
        trade("BUY", 30, 220.0)
        assert average_costs(s, pid)[amd] == pytest.approx(215.0)
        trade("SELL", 20, 300.0)
        assert average_costs(s, pid)[amd] == pytest.approx(215.0), "selling some does not change what the rest cost"
        trade("SELL", 20, 300.0)
        assert amd not in average_costs(s, pid)
        trade("BUY", 5, 180.0)
        assert average_costs(s, pid)[amd] == pytest.approx(180.0), "a new position does not inherit the old average"


def test_stop_loss_sells_whatever_the_crowd_says_and_the_name_rests_for_the_day(book):
    factory, pid, _ = book
    roomy = TradingLimits(max_order_notional=50_000, max_daily_notional=500_000, max_orders_per_day=50, max_position_weight=1.0)

    def cycle(s, **kw):
        return run_once(s, pid, limits=roomy, top_n=2, invest=0.5, **kw)

    with factory() as s:
        cycle(s)  # 10,000 x 50% / 2 names = 2,500 -> 16 NVDA at 150
        # AMD is held too, and there is no read on it at all (too few people talking).
        amd = _set_price(s, "AMD", 200.0)
        s.add(Trade(portfolio_id=pid, security_id=amd, side="BUY", quantity=5, price=200.0, currency="USD", trade_date=T0.date()))
        s.commit()

        _set_price(s, "NVDA", 141.0)  # down 6%
        _set_price(s, "AMD", 190.0)  # down 5%
        calm = cycle(s, stop_loss=0.08)
        assert [(a["side"], a["ticker"], a["quantity"]) for a in calm.actions] == [("BUY", "NVDA", 1)], \
            "inside the 8% stop nothing is sold; NVDA is topped back up to its target instead"

        _set_price(s, "NVDA", 135.0)  # while the crowd is as bullish as ever
        _set_price(s, "AMD", 180.0)  # and still nobody is talking about AMD
        r = cycle(s, stop_loss=0.08)
        sold = {a["ticker"]: a for a in r.actions}
        assert set(sold) == {"NVDA", "AMD"} and all(a["side"] == "SELL" and a["outcome"] == "executed" for a in sold.values())
        # 16 shares at 150 and 1 at 141 cost 149.47 on average; 135 is 9.7% below that.
        assert sold["NVDA"]["why"] == "9.7% below its average cost of 149.47: stop" and sold["NVDA"]["quantity"] == 17
        assert sold["AMD"]["why"] == "10.0% below its average cost of 200.00: stop" and sold["AMD"]["quantity"] == 5
        assert "NVDA" in r.targets, "the crowd still wants it..."
        assert value_portfolio(s, pid).positions.empty, "...but it was not bought straight back"
        assert cycle(s, stop_loss=0.08).actions == [], "nor later the same day"
        assert cycle(s, dry_run=True).actions == [], "the rest-of-the-day pause applies with or without a stop configured"


TURNS = ["$NVDA rolling over hard now", "That $NVDA guide was a disaster", "Out of $NVDA completely, the trade is done",
         "Export rules just gutted the $NVDA story", "$NVDA breaking the 50 day, this is not a dip to buy",
         "Margins guided down at $NVDA, sell the news", "Short $NVDA from here with a tight stop",
         "Everyone is trapped long $NVDA at the highs"]


def _bought_then_the_crowd_turned(factory, pid, pipe):
    """13 NVDA bought a quarter of an hour into the story; half an hour in, eight new voices turn bearish."""
    with factory() as s:
        run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)
        fill = s.execute(select(Order)).scalar_one().fills[0]
        fill.filled_at = T0 + timedelta(minutes=15)
        s.commit()
    pipe.process_posts([_post(f"z{a}", f"turn{a}", t, "Bearish", 30 + a, {"NVDA": 148.0}) for a, t in enumerate(TURNS)])


def test_a_change_of_mind_does_not_count_until_the_holding_is_old_enough(book):
    factory, pid, pipe = book
    _bought_then_the_crowd_turned(factory, pid, pipe)
    with factory() as s:
        # Thirty minutes after buying the crowd has turned: with an hour's minimum hold nothing is sold yet...
        soon = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, min_hold_minutes=60, stop_loss=0.08, at=T0 + timedelta(minutes=45))
        (held_back,) = soon.actions
        assert held_back["outcome"] == "skipped" and "bought 30 minutes ago" in held_back["why"] and "at least 60" in held_back["why"]
        assert float(value_portfolio(s, pid).positions["quantity"].sum()) == 13
        # ...but the stop-loss does not wait for anything.
        _set_price(s, "NVDA", 130.0)
        stopped = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, min_hold_minutes=60, stop_loss=0.08, at=T0 + timedelta(minutes=50))
        assert stopped.actions[0]["side"] == "SELL" and "stop" in stopped.actions[0]["why"] and stopped.actions[0]["outcome"] == "executed"


def test_once_old_enough_a_turned_crowd_sells_as_before(book):
    factory, pid, pipe = book
    _bought_then_the_crowd_turned(factory, pid, pipe)
    with factory() as s:
        later = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, min_hold_minutes=60, at=T0 + timedelta(minutes=80))
        assert [(a["side"], a["outcome"]) for a in later.actions] == [("SELL", "executed")]
        no_rule = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, at=T0 + timedelta(minutes=80))
        assert no_rule.actions == [], "already sold; and with no minimum hold the rule simply does not apply"


def test_risk_weighting_gives_a_jumpy_name_a_smaller_position(book):
    import numpy as np

    from spectre.models import Price
    from spectre.risk.vol import recent_vols

    factory, pid, pipe = book
    # Make AMD a second strongly liked name, so the bot wants both it and NVDA.
    likes = ["$AMD taking share in servers again", "Long $AMD into the product launch", "$AMD margins finally turning up",
             "Adding $AMD on this base, looks ready", "$AMD datacenter numbers were excellent", "Buying more $AMD here"]
    pipe.process_posts([_post(f"m{a}", f"amdfan{a}", t, "Bullish", 3 + a, {"AMD": 200.0}, ("AMD",)) for a, t in enumerate(likes)])
    with factory() as s:
        ids = {t: s.execute(select(Security.id).where(Security.ticker == t)).scalar_one() for t in ("NVDA", "AMD", "MSFT", "AAPL", "TSLA")}
        rng = np.random.default_rng(3)
        # Sixty days of history: NVDA and three others move about 1% a day, AMD about 3%.
        for ticker, daily, last in (("NVDA", 0.01, 150.0), ("MSFT", 0.01, 500.0), ("AAPL", 0.01, 350.0), ("TSLA", 0.01, 400.0), ("AMD", 0.03, 200.0)):
            moves = rng.normal(0, daily, 60)
            closes = last / np.cumprod(1 + moves[::-1])[::-1]
            for k, close in enumerate(closes):
                s.add(Price(security_id=ids[ticker], date=T0.date() - timedelta(days=60 - k), close=float(close)))
        s.commit()
        vols = recent_vols(s, ids.values(), T0.date())
        assert vols[ids["AMD"]] > 2.3 * vols[ids["NVDA"]], "AMD has been moving about three times as much"

        plain = run_once(s, pid, limits=LIMITS, top_n=5, invest=0.5, dry_run=True)
        assert {a["ticker"]: a["quantity"] for a in plain.actions} == {"NVDA": 6, "AMD": 5}, "equal dollars: 1,000 each"
        r = run_once(s, pid, limits=LIMITS, top_n=5, invest=0.5, dry_run=True, risk_weighted=True)
        size = {a["ticker"]: a for a in r.actions}
        # A slot is 1,000. NVDA moves like the typical name: a full position. AMD moves three times as much: half of one, the floor.
        assert size["NVDA"]["quantity"] == 6 and "sized at" not in size["NVDA"]["why"]
        assert size["AMD"]["quantity"] == 2 and "sized at 0.5 of a full position because it moves more than most" in size["AMD"]["why"]


def test_with_a_brake_on_a_cycle_sells_but_does_not_buy(book):
    factory, pid, pipe = book
    with factory() as s:
        paused = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, allow_buys=False)
        assert paused.actions == [] and paused.targets == ["NVDA"], "it still sees what it would buy; it just does not"
    _bought_then_the_crowd_turned(factory, pid, pipe)
    with factory() as s:
        r = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5, allow_buys=False, at=T0 + timedelta(minutes=80))
        assert [(a["side"], a["outcome"]) for a in r.actions] == [("SELL", "executed")], "selling reduces risk: never paused"


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
        s.add(Trade(portfolio_id=pid, security_id=amd.id, side="BUY", quantity=18, price=200.0, currency="USD", trade_date=T0.date()))
        s.commit()
        r = run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5)
        (buy,) = r.actions
        # 5,000 allowed in stocks, 3,600 already in AMD: 1,400 of room buys 9 NVDA at 150, not the 13 its own target asks for.
        assert buy["ticker"] == "NVDA" and buy["quantity"] == 9
        assert run_once(s, pid, limits=LIMITS, top_n=2, invest=0.5).actions == [], "no room left"


def test_kill_switch_stops_the_bot(book):
    factory, pid, _ = book
    with factory() as s:
        set_halt(s, True, actor="owner", reason="stop")
        r = run_once(s, pid, limits=LIMITS, top_n=2)
        assert r.actions[0]["outcome"] == "blocked" and "halted" in r.actions[0]["detail"]
        assert value_portfolio(s, pid).positions.empty


def test_a_new_name_is_not_started_with_a_token_amount(book):
    factory, pid, _ = book
    with factory() as s:
        # The plan is 2,000 of NVDA (one slot of a 20% book), but only 700 can go into one order here.
        tight = TradingLimits(max_order_notional=700, max_daily_notional=20_000, max_orders_per_day=20, max_position_weight=0.25)
        r = run_once(s, pid, limits=tight, top_n=1, invest=0.2)
        assert r.actions == [] and value_portfolio(s, pid).positions.empty, "700 of an intended 2,000 is under half: wait"
        roomy = TradingLimits(max_order_notional=1_200, max_daily_notional=20_000, max_orders_per_day=20, max_position_weight=0.25)
        r = run_once(s, pid, limits=roomy, top_n=1, invest=0.2)
        assert [(a["ticker"], a["quantity"], a["outcome"]) for a in r.actions] == [("NVDA", 8.0, "executed")], "1,200 of 2,000 is a real start"
        # ... and once held, it is topped up towards the full position in pieces of any worthwhile size.
        r = run_once(s, pid, limits=tight, top_n=1, invest=0.2)
        assert [(a["ticker"], a["quantity"]) for a in r.actions] == [("NVDA", 4.0)]
