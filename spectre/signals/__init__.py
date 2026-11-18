"""Signals: public conversation and prediction markets turned into aggregate, tradeable data.

Pipeline:  sources -> screening (bots, spam, duplicates) -> NLP (sentiment, fear, tickers)
           -> store -> aggregation (topic bubbles, sentiment bars, fear index)
           -> signals (z-scores) -> backtest / paper strategy / dashboard

Only aggregates leave this package. Author identity is reduced to a salted hash used for
screening and de-duplication; no handles, names or profiles are stored.
"""
