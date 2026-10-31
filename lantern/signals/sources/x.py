"""X (Twitter) recent search, API v2. Requires a bearer token with a paid tier that includes
search (`LANTERN_X_BEARER_TOKEN`). The filtered-stream endpoint is the better fit for a firehose
once the account tier allows it; this polling adapter is the lowest common denominator.

Not exercised in this repository's test environment (no outbound network, no token).
"""

from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime

import httpx

from lantern.signals.sources.base import Emit, Post, sleep_or_stop, to_naive_utc

log = logging.getLogger(__name__)


class XRecentSearch:
    name = "x"

    def __init__(self, query: str, poll_seconds: float = 60, bearer_token: str | None = None):
        self.query = query
        self.poll_seconds = poll_seconds
        self.token = bearer_token or os.environ.get("LANTERN_X_BEARER_TOKEN")
        if not self.token:
            raise ValueError("X adapter needs a bearer token (LANTERN_X_BEARER_TOKEN)")
        self._since_id: str | None = None

    async def run(self, emit: Emit, stop: asyncio.Event) -> None:
        headers = {"Authorization": f"Bearer {self.token}", "User-Agent": "lantern-signals/0.1"}
        async with httpx.AsyncClient(timeout=20, headers=headers) as client:
            while not stop.is_set():
                params = {
                    "query": self.query,
                    "max_results": 100,
                    "tweet.fields": "created_at,lang,author_id,public_metrics",
                    "expansions": "author_id",
                    "user.fields": "created_at,public_metrics",
                }
                if self._since_id:
                    params["since_id"] = self._since_id
                try:
                    r = await client.get("https://api.x.com/2/tweets/search/recent", params=params)
                    r.raise_for_status()
                    body = r.json()
                    users = {u["id"]: u for u in body.get("includes", {}).get("users", [])}
                    for t in body.get("data", []):
                        self._since_id = max(self._since_id or "0", t["id"], key=int)
                        u = users.get(t.get("author_id"), {})
                        created = to_naive_utc(datetime.fromisoformat(t["created_at"].replace("Z", "+00:00")))
                        age = None
                        if u.get("created_at"):
                            age = (created - to_naive_utc(datetime.fromisoformat(u["created_at"].replace("Z", "+00:00")))).days
                        await emit(
                            Post(
                                source=self.name,
                                external_id=t["id"],
                                author_id=t.get("author_id", ""),
                                text=t.get("text", ""),
                                created_at=created,
                                lang=t.get("lang"),
                                followers=(u.get("public_metrics") or {}).get("followers_count"),
                                account_age_days=age,
                            )
                        )
                except Exception as exc:
                    log.warning("x: %s", exc)
                if await sleep_or_stop(self.poll_seconds, stop):
                    return
