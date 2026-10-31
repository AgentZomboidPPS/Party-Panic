"""Text analytics: sentiment, fear, ticker extraction, topic clustering.

Deliberately light: a lexicon sentiment model (VADER plus finance terms) and TF-IDF k-means
topics run at firehose speed on one core and are easy to audit. Swap in a transformer behind
the same interfaces when the volume and budget justify it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

import numpy as np
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

FINANCE_LEXICON = {
    "bullish": 2.5, "bearish": -2.5, "moon": 2.0, "mooning": 2.0, "rocket": 1.5, "calls": 1.2, "puts": -1.2,
    "squeeze": 1.0, "crash": -3.0, "crashing": -3.0, "dump": -2.0, "dumping": -2.0, "rally": 2.0, "ripping": 2.0,
    "selloff": -2.5, "sell-off": -2.5, "recession": -2.5, "layoffs": -2.0, "bagholder": -2.0, "ath": 2.0,
    "breakout": 1.8, "downgrade": -2.0, "upgrade": 2.0, "beat": 1.5, "miss": -1.5, "missed": -1.5,
    "bankrupt": -3.0, "bankruptcy": -3.0, "default": -2.0, "tariff": -1.0, "tariffs": -1.0, "overvalued": -1.5,
    "undervalued": 1.5, "buyback": 1.2, "dilution": -1.5, "guidance": 0.0, "tanking": -2.5, "soaring": 2.5,
    "plunge": -2.5, "plunging": -2.5, "surge": 2.0, "surging": 2.0, "bubble": -1.5, "panic": -3.0,
    "capitulation": -2.0, "oversold": 0.8, "overbought": -0.8, "hawkish": -1.0, "dovish": 1.0,
}

FEAR_TERMS = {
    "crash", "crashing", "recession", "layoffs", "panic", "collapse", "collapsing", "war", "default", "bankrupt",
    "bankruptcy", "depression", "selloff", "sell-off", "plunge", "plunging", "contagion", "bank run", "meltdown",
    "tanking", "capitulation", "fear", "scared", "afraid", "terrified", "bubble", "crisis", "inflation", "stagflation",
    "unemployment", "foreclosure", "evictions", "shutdown", "sanctions", "invasion", "nuclear",
}

_CASHTAG = re.compile(r"\$([A-Za-z][A-Za-z.\-]{0,7})\b")
_WORD = re.compile(r"[a-z][a-z\-']+")


class SentimentModel:
    def __init__(self):
        self._a = SentimentIntensityAnalyzer()
        self._a.lexicon.update(FINANCE_LEXICON)

    def score(self, text: str) -> float:
        """Compound sentiment in [-1, 1]."""
        return float(self._a.polarity_scores(text)["compound"])


def fear_flag(text: str) -> bool:
    low = text.lower()
    if "bank run" in low:
        return True
    return any(w in FEAR_TERMS for w in _WORD.findall(low))


class TickerExtractor:
    """Finds securities by cashtag ($ACME) or by name/alias ("Acme Systems", "Acme")."""

    def __init__(self, tickers: set[str], aliases: dict[str, str] | None = None):
        self.tickers = {t.upper() for t in tickers}
        aliases = {k.lower(): v.upper() for k, v in (aliases or {}).items() if len(k) >= 3}
        self.aliases = aliases
        if aliases:
            pat = "|".join(re.escape(a) for a in sorted(aliases, key=len, reverse=True))
            self._alias_re = re.compile(rf"\b({pat})\b", re.IGNORECASE)
        else:
            self._alias_re = None

    def extract(self, text: str) -> list[str]:
        found: list[str] = []
        for m in _CASHTAG.findall(text):
            t = m.upper()
            if t in self.tickers and t not in found:
                found.append(t)
        if self._alias_re:
            for m in self._alias_re.findall(text):
                t = self.aliases.get(m.lower())
                if t and t not in found:
                    found.append(t)
        return found


STOPWORDS_EXTRA = {
    "stock", "stocks", "market", "markets", "today", "just", "like", "think", "going", "really", "people", "time",
    "year", "week", "day", "new", "way", "lol", "got", "know", "right", "good", "bad", "big", "https", "http", "com",
    "www", "amp", "don", "ve", "ll", "re", "im", "rt", "make", "need", "want", "say", "said", "thing", "things",
}


@dataclass
class TopicCluster:
    label: str
    keywords: list[str]
    indices: np.ndarray  # positions of member texts


def _cosine_distances(X: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(X, axis=1)
    Xn = X / np.where(norms > 0, norms, 1.0)[:, None]
    D = 1.0 - Xn @ Xn.T
    D[norms == 0, :] = 1.0  # a post with no usable terms is far from everything
    D[:, norms == 0] = 1.0
    np.fill_diagonal(D, 0.0)
    return np.clip(D, 0.0, 2.0)


def cluster_topics(
    texts: list[str],
    max_topics: int = 15,
    min_cluster: int = 3,
    seed: int = 0,
    distance_threshold: float = 0.85,
    agglomerative_max_n: int = 2000,
) -> list[TopicCluster]:
    """Group posts into topics.

    Up to `agglomerative_max_n` posts: average-linkage agglomerative clustering on TF-IDF cosine
    distance with a fixed threshold, so the number of topics follows the data and nothing is
    forced into one giant cluster. Beyond that (firehose windows): mini-batch k-means with
    k ~ sqrt(n/3). Clusters smaller than `min_cluster` are dropped; the largest `max_topics` kept.
    """
    from sklearn.cluster import AgglomerativeClustering, MiniBatchKMeans
    from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS, TfidfVectorizer

    n = len(texts)
    if n == 0:
        return []
    stop = list(ENGLISH_STOP_WORDS | STOPWORDS_EXTRA)
    vec = TfidfVectorizer(
        stop_words=stop,
        ngram_range=(1, 2),
        min_df=2 if n >= 10 else 1,
        max_features=8000,
        token_pattern=r"(?u)\b[a-zA-Z$][a-zA-Z\-]{1,}\b",
        sublinear_tf=True,
    )
    try:
        X = vec.fit_transform(texts)
    except ValueError:  # all stop words
        return [TopicCluster("misc", [], np.arange(n))]
    terms = np.array(vec.get_feature_names_out())

    if n < 2 * min_cluster:
        weights = np.asarray(X.sum(axis=0)).ravel()
        top = terms[np.argsort(weights)[::-1][:6]].tolist()
        return [TopicCluster(" / ".join(top[:3]) or "misc", top, np.arange(n))]

    if n <= agglomerative_max_n:
        dense = X.toarray()
        labels = AgglomerativeClustering(
            n_clusters=None, metric="precomputed", linkage="average", distance_threshold=distance_threshold
        ).fit_predict(_cosine_distances(dense))
        centroid = lambda idx: dense[idx].mean(axis=0)  # noqa: E731
    else:
        k = int(np.clip(np.sqrt(n / 3.0), 2, max_topics))
        km = MiniBatchKMeans(n_clusters=k, random_state=seed, n_init=3, batch_size=1024)
        labels = km.fit_predict(X)
        centroid = lambda idx: np.asarray(X[idx].mean(axis=0)).ravel()  # noqa: E731

    out: list[TopicCluster] = []
    for c in np.unique(labels):
        idx = np.where(labels == c)[0]
        if len(idx) < min_cluster:
            continue
        top = terms[np.argsort(centroid(idx))[::-1][:8]].tolist()
        out.append(TopicCluster(" / ".join(top[:3]), top, idx))
    out.sort(key=lambda c: -len(c.indices))
    return out[:max_topics]
