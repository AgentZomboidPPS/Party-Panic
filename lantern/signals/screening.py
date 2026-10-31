"""Activity screening: keep posts from people, drop bots, spam and coordinated campaigns.

No platform gives us a clean "is a human" flag, so quality is a product of independent
heuristics, each in (0, 1]. A post is screened out below `threshold`; it is still stored
(flagged) so the screening itself can be audited and tuned.

Signals used
- text shape: too short, cashtag/hashtag stuffing, link-only, shouting
- author burst: too many posts in a short window from one author
- author self-duplication: near-identical text to the author's own recent posts
- coordination: the same near-identical text from many authors in a short window
- account metadata when the source provides it: no followers, very new account
"""

from __future__ import annotations

import hashlib
import re
from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta

from lantern.signals.sources.base import Post

_TOKEN = re.compile(r"[a-z0-9$#@']+")
_URL = re.compile(r"https?://\S+")
_CASHTAG = re.compile(r"\$[A-Za-z]{1,6}\b")
_HASHTAG = re.compile(r"#\w+")


def author_hash(source: str, author_id: str, salt: str = "lantern") -> str:
    return hashlib.blake2b(f"{salt}|{source}|{author_id}".encode(), digest_size=16).hexdigest()


def tokens(text: str) -> list[str]:
    return _TOKEN.findall(_URL.sub(" ", text.lower()))


def simhash(text: str, bits: int = 64) -> int:
    """64-bit SimHash over word bigrams; near-duplicates differ in few bits."""
    toks = tokens(text)
    shingles = [" ".join(toks[i : i + 2]) for i in range(max(len(toks) - 1, 1))] or toks
    v = [0] * bits
    for sh in shingles:
        h = int.from_bytes(hashlib.blake2b(sh.encode(), digest_size=8).digest(), "big")
        for i in range(bits):
            v[i] += 1 if (h >> i) & 1 else -1
    return sum(1 << i for i in range(bits) if v[i] > 0)


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()


@dataclass
class ScreenResult:
    quality: float
    screened_out: bool
    reason: str | None
    dedup_hash: int
    factors: dict[str, float]


class Screener:
    def __init__(
        self,
        threshold: float = 0.35,
        burst_window: timedelta = timedelta(minutes=10),
        burst_soft: int = 4,
        burst_hard: int = 8,
        dup_bits: int = 3,
        coord_window: timedelta = timedelta(minutes=30),
        coord_authors: int = 5,
        author_memory: int = 50,
    ):
        self.threshold = threshold
        self.burst_window = burst_window
        self.burst_soft = burst_soft
        self.burst_hard = burst_hard
        self.dup_bits = dup_bits
        self.coord_window = coord_window
        self.coord_authors = coord_authors
        self.author_memory = author_memory
        # author_hash -> deque[(ts, simhash)]
        self._recent: dict[str, deque[tuple[datetime, int]]] = defaultdict(lambda: deque(maxlen=author_memory))
        # simhash bucket (top 16 bits) -> deque[(ts, author_hash, simhash)]
        self._global: dict[int, deque[tuple[datetime, str, int]]] = defaultdict(lambda: deque(maxlen=2000))
        self.stats: dict[str, dict] = {}

    # --- individual factors -------------------------------------------------------------

    @staticmethod
    def text_factor(text: str) -> tuple[float, str | None]:
        stripped = _URL.sub("", text).strip()
        if len(stripped) < 8:
            return 0.2, "link_or_empty" if _URL.search(text) else "too_short"
        if len(_CASHTAG.findall(text)) > 5:
            return 0.3, "cashtag_stuffing"
        if len(_HASHTAG.findall(text)) > 6:
            return 0.4, "hashtag_stuffing"
        letters = [c for c in stripped if c.isalpha()]
        if len(letters) > 20 and sum(c.isupper() for c in letters) / len(letters) > 0.7:
            return 0.6, "shouting"
        return 1.0, None

    @staticmethod
    def account_factor(post: Post) -> tuple[float, str | None]:
        if post.followers is not None and post.followers == 0:
            return 0.5, "no_followers"
        if post.account_age_days is not None and post.account_age_days < 7:
            return 0.6, "new_account"
        return 1.0, None

    def burst_factor(self, recent: deque, now: datetime) -> tuple[float, str | None, int]:
        n = sum(1 for ts, _ in recent if now - ts <= self.burst_window)
        if n >= self.burst_hard:
            return 0.25, "burst", n
        if n >= self.burst_soft:
            return 0.7, "burst_soft", n
        return 1.0, None, n

    def self_dup_factor(self, recent: deque, h: int) -> tuple[float, str | None]:
        if any(hamming(h, prev) <= self.dup_bits for _, prev in recent):
            return 0.2, "self_duplicate"
        return 1.0, None

    def coordination_factor(self, bucket: deque, h: int, author: str, now: datetime) -> tuple[float, str | None]:
        authors = {a for ts, a, prev in bucket if a != author and now - ts <= self.coord_window and hamming(h, prev) <= self.dup_bits}
        if len(authors) >= self.coord_authors:
            return 0.2, "coordinated"
        return 1.0, None

    # --- main entry -------------------------------------------------------------------

    def screen(self, post: Post, author: str) -> ScreenResult:
        now = post.created_at
        h = simhash(post.text)
        recent = self._recent[author]
        bucket = self._global[h >> 48]

        factors: dict[str, float] = {}
        reasons: list[tuple[float, str]] = []
        for f, reason in (self.text_factor(post.text), self.account_factor(post)):
            if reason:
                factors[reason] = f
                reasons.append((f, reason))
        bf, breason, n_burst = self.burst_factor(recent, now)
        if breason:
            factors[breason] = bf
            reasons.append((bf, breason))
        df, dreason = self.self_dup_factor(recent, h)
        if dreason:
            factors[dreason] = df
            reasons.append((df, dreason))
        cf, creason = self.coordination_factor(bucket, h, author, now)
        if creason:
            factors[creason] = cf
            reasons.append((cf, creason))

        quality = 1.0
        for f in factors.values():
            quality *= f
        reason = min(reasons)[1] if reasons else None

        recent.append((now, h))
        bucket.append((now, author, h))
        st = self.stats.setdefault(author, {"posts": 0, "dups": 0, "burst_max": 0, "first": now, "last": now})
        st["posts"] += 1
        st["dups"] += int(dreason is not None)
        st["burst_max"] = max(st["burst_max"], n_burst + 1)
        st["last"] = max(st["last"], now)
        st["first"] = min(st["first"], now)

        return ScreenResult(quality, quality < self.threshold, reason, h, factors)
