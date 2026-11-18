"""Company fundamentals from SEC filings: quarterly results and how they compare.

Source: the SEC's EDGAR "company facts" data, which holds every number a company has tagged in
its 10-Q and 10-K filings. This package turns that into one clean value per quarter per metric,
then compares the latest quarter with the one before it and with the same quarter a year ago.
"""
