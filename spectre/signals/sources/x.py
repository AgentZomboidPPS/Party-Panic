"""X (Twitter) recent search, API v2, on a daily budget.

X charges for every post read (about half a cent each on its pay-per-use plan in 2026), so
this reader is built around a hard cap: `daily_posts` is the most it will read in one UTC
day, across restarts (the count already read today is asked for at start), and when the cap
is reached it stops until the next day. Nothing is read at all unless a budget is set.

What it reads: the newest posts that carry the cashtag of one of the symbols it was given
(`$NVDA OR $TSLA ...`), in English, without retweets. Busy names get thousands of posts in
ten minutes, so what comes back is a sample of the newest, not everything; `since_id` keeps a
post from being read (and paid for) twice. Requests are spaced so the budget lasts through
the trading day rather than being spent in the first hour.

The token is a bearer token from an X developer app (`SPECTRE_X_BEARER_TOKEN`), or one the
hosting environment adds to requests itself, in which case nothing needs to be set here.

Not yet run against the live service: there has been no token to run it with. The request
and response shapes follow X's published documentation and are covered by tests against a
stand-in; expect to adjust details on first contact (above all whether the account's plan
accepts the cashtag operator: if a query is refused for it, plain symbols are tried instead).
"""

from __future__ import annotations

import asyncio
import logging
import os
from collections.abc import Callable
from datetime import datetime

import httpx

from spectre.signals.sources.base import Emit, Post, sleep_or_stop, to_naive_utc, utcnow

log = logging.getLogger(__name__)

SEARCH = "https://api.x.com/2/tweets/search/recent"
QUERY_LIMIT = 480  # X allows 512 characters; leave room
PAGE_MIN, PAGE_MAX = 10, 100  # the fewest and the most posts one request may ask for
SUFFIX = " lang:en -is:retweet"


def build_queries(symbols: list[str], cashtags: bool = True) -> list[str]:
    """Search queries covering the symbols, as few as fit X's length limit. With `cashtags`
    off (a plan that refuses the `$` operator) only symbols of four letters or more are
    searched for as plain words: shorter ones are ordinary words far too often."""
    terms = [f"${s}" for s in symbols] if cashtags else [s for s in symbols if len(s) >= 4]
    queries, chunk = [], []
    for term in terms:
        if chunk and len(f"({' OR '.join([*chunk, term])}){SUFFIX}") > QUERY_LIMIT:
            queries.append(f"({' OR '.join(chunk)}){SUFFIX}")
            chunk = []
        chunk.append(term)
    if chunk:
        queries.append(f"({' OR '.join(chunk)}){SUFFIX}")
    return queries


def parse_posts(body: dict) -> list[Post]:
    """The posts in one search response."""
    users = {u["id"]: u for u in (body.get("includes") or {}).get("users", [])}
    out = []
    for t in body.get("data") or []:
        try:
            created = to_naive_utc(datetime.fromisoformat(t["created_at"].replace("Z", "+00:00")))
            ext = str(t["id"])
        except (KeyError, ValueError, AttributeError):
            continue
        u = users.get(t.get("author_id"), {})
        age = None
        if u.get("created_at"):
            try:
                age = (created - to_naive_utc(datetime.fromisoformat(u["created_at"].replace("Z", "+00:00")))).days
            except ValueError:
                age = None
        out.append(Post(
            source="x", external_id=ext, author_id=str(t.get("author_id", "")), text=t.get("text", ""), created_at=created,
            lang=t.get("lang"), followers=(u.get("public_metrics") or {}).get("followers_count"), account_age_days=age,
        ))
    return out


class XRecentSearch:
    name = "x"

    def __init__(
        self,
        symbols: list[str] | None = None,
        query: str | None = None,
        daily_posts: int = 0,
        already_read: Callable[[], int] | None = None,
        poll_seconds: float | None = None,
        bearer_token: str | None = None,
        cost_per_post: float = 0.005,
        active_hours: float = 8.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ):
        if daily_posts <= 0:
            raise ValueError("X charges per post read: set a daily budget of posts (SPECTRE_X_DAILY_POSTS) before switching it on")
        if not symbols and not query:
            raise ValueError("X adapter needs symbols or a query to search for")
        self.symbols = [s.upper().removesuffix(".X") for s in symbols or []]
        self.queries = [query] if query else build_queries(self.symbols)
        self.daily_posts = daily_posts
        self.cost_per_post = cost_per_post
        # The token set here, or a placeholder for the hosting environment to replace with the real one.
        self.token = bearer_token or os.environ.get("SPECTRE_X_BEARER_TOKEN") or "added-by-the-network"
        # Spread the day's requests over the hours that matter, never faster than once a minute.
        rounds = max(1.0, daily_posts / (PAGE_MAX * len(self.queries)))
        self.poll_seconds = poll_seconds if poll_seconds is not None else max(60.0, active_hours * 3600 / rounds)
        self._already_read = already_read
        self._transport = transport
        self._since: dict[str, str] = {}
        self._day = utcnow().date()
        self.read_today = 0
        self._cashtags = query is None

    def _budget_left(self) -> int:
        today = utcnow().date()
        if today != self._day:  # a new day, a new budget
            self._day, self.read_today = today, 0
        return self.daily_posts - self.read_today

    async def _search(self, client: httpx.AsyncClient, query: str, want: int) -> list[Post]:
        params = {"query": query, "max_results": want, "tweet.fields": "created_at,lang,author_id,public_metrics",
                  "expansions": "author_id", "user.fields": "created_at,public_metrics"}
        if query in self._since:
            params["since_id"] = self._since[query]
        r = await client.get(SEARCH, params=params)
        r.raise_for_status()
        posts = parse_posts(r.json())
        if posts:
            self._since[query] = max((p.external_id for p in posts), key=int)
        self.read_today += len(posts)  # what X bills for
        return posts

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        if self._already_read is not None:
            try:
                self.read_today = max(self.read_today, int(self._already_read()))  # a restart does not reset the budget
            except Exception as exc:  # the count is a safeguard; without it start from what this run has read
                log.warning("x: could not count today's posts already read: %s", exc)
        headers = {"Authorization": f"Bearer {self.token}", "User-Agent": "spectre-signals/0.1"}
        async with httpx.AsyncClient(timeout=20, headers=headers, transport=self._transport) as client:
            while not stop.is_set():
                wait = self.poll_seconds
                for query in list(self.queries):
                    left = self._budget_left()
                    if left < PAGE_MIN:
                        log.warning("x: today's budget of %d posts is used up (about $%.2f); reading again tomorrow",
                                    self.daily_posts, self.read_today * self.cost_per_post)
                        wait = max(wait, 900.0)
                        break
                    try:
                        posts = await self._search(client, query, min(PAGE_MAX, left))
                    except httpx.HTTPStatusError as exc:
                        code, detail = exc.response.status_code, exc.response.text[:200]
                        if code == 400 and self._cashtags and "$" in query:
                            # This plan does not accept the cashtag operator: search for the symbols as plain words.
                            log.warning("x: the cashtag operator was refused (%s); searching for plain symbols instead", detail)
                            self._cashtags, self.queries = False, build_queries(self.symbols, cashtags=False)
                        elif code in (401, 403):
                            log.warning("x: not authorised (%d): %s. Is the bearer token set and does the plan include search?", code, detail)
                            wait = max(wait, 900.0)
                        elif code == 429:
                            log.warning("x: rate limited; waiting fifteen minutes")
                            wait = max(wait, 900.0)
                        else:
                            log.warning("x: HTTP %d: %s", code, detail)
                        break
                    except Exception as exc:
                        log.warning("x: %s: %s", type(exc).__name__, exc)
                        break
                    for p in posts:
                        await emit(p)
                    log.info("x: read %d posts (%d of %d today, about $%.2f)", len(posts), self.read_today, self.daily_posts,
                             self.read_today * self.cost_per_post)
                if await sleep_or_stop(wait, stop):
                    return
