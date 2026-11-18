"""A sentiment model learned from what people said they meant.

Stocktwits lets an author tag a post Bullish or Bearish. Those tags are ground truth in the
only sense that matters here (the author's own stance), and they come attached to exactly the
kind of text the model has to read: short, slangy market talk. Most posts carry no tag, so a
model that reads them well improves every score built on top.

The model is deliberately plain: word and word-pair frequencies into a logistic regression.
Ticker symbols, links and numbers are blanked first, so it learns the language of being
bullish or bearish and not "NVDA was popular on the day I was trained".

It is not used on its own. On the first day's 1,640 tagged posts it ranked later posts no
better than the general-purpose word list did (0.62 against 0.63, where 0.50 is a coin toss).
But the two were nearly uncorrelated, and an even blend of them reached 0.66. So what is
tested, and used if it earns it, is the **blend**: half word list, half learned model, the
learned half rescaled to the word list's spread.

It is tested the way it would be used: trained on earlier posts, judged on later ones, block
after block. The blend replaces the word list only when it ranks later posts clearly better.
Otherwise the word list stays, and the evaluation says why.
"""

from __future__ import annotations

import re
from datetime import UTC, datetime
from pathlib import Path

import numpy as np
import pandas as pd
from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.signals.models import SocialPost

MIN_LABELLED = 800  # fewer tagged posts than this and nothing is trained
MIN_TESTED = 300  # ... or judged on fewer later posts than this
MIN_AUC = 0.60  # the blend must rank later posts at least this well (0.5 is a coin toss)
MIN_GAIN = 0.03  # ... and beat the word list alone by at least this much
SIDE = 0.2  # a score beyond +/- this counts as taking a side (the same line the bot draws)

_CASHTAG = re.compile(r"\$[A-Za-z][A-Za-z.\-]{0,7}")
_URL = re.compile(r"https?://\S+")
_NUMBER = re.compile(r"\d[\d,.]*%?")


def normalise(text: str) -> str:
    text = _URL.sub(" url ", text)
    text = _CASHTAG.sub(" cashtag ", text)
    return _NUMBER.sub(" num ", text).lower()


def labelled(session: Session) -> pd.DataFrame:
    """Tagged posts, oldest first, one per distinct text: text, label (1 bullish, 0 bearish),
    when it was posted, and what the word-list scorer made of it."""
    from spectre.signals.nlp import SentimentModel

    rows = session.execute(
        select(SocialPost.text, SocialPost.source_sentiment, SocialPost.posted_at, SocialPost.dedup_hash)
        .where(SocialPost.source_sentiment.in_(("Bullish", "Bearish")), SocialPost.screened_out.is_(False))
        .order_by(SocialPost.posted_at, SocialPost.id)
    ).all()
    df = pd.DataFrame(rows, columns=["text", "tag", "at", "dedup"])
    df = df.drop_duplicates("dedup").drop(columns="dedup").reset_index(drop=True)
    df["label"] = (df["tag"] == "Bullish").astype(int)
    # Scored afresh rather than read from the stored column: once a blend is in use the stored
    # score is the blend's, and the word list has to be judged as itself.
    words = SentimentModel()
    df["lexicon"] = [words.lexicon_score(t) for t in df["text"]]
    return df


def fit(texts: list[str], labels: list[int]):
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import make_pipeline

    model = make_pipeline(
        TfidfVectorizer(preprocessor=normalise, ngram_range=(1, 2), min_df=2, sublinear_tf=True,
                        token_pattern=r"(?u)\b[a-z][a-z']+\b|[\U0001F300-\U0001FAFF]"),
        LogisticRegression(C=2.0, class_weight="balanced", max_iter=1000),
    )
    model.fit(texts, labels)
    return model


def _auc(labels: np.ndarray, scores: np.ndarray) -> float | None:
    from sklearn.metrics import roc_auc_score

    return float(roc_auc_score(labels, scores)) if len(set(labels)) == 2 else None


def _sides(labels: np.ndarray, scores: np.ndarray) -> dict:
    """How often it takes a side, and how often it is right when it does."""
    took = np.abs(scores) > SIDE
    right = ((scores > SIDE) & (labels == 1)) | ((scores < -SIDE) & (labels == 0))
    return {"takes_a_side": float(took.mean()), "right_when_it_does": float(right[took].mean()) if took.any() else None}


def evaluate(df: pd.DataFrame, blocks: int = 5) -> dict:
    """Train on earlier posts, judge on later ones: the first block trains a model judged on the
    second, the first two train one judged on the third, and so on. Every judged post is one
    the model had not seen and that came after everything it had."""
    n = len(df)
    out: dict = {"labelled": int(n), "bullish_share": float(df["label"].mean()) if n else None, "adopt": False}
    if n < MIN_LABELLED:
        out["reason"] = f"only {n} tagged posts so far; {MIN_LABELLED} are needed before a model is worth training"
        return out
    edges = [round(n * i / blocks) for i in range(blocks + 1)]
    scores = np.full(n, np.nan)
    for k in range(1, blocks):
        train, test = df.iloc[: edges[k]], df.iloc[edges[k] : edges[k + 1]]
        if train["label"].nunique() < 2 or test.empty:
            continue
        model = fit(list(train["text"]), list(train["label"]))
        scores[edges[k] : edges[k + 1]] = 2 * model.predict_proba(list(test["text"]))[:, 1] - 1
    judged = ~np.isnan(scores)
    y, learned, lexicon = df["label"].to_numpy()[judged], scores[judged], df["lexicon"].to_numpy()[judged]
    # Bring the learned half to the word list's spread, within reason: if either hardly varies
    # (a word list that knows none of the words scores everything zero) leave it as it is.
    scale = 1.0
    if len(learned) and learned.std() > 1e-6 and lexicon.std() > 1e-6:
        scale = float(min(8.0, max(0.25, lexicon.std() / learned.std())))
    blended = blend(lexicon, learned, scale)
    out.update({
        "judged": int(judged.sum()), "from": df["at"].iloc[0].isoformat(timespec="minutes"),
        "to": df["at"].iloc[-1].isoformat(timespec="minutes"),
        "majority_share": float(max(y.mean(), 1 - y.mean())) if len(y) else None,
        "scale": scale,
        "lexicon": {"auc": _auc(y, lexicon), **_sides(y, lexicon)},
        "learned": {"auc": _auc(y, learned), **_sides(y, learned * scale)},
        "blend": {"auc": _auc(y, blended), **_sides(y, blended)},
    })
    both, words = out["blend"]["auc"], out["lexicon"]["auc"]
    if out["judged"] < MIN_TESTED or both is None or words is None:
        out["reason"] = f"judged on only {out['judged']} later posts; {MIN_TESTED} are needed"
    elif both < MIN_AUC:
        out["reason"] = f"the blend ranks later posts at {both:.2f}, where 0.50 is a coin toss; {MIN_AUC:.2f} is the bar"
    elif both < words + MIN_GAIN:
        out["reason"] = f"the blend ranks later posts at {both:.2f} against the word list's {words:.2f}; not enough of a gain"
    else:
        out["adopt"] = True
        out["reason"] = f"the blend ranks later posts at {both:.2f} against the word list's {words:.2f}"
    return out


def blend(lexicon, learned, scale: float):
    """Half word list, half learned model (rescaled to the word list's spread), kept in [-1, 1]."""
    return np.clip(0.5 * np.asarray(lexicon, dtype=float) + 0.5 * np.asarray(learned, dtype=float) * scale, -1.0, 1.0)


def model_path(database_url: str) -> Path | None:
    """Where the learned model lives: beside a SQLite database file; nowhere for an in-memory one."""
    if database_url.startswith("sqlite:///") and ":memory:" not in database_url and len(database_url) > len("sqlite:///"):
        return Path(database_url[len("sqlite:///"):]).resolve().parent / "sentiment_model.joblib"
    if database_url.startswith("sqlite"):
        return None
    return Path.home() / ".spectre" / "sentiment_model.joblib"


def train(session: Session, path: Path | None) -> dict:
    """Evaluate, and if the model earns its place, train it on everything and save it. If it
    does not, any saved model is removed so the word list is used again."""
    import joblib

    df = labelled(session)
    result = evaluate(df)
    if path is None:
        return result
    if result["adopt"]:
        path.parent.mkdir(parents=True, exist_ok=True)
        joblib.dump({"model": fit(list(df["text"]), list(df["label"])), "scale": result["scale"],
                     "trained_at": datetime.now(UTC).isoformat(timespec="seconds"), "evaluation": result}, path)
    elif path.exists():
        path.unlink()
    return result


def load(path: Path | None):
    """The saved model and its evaluation, or None."""
    if path is None or not path.exists():
        return None
    import joblib

    try:
        return joblib.load(path)
    except Exception:  # a file from an incompatible version: fall back to the word list
        return None
