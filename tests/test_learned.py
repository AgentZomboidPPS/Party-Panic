"""The learned sentiment model: trained on tagged posts, judged on later ones, used only if it earns it."""

import random
from datetime import datetime, timedelta

import pytest

from spectre.db import init_db, make_engine, make_session_factory
from spectre.signals import learned
from spectre.signals.models import SocialPost
from spectre.signals.nlp import SentimentModel

T0 = datetime(2026, 11, 18, 14, 0)
# Slang the general word list has never heard of, which is the whole point of learning from tags.
UP = ["zorping flibber", "quazzle wumbo", "snarfle zib", "flibber quazzle", "wumbo zorping"]
DOWN = ["drazzled blorp", "kerfluff murkle", "zonked grib", "blorp kerfluff", "murkle drazzled"]
FILLER = ["today", "this week", "at the open", "into the close", "before the print", "after lunch", "again", "for real"]


def posts(n, honest=True, seed=1):
    rng = random.Random(seed)
    out = []
    for i in range(n):
        bullish = rng.random() < 0.6
        said = rng.choice(UP if bullish else DOWN)
        tag = ("Bullish" if bullish else "Bearish") if honest else rng.choice(["Bullish", "Bearish"])
        text = f"$T{i % 7} {said} {rng.choice(FILLER)} {rng.choice(FILLER)} {i}"
        when = T0 + timedelta(minutes=i)
        out.append(SocialPost(source="stocktwits", external_id=str(i), author_hash=f"a{i % 50}", author_quality=1.0, dedup_hash=str(i),
                              text=text, posted_at=when, ingested_at=when, sentiment=0.7 if tag == "Bullish" else -0.7,
                              model_sentiment=0.0, tickers=[], fear=False, screened_out=False, source_sentiment=tag))
    return out


@pytest.fixture
def db(tmp_path):
    url = f"sqlite:///{tmp_path / 'spectre.db'}"
    e = make_engine(url)
    init_db(e)
    with make_session_factory(e)() as s:
        yield s, url


def test_a_model_that_reads_the_slang_is_adopted_and_blended_in(db):
    s, url = db
    s.add_all(posts(1_000))
    s.commit()
    path = learned.model_path(url)
    assert path.name == "sentiment_model.joblib" and path.parent == path.parent.resolve()

    r = learned.train(s, path)
    assert r["labelled"] == 1_000 and r["judged"] == 800, "the first of five blocks only trains; the other four are judged"
    assert r["lexicon"]["auc"] == pytest.approx(0.5, abs=0.06), "the word list has never seen these words"
    assert r["learned"]["auc"] > 0.95 and r["blend"]["auc"] > 0.95 and r["adopt"] and "against the word list" in r["reason"]
    assert path.exists()

    plain, blended = SentimentModel(), SentimentModel(path)
    assert plain.kind == "word list" and "learned" in blended.kind and blended.trained_at
    assert plain.score("$ABC zorping flibber today") == 0.0
    assert blended.score("$ABC zorping flibber today") > 0.2 and blended.score("$ABC drazzled blorp again") < -0.2
    assert -1.0 <= blended.score("great amazing wonderful zorping flibber quazzle wumbo") <= 1.0


def test_a_model_that_learns_nothing_is_not_used_and_an_old_one_is_removed(db):
    s, url = db
    path = learned.model_path(url)
    s.add_all(posts(1_000, honest=False))  # tags unrelated to the text: nothing to learn
    s.commit()
    path.write_bytes(b"left over from a better day")
    r = learned.train(s, path)
    assert not r["adopt"] and r["blend"]["auc"] < 0.6 and "coin toss" in r["reason"]
    assert not path.exists(), "the word list is used again"
    assert SentimentModel(path).kind == "word list"


def test_too_few_tagged_posts_trains_nothing(db):
    s, url = db
    s.add_all(posts(200))
    s.commit()
    r = learned.train(s, learned.model_path(url))
    assert not r["adopt"] and "only 200 tagged posts" in r["reason"] and "blend" not in r


def test_tickers_links_and_numbers_are_blanked_before_learning():
    assert learned.normalise("$NVDA to 200 by Friday https://x.co/abc +12.5%") == " cashtag  to  num  by friday  url  + num "
    assert learned.model_path("sqlite://") is None and learned.model_path("sqlite:///:memory:") is None
    assert learned.load(None) is None


def test_a_damaged_model_file_falls_back_to_the_word_list(tmp_path):
    bad = tmp_path / "sentiment_model.joblib"
    bad.write_bytes(b"not a model")
    assert learned.load(bad) is None and SentimentModel(bad).kind == "word list"
