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
    """Scores a post from -1 (bearish) to +1 (bullish).

    The base is a general-purpose word list with finance vocabulary added. When a model learned
    from authors' own Bullish/Bearish tags has been trained and has earned its place (see
    `signals/learned.py`), the score is an even blend of the two."""

    def __init__(self, learned_path=None):
        self._a = SentimentIntensityAnalyzer()
        self._a.lexicon.update(FINANCE_LEXICON)
        self._learned, self._scale, self.trained_at = None, 1.0, None
        if learned_path is not None:
            from spectre.signals.learned import load

            saved = load(learned_path)
            if saved:
                self._learned, self._scale, self.trained_at = saved["model"], float(saved.get("scale", 1.0)), saved.get("trained_at")

    @property
    def kind(self) -> str:
        return "word list blended with a model learned from tagged posts" if self._learned is not None else "word list"

    def lexicon_score(self, text: str) -> float:
        return float(self._a.polarity_scores(text)["compound"])

    def score(self, text: str) -> float:
        """Sentiment in [-1, 1]."""
        base = self.lexicon_score(text)
        if self._learned is None:
            return base
        learned = 2.0 * float(self._learned.predict_proba([text])[0, 1]) - 1.0
        return float(min(1.0, max(-1.0, 0.5 * base + 0.5 * learned * self._scale)))


def fear_flag(text: str) -> bool:
    low = text.lower()
    if "bank run" in low:
        return True
    return any(w in FEAR_TERMS for w in _WORD.findall(low))


# General finance vocabulary: used to pre-filter a firehose down to market conversation.
FINANCE_TERMS = [
    "stock market", "stocks", "earnings", "nasdaq", "s&p 500", "dow jones", "wall street", "federal reserve",
    "the fed", "rate cut", "rate cuts", "rate hike", "interest rates", "inflation", "recession", "tariffs",
    "layoffs", "jobs report", "unemployment", "treasury yields", "bond market", "bitcoin", "crypto", "ipo",
    "short squeeze", "bull market", "bear market", "price target", "market cap", "the economy", "stock price",
    "shareholders", "investors", "hedge fund", "housing market", "mortgage rates", "gas prices", "oil prices",
]

# Words that make it plausible a post about "apple" or "target" means the company.
_FIN_CONTEXT = re.compile(
    r"\$[A-Za-z]{1,6}\b|\b(?:stocks?|shares?|shareholders?|earnings|revenue|guidance|eps|dividends?|buybacks?|ipo|"
    r"market cap|price target|valuation|investors?|invest(?:ing|ment|ed)?|traders?|trading|calls|puts|options|"
    r"bullish|bearish|rally|sell-?off|downgrade[sd]?|upgrade[sd]?|analysts?|nasdaq|nyse|s&p|wall street|"
    r"quarter(?:ly)?|q[1-4]|ceo|cfo|antitrust|layoffs|10-[kq]|crypto|coins?|tokens?|altcoins?|memecoins?|"
    r"blockchain|defi|staking|hodl)\b",
    re.IGNORECASE,
)
_BARE = re.compile(r"(?<![\w$])[A-Z]{2,5}(?:\.[A-Z])?(?![\w])")


class TickerExtractor:
    """Finds securities in text.

    Four routes, from most to least certain:
    - cashtags (`$NVDA`): always accepted
    - `aliases` (unambiguous names such as "nvidia", "goldman sachs"): always accepted
    - `context_aliases` (names that are also ordinary words: "apple", "meta", "target"):
      accepted only when the text also reads like market talk
    - bare upper-case symbols: `bare_tickers` always, `context_bare` only with market context
    """

    def __init__(
        self,
        tickers: set[str],
        aliases: dict[str, str] | None = None,
        context_aliases: dict[str, str] | None = None,
        bare_tickers: set[str] | None = None,
        context_bare: set[str] | None = None,
    ):
        self.tickers = {t.upper() for t in tickers}
        self.aliases = {k.lower(): v.upper() for k, v in (aliases or {}).items() if len(k) >= 3}
        self.context_aliases = {k.lower(): v.upper() for k, v in (context_aliases or {}).items() if len(k) >= 3}
        self.bare_tickers = {t.upper() for t in (bare_tickers or set())}
        self.context_bare = {t.upper() for t in (context_bare or set())}
        self._alias_re = self._compile(self.aliases)
        self._context_re = self._compile(self.context_aliases)

    @staticmethod
    def _compile(mapping: dict[str, str]) -> re.Pattern | None:
        if not mapping:
            return None
        pat = "|".join(re.escape(a) for a in sorted(mapping, key=len, reverse=True))
        return re.compile(rf"(?<![\w$])({pat})(?![\w])", re.IGNORECASE)

    def extract(self, text: str) -> list[str]:
        found: list[str] = []

        def add(t: str | None) -> None:
            if t and t not in found:
                found.append(t)

        for m in _CASHTAG.findall(text):
            t = m.upper().rstrip(".-")
            if t.endswith(".X") and t[:-2] in self.tickers:  # "$BTC.X": how stock platforms write a coin
                t = t[:-2]
            if t in self.tickers:
                add(t)
        if self._alias_re:
            for m in self._alias_re.findall(text):
                add(self.aliases.get(m.lower()))
        if not (self._context_re or self.bare_tickers or self.context_bare):
            return found
        has_context = bool(_FIN_CONTEXT.search(text))
        if self._context_re and has_context:
            for m in self._context_re.findall(text):
                add(self.context_aliases.get(m.lower()))
        if self.bare_tickers or self.context_bare:
            for tok in _BARE.findall(text):
                tok = tok[:-2] if tok.endswith(".X") else tok
                if tok in self.bare_tickers or (has_context and tok in self.context_bare):
                    add(tok)
        return found


STOPWORDS_EXTRA = {
    "stock", "stocks", "market", "markets", "today", "just", "like", "think", "going", "really", "people", "time",
    "year", "week", "day", "new", "way", "lol", "got", "know", "right", "good", "bad", "big", "https", "http", "com",
    "www", "amp", "don", "ve", "ll", "re", "im", "rt", "make", "need", "want", "say", "said", "thing", "things",
    "thats", "dont", "doesnt", "didnt", "isnt", "cant", "wont", "ive", "youre", "theyre", "gonna", "gotta", "yeah",
    "lets", "let", "looks", "look", "looking", "getting", "come", "coming", "went", "goes", "actually", "probably",
    "maybe", "sure", "ok", "okay", "hey", "oh", "yes", "nice", "great", "bit", "lot", "lots", "guys", "guy", "man",
}


@dataclass
class TopicCluster:
    label: str
    keywords: list[str]
    indices: np.ndarray  # positions of member texts


_NOISE = re.compile(r"https?://\S+|\b[\w.-]+\.(?:com|org|net|io|co|app|tv|gg|social)\S*|@[\w.]+", re.IGNORECASE)


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
    texts = [_NOISE.sub(" ", t) for t in texts]  # links and @handles are not what a post is about
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
