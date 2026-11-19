"""More than the crowd: what else KAIROS knows about a name when it decides.

Each kind of evidence is either **in use** or **on trial**.

In use means it has been tested against real prices and is allowed to change a decision:

- **trend**: where a stock or fund stands among all those in the book on six-to-twelve-month
  price momentum. On nine years of daily prices (`trend_check`) the top fifth went on to beat
  the average name by about 0.09% a day, steadily in both halves of the period, while the
  other four fifths could not be told apart. So a name near the top has its crowd score
  raised by up to half, and a weak trend takes nothing away: the test gives no grounds for
  that. The same history shows the effect disappears while the market itself is deep in a
  fall (the S&P 500 more than 10% below its one-year high), so the raise is switched off
  then. One caution: the book is a list of names that are well known today, which flatters
  any test of "winners keep winning" somewhat.
- **backdrop**: how turbulent the market is, from the S&P 500's last 20 trading days. The
  same history says turbulence does not tell direction (`backdrop_check`), but turbulent
  stretches are two to three times as violent, so new buying is scaled down in them: a
  position sized for a calm market is too big for a wild one.

On trial means it is worked out and written down with every reading KAIROS records, judged
later against what prices did, and changes no decision until it has earned it:

- **news**: the tone of the last two days' headlines about the name, and events spotted in
  them (results, guidance, analyst changes, deals, share offerings, legal trouble);
- **tape**: how the name has moved today against the typical name in the book.

Coins get no trend evidence: the same test on six years of coin prices showed nothing that
held up in both halves of the period.

Tested and not used:

- **big market moves**: "the market has just moved a lot, so buy index calls or puts the same
  way and get out quickly". On eight years of half-hourly prices of the S&P 500 fund
  (`market_move_check`) a big move did not tend to carry on: not from the first half hour
  into the last, not into the rest of the day, not from any unusually large half hour into
  the next. Whatever there is to be had in the seconds after a number comes out belongs to
  machines that are there in those seconds, which this is not.
"""

from __future__ import annotations

import math
import re
from dataclasses import replace
from datetime import date, datetime, timedelta

import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.models import Price, Security
from spectre.signals.models import NewsItem
from spectre.signals.sources.base import utcnow

STOCKS = ("Equity", "Fund")
BENCHMARK = "SPY"

TREND_STRENGTH = 0.5  # a name at the very top of the trend ranking has its crowd score raised by this much
TREND_FROM, TREND_FULL = 0.7, 0.9  # standing (0 to 1) where the raise starts, and where it is complete
TREND_OFF_BELOW_HIGH = -0.10  # no raise while the S&P 500 is further than this below its one-year high
MIN_HISTORY = 131  # trading days a name needs before its six-month momentum exists

TARGET_VOL = 0.15  # S&P 500 volatility (a year) above which new buying is scaled down
MIN_SCALE = 0.5  # never below half size
VOL_DAYS = 20

NEWS_HOURS = 48.0
NEWS_HALF_LIFE = 12.0  # hours: a headline counts half as much after this long

IN_USE = "in use"
ON_TRIAL = "on trial"
NOT_USED = "tested, not used"
KINDS = (
    {"key": "crowd", "name": "The crowd", "status": IN_USE,
     "what": "Share of authors bullish minus bearish over the last stretch of posts, weighted by how many are talking."},
    {"key": "trend", "name": "Price trend", "status": IN_USE,
     "what": "Where the name stands among all stocks and funds in the book on 6-12 month momentum. "
             "Near the top raises its crowd score by up to half; a weak trend takes nothing away."},
    {"key": "backdrop", "name": "Market backdrop", "status": IN_USE,
     "what": "How turbulent the S&P 500 has been over the last 20 trading days. New buying is scaled down when it is."},
    {"key": "news", "name": "News", "status": ON_TRIAL,
     "what": "Tone of the last two days' headlines about the name, and events spotted in them."},
    {"key": "tape", "name": "Today's move", "status": ON_TRIAL,
     "what": "How the name has moved today against the typical name in the book."},
    {"key": "market_move", "name": "Big market moves", "status": NOT_USED,
     "what": "After a big move in the S&P 500, buy index calls or puts the same way and get out quickly. On eight years of "
             "half-hourly prices a big move did not tend to carry on: the next half hour, the last half hour and the rest "
             "of the day were each as likely to go the other way. `spectre market-moves` runs the test again."},
)


# --------------------------------------------------------------------------- trend


def momentum_standing(closes: pd.DataFrame) -> pd.DataFrame:
    """Each name's standing (0 = weakest, 1 = strongest) on six-to-twelve-month momentum, for
    every day, from prices up to that day only. Two looks are blended: the last twelve months
    leaving out the latest month, and the last six leaving out the latest week (the most
    recent stretch is left out because short-term moves tend to reverse). A name too young for
    the twelve-month look is ranked on the six-month one alone."""
    long = closes.shift(21) / closes.shift(252) - 1
    mid = closes.shift(5) / closes.shift(126) - 1
    blend = pd.concat([long.rank(axis=1, pct=True), mid.rank(axis=1, pct=True)]).groupby(level=0).mean()
    return blend.rank(axis=1, pct=True)


def trend_boost(standing: float | None) -> float:
    """What a name's crowd score is multiplied by for its trend: 1.0 through most of the range,
    rising to 1 + TREND_STRENGTH near the top. Never below 1: see the module notes."""
    if standing is None or pd.isna(standing):
        return 1.0
    return 1.0 + TREND_STRENGTH * min(max((float(standing) - TREND_FROM) / (TREND_FULL - TREND_FROM), 0.0), 1.0)


def stock_closes(session: Session, as_of: date | None = None, days: int = 420) -> pd.DataFrame:
    """Daily closes of every stock and fund in the book (rows: dates, columns: tickers) over
    the last `days` calendar days up to `as_of`."""
    q = (select(Security.ticker, Price.date, Price.close).join(Price, Price.security_id == Security.id)
         .where(Security.asset_class.in_(STOCKS)))
    if as_of is not None:
        q = q.where(Price.date <= as_of, Price.date >= as_of - timedelta(days=days))
    rows = session.execute(q).all()
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows, columns=["ticker", "date", "close"]).pivot(index="date", columns="ticker", values="close").sort_index()
    if BENCHMARK in df.columns:
        df = df[df[BENCHMARK].notna()]  # market days only
    return df


# --------------------------------------------------------------------------- news

_EVENTS: tuple[tuple[str, int, re.Pattern], ...] = tuple(
    (name, direction, re.compile(pattern, re.IGNORECASE)) for name, direction, pattern in (
        ("results beat", +1, r"\b(beats?|tops?|exceeds?|surpass(?:es)?|crush(?:es)?)\b.{0,40}\b(estimates?|expectations|forecasts?|views?)\b"),
        ("results miss", -1, r"\b(miss(?:es|ed)?|falls? short of|short of)\b.{0,40}\b(estimates?|expectations|forecasts?|views?)\b"),
        ("guidance raised", +1, r"\b(raises?|lifts?|boosts?|hikes?|increases?|ups)\b.{0,30}\b(guidance|outlook|forecast)\b"),
        ("guidance cut", -1, r"\b(cuts?|lowers?|slashes?|reduces?|trims?|withdraws?)\b.{0,30}\b(guidance|outlook|forecast)\b"),
        ("analyst upgrade", +1, r"\bupgrad(?:e|es|ed)\b|\b(raises?|lifts?|boosts?|hikes?)\b.{0,30}\bprice target\b|\bprice target (?:raised|increased|lifted|hiked)\b"),
        ("analyst downgrade", -1, r"\bdowngrad(?:e|es|ed)\b|\b(cuts?|lowers?|trims?|slashes?)\b.{0,30}\bprice target\b|\bprice target (?:cut|lowered|reduced|trimmed)\b"),
        ("deal", +1, r"\b(to acquire|acquires|acquisition of|merger with|to be acquired|takeover|buyout)\b"),
        ("buyback or dividend", +1, r"\b(buyback|share repurchase|repurchase program|raises (?:its )?dividend|dividend increase|special dividend)\b"),
        ("approval", +1, r"\bfda (?:approves|approval|clears|clearance)\b|\bwins? (?:\w+ )?approval\b"),
        ("share offering", -1, r"\b(public offering|secondary offering|offering of (?:common )?(?:stock|shares)|share sale|convertible notes?|at-the-market)\b"),
        ("legal or regulatory trouble", -1, r"\b(lawsuit|sued|sues|investigation|probe|subpoena|recalls?|fraud|antitrust|fined)\b"),
    )
)


def headline_events(text: str) -> list[tuple[str, int]]:
    """Events spotted in a headline, each with the direction it usually points: (name, +1 or -1)."""
    return [(name, direction) for name, direction, pattern in _EVENTS if pattern.search(text or "")]


def news_evidence(session: Session, now: datetime | None = None, hours: float = NEWS_HOURS) -> dict[str, dict]:
    """Per ticker, from the last `hours` of headlines: `tone` (-1 to +1; newer headlines count
    more, and an event pulls it half a point its way), how many headlines, and the events seen."""
    now = now or utcnow()
    rows = session.execute(
        select(NewsItem.tickers, NewsItem.headline, NewsItem.sentiment, NewsItem.published_at)
        .where(NewsItem.published_at >= now - timedelta(hours=hours), NewsItem.published_at <= now)
    ).all()
    acc: dict[str, dict] = {}
    for tickers, headline, tone, published in rows:
        events = headline_events(headline)
        value = max(-1.0, min(1.0, (tone or 0.0) + 0.5 * sum(d for _, d in events)))
        weight = 0.5 ** (max((now - published).total_seconds() / 3600, 0.0) / NEWS_HALF_LIFE)
        for ticker in tickers or []:
            a = acc.setdefault(ticker, {"sum": 0.0, "weight": 0.0, "count": 0, "events": []})
            a["sum"] += value * weight
            a["weight"] += weight
            a["count"] += 1
            a["events"] += [name for name, _ in events if name not in a["events"]]
    return {t: {"tone": a["sum"] / a["weight"] if a["weight"] else 0.0, "count": a["count"], "events": a["events"]}
            for t, a in acc.items()}


# --------------------------------------------------------------------------- putting it together


def weigh(session: Session, signals: list, at: datetime | None = None, use_trend: bool = True) -> list:
    """Attach the other evidence to each crowd read and work out its conviction: the crowd score,
    raised for a stock or fund whose trend is near the top of the book. A bearish read is left
    as it is (the history gives no reason to think a weak trend adds to it). Strongest first."""
    if not signals:
        return []
    now = at or utcnow()
    closes = stock_closes(session, now.date())
    standing: dict = {}
    tape: dict = {}
    if len(closes) >= MIN_HISTORY:
        standing = momentum_standing(closes).iloc[-1].dropna().to_dict()
    use_trend = use_trend and backdrop(session, now.date()).get("trend_in_play", True)
    if len(closes) >= 2 and closes.index[-1] == now.date():  # a price from today to compare with the last close
        today = (closes.iloc[-1] / closes.iloc[-2] - 1).dropna()
        tape = (today - today.median()).to_dict()
    news = news_evidence(session, now)
    out = []
    for s in signals:
        is_stock = s.asset_class in STOCKS
        rank = standing.get(s.ticker) if is_stock else None
        boost = trend_boost(rank) if (use_trend and s.score > 0) else 1.0
        n = news.get(s.ticker)
        out.append(replace(
            s, trend=None if rank is None else float(rank), tape=float(tape[s.ticker]) if is_stock and s.ticker in tape else None,
            news=float(n["tone"]) if n else None, news_count=n["count"] if n else 0, events=list(n["events"]) if n else [],
            conviction=s.score * boost,
        ))
    return sorted(out, key=lambda s: -s.conviction)


def describe(signal) -> str:
    """The evidence behind one read, in words, for the journal: only what changed the decision."""
    if signal.conviction is None or signal.trend is None or signal.score <= 0 or signal.conviction <= signal.score * 1.02:
        return ""
    return (f"; strong trend (top {max(1.0 - signal.trend, 0.01):.0%} of the book on 6-12 month momentum) "
            f"raises it to {signal.conviction:+.2f}")


# --------------------------------------------------------------------------- backdrop


def backdrop(session: Session, as_of: date | None = None) -> dict:
    """How turbulent the market is now, and what that does to the size of new purchases."""
    q = select(Price.date, Price.close).join(Security, Security.id == Price.security_id).where(Security.ticker == BENCHMARK)
    if as_of is not None:
        q = q.where(Price.date <= as_of)
    rows = session.execute(q.order_by(Price.date.desc()).limit(260)).all()
    closes = pd.Series({d: c for d, c in rows}).sort_index()
    if len(closes) < VOL_DAYS + 1:
        return {"available": False, "scale": 1.0, "volatility": None,
                "note": f"No market backdrop yet: it needs {VOL_DAYS + 1} days of {BENCHMARK} prices."}
    vol = float(closes.pct_change().tail(VOL_DAYS).std() * math.sqrt(252))
    scale = 1.0 if vol <= TARGET_VOL else max(MIN_SCALE, TARGET_VOL / vol)
    average = float(closes.tail(200).mean()) if len(closes) >= 200 else None
    high = float(closes.max())
    state = "calm" if vol <= TARGET_VOL else "turbulent" if scale > MIN_SCALE else "very turbulent"
    note = (f"The market is {state}: the S&P 500 has been moving at {vol:.0%} a year over the last {VOL_DAYS} trading days"
            + (f", so new stock and option purchases are made at {scale:.0%} of normal size." if scale < 1 else
               ", so purchases are made at full size."))
    below_high = float(closes.iloc[-1] / high - 1)
    in_play = below_high > TREND_OFF_BELOW_HIGH
    if not in_play:
        note += (f" The S&P 500 is {-below_high:.0%} below its one-year high; in falls that deep a strong trend has not "
                 "helped, so it is not being counted.")
    return {"available": True, "state": state, "volatility": vol, "target_volatility": TARGET_VOL, "scale": scale,
            "above_200_day_average": None if average is None else bool(closes.iloc[-1] > average),
            "below_year_high": below_high, "trend_in_play": in_play, "as_of": closes.index[-1].isoformat(), "note": note}


# --------------------------------------------------------------------------- the tests on history


def _t(values: pd.Series) -> float | None:
    values = values.dropna()
    if len(values) < 4 or values.std() == 0:
        return None
    return float(values.mean() / (values.std() / math.sqrt(len(values))))


def trend_check(session: Session, as_of: date | None = None) -> dict:
    """The test behind the trend evidence, run on all the daily history in the database: sort
    the stocks and funds into fifths by momentum standing each day, and see how each fifth did
    the next day against the average name. Reported for the whole period and for each half."""
    q = (select(Security.ticker, Price.date, Price.close).join(Price, Price.security_id == Security.id)
         .where(Security.asset_class.in_(STOCKS)))
    if as_of is not None:
        q = q.where(Price.date <= as_of)
    rows = session.execute(q).all()
    if not rows:
        return {"available": False, "fifths": [], "top_fifth_by_market": []}
    closes = pd.DataFrame(rows, columns=["ticker", "date", "close"]).pivot(index="date", columns="ticker", values="close").sort_index()
    if BENCHMARK in closes.columns:
        closes = closes[closes[BENCHMARK].notna()]
    closes = closes.iloc[:-1]  # the latest row may be a day still in progress
    if len(closes) < 260:  # under a year of days: nothing to test yet
        return {"available": False, "fifths": [], "top_fifth_by_market": []}
    standing = momentum_standing(closes)
    ahead = closes.shift(-1) / closes - 1
    against = ahead.sub(ahead.mean(axis=1), axis=0)
    enough = standing.notna().sum(axis=1) >= 20
    fifths = []
    for i in range(5):
        lo, hi = i / 5, (i + 1) / 5
        inside = (standing > lo) & (standing <= hi) if i else (standing <= hi)
        daily = against.where(inside)[enough].mean(axis=1).dropna()
        half = len(daily) // 2
        fifths.append({"fifth": i + 1, "days": int(len(daily)), "next_day_against_average": float(daily.mean()) if len(daily) else None,
                       "t_stat": _t(daily), "first_half": float(daily.iloc[:half].mean()) if half else None,
                       "second_half": float(daily.iloc[half:].mean()) if half else None})
    days = int(enough.sum())
    # The top fifth again, split by whether the market itself was deep in a fall at the time.
    by_market = []
    if BENCHMARK in closes.columns:
        below = closes[BENCHMARK] / closes[BENCHMARK].rolling(252, min_periods=60).max() - 1
        top = against.where(standing > 0.8)[enough].mean(axis=1)
        for name, mask in (("S&P 500 within 10% of its one-year high", below > TREND_OFF_BELOW_HIGH),
                           ("S&P 500 more than 10% below it", below <= TREND_OFF_BELOW_HIGH)):
            daily = top[mask.reindex(top.index).fillna(False)].dropna()
            by_market.append({"market": name, "days": int(len(daily)),
                              "top_fifth_next_day_against_average": float(daily.mean()) if len(daily) else None, "t_stat": _t(daily)})
    return {"available": days > 250, "from": closes.index[0].isoformat(), "to": closes.index[-1].isoformat(), "days": days,
            "names": int(closes.shape[1]), "fifths": fifths, "top_fifth_by_market": by_market}


def backdrop_check(session: Session, as_of: date | None = None) -> dict:
    """The test behind the backdrop: on all the S&P 500 history in the database, what the next
    day looked like after calm and after turbulent stretches, and what scaling exposure down
    in turbulent ones would have done to simply holding the index."""
    q = select(Price.date, Price.close).join(Security, Security.id == Price.security_id).where(Security.ticker == BENCHMARK)
    if as_of is not None:
        q = q.where(Price.date <= as_of)
    closes = pd.Series({d: c for d, c in session.execute(q).all()}).sort_index().iloc[:-1]
    if len(closes) < 300:
        return {"available": False}
    ret = closes.pct_change()
    vol = ret.rolling(VOL_DAYS).std() * math.sqrt(252)
    ahead = ret.shift(-1)
    frame = pd.DataFrame({"vol": vol, "ahead": ahead}).dropna()
    scale = (TARGET_VOL / frame["vol"]).clip(lower=MIN_SCALE, upper=1.0)

    def describe_run(r: pd.Series) -> dict:
        growth = (1 + r).cumprod()
        return {"return_a_year": float(r.mean() * 252), "volatility": float(r.std() * math.sqrt(252)), "worst_day": float(r.min()),
                "deepest_fall": float((growth / growth.cummax() - 1).min())}

    states = []
    for name, mask in (("calm", frame["vol"] <= TARGET_VOL), ("turbulent", frame["vol"] > TARGET_VOL)):
        r = frame["ahead"][mask]
        states.append({"state": name, "days": int(len(r)), "next_day_mean": float(r.mean()) if len(r) else None,
                       "volatility": float(r.std() * math.sqrt(252)) if len(r) > 1 else None})
    return {"available": True, "from": frame.index[0].isoformat(), "to": frame.index[-1].isoformat(), "days": int(len(frame)),
            "states": states, "held_throughout": describe_run(frame["ahead"]), "scaled_down_when_turbulent": describe_run(frame["ahead"] * scale),
            "average_scale": float(scale.mean())}


def market_move_check(bars: list[tuple[datetime, float]], big: float = 0.01, unusual: float = 3.0) -> dict:
    """Does a big move in the market carry on? Tested on half-hourly prices of the S&P 500
    fund (`bars`: (start of the half hour in UTC, its closing price), regular hours or more).

    Each rule is "go the way of the move": its result is the average return that followed,
    counted as a gain when the market carried on and a loss when it turned back, with the
    share of times it carried on and the two halves of the period apart. Rules:
    - the first half hour of the day (measured from the previous close), into the last half
      hour: the one pattern of this kind with a published study behind it;
    - the first half hour into the rest of the day, on every day and on days it moved over `big`;
    - any later half hour that moved more than `unusual` times what was usual over the last
      twenty days, into the next half hour and into the next hour."""
    if len(bars) < 500:
        return {"available": False, "rules": []}
    series = pd.Series({t: c for t, c in bars}).sort_index()
    local = pd.DatetimeIndex(series.index).tz_localize("UTC").tz_convert("America/New_York")
    frame = pd.DataFrame({"close": series.to_numpy(), "day": local.date, "at": local.strftime("%H:%M")})
    frame = frame[(frame["at"] >= "09:30") & (frame["at"] <= "15:30")]
    table = frame.pivot(index="day", columns="at", values="close").dropna(subset=["09:30", "15:00", "15:30"])  # whole days only
    if len(table) < 60:
        return {"available": False, "rules": []}
    close, at_ten, at_half_three = table["15:30"], table["09:30"], table["15:00"]
    previous = close.shift(1)
    first = at_ten / previous - 1

    def rule(name: str, move: pd.Series, after: pd.Series) -> dict:
        both = pd.DataFrame({"move": move, "after": after}).dropna()
        both = both[both["move"] != 0]
        gain = (both["move"].apply(lambda x: 1.0 if x > 0 else -1.0) * both["after"])
        half = len(gain) // 2
        return {"rule": name, "times": int(len(gain)), "average_after": float(gain.mean()) if len(gain) else None, "t_stat": _t(gain),
                "carried_on": float((gain > 0).mean()) if len(gain) else None,
                "first_half": float(gain.iloc[:half].mean()) if half else None,
                "second_half": float(gain.iloc[half:].mean()) if half else None}

    rules = [
        rule("the first half hour, into the last half hour", first, close / at_half_three - 1),
        rule("the first half hour, into the rest of the day", first, close / at_ten - 1),
        rule(f"a first half hour of more than {big:.0%}, into the rest of the day", first[first.abs() > big], close / at_ten - 1),
    ]
    moves = table.pct_change(axis=1)
    usual = moves.abs().mean(axis=1).rolling(20).mean().shift(1)  # the typical half-hour move over the last twenty days
    large = moves.where(moves.abs().gt(unusual * usual, axis=0)).iloc[:, 1:]  # the opening half hour is covered above
    for name, steps in (("the next half hour", 1), ("the next hour", 2)):
        after = (table.shift(-steps, axis=1) / table - 1).iloc[:, 1:]
        rules.append(rule(f"a half hour of more than {unusual:g} times the usual move, into {name}", large.stack(), after.stack()))
    return {"available": True, "from": table.index[0].isoformat(), "to": table.index[-1].isoformat(), "days": int(len(table)), "rules": rules}
