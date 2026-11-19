"""A curated real-world universe, so live conversation maps to actual companies.

Reference data only: tickers, names, sectors and the names people use for them. No prices are
loaded here. Each entry says how the company may be recognised in free text:

- `aliases`: unambiguous names ("nvidia", "goldman sachs"); always accepted
- `context`: names that are also ordinary words ("apple", "meta", "visa"); accepted only when
  the text also reads like market talk
- `bare`: whether the upper-case symbol on its own counts: "yes", "context" (needs market
  talk, for symbols that are also words or very short), or "no"
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.orm import Session

from spectre.models import Security


@dataclass(frozen=True)
class Entry:
    ticker: str
    name: str
    sector: str
    aliases: tuple[str, ...] = ()
    context: tuple[str, ...] = ()
    bare: str = "yes"
    asset_class: str = "Equity"
    country: str = "US"


T, F, H, CD, CS, E, IND, C, M = (
    "Technology", "Financials", "Health Care", "Consumer Discretionary", "Consumer Staples", "Energy",
    "Industrials", "Communication Services", "Materials",
)

UNIVERSE: list[Entry] = [
    # Technology
    Entry("AAPL", "Apple Inc.", T, ("apple inc",), ("apple", "iphone")),
    Entry("MSFT", "Microsoft Corporation", T, ("microsoft",)),
    Entry("NVDA", "NVIDIA Corporation", T, ("nvidia",)),
    Entry("AVGO", "Broadcom Inc.", T, ("broadcom",)),
    Entry("AMD", "Advanced Micro Devices", T, ("advanced micro devices",)),
    Entry("INTC", "Intel Corporation", T, ("intel corp", "intel corporation"), ("intel",)),
    Entry("ORCL", "Oracle Corporation", T, ("oracle corp", "oracle corporation"), ("oracle",)),
    Entry("CRM", "Salesforce Inc.", T, ("salesforce",)),
    Entry("PLTR", "Palantir Technologies", T, ("palantir",)),
    Entry("TSM", "Taiwan Semiconductor Manufacturing", T, ("tsmc", "taiwan semiconductor"), country="TW"),
    Entry("ASML", "ASML Holding", T, country="NL"),
    Entry("MU", "Micron Technology", T, ("micron technology",), ("micron",), bare="context"),
    Entry("SMCI", "Super Micro Computer", T, ("supermicro", "super micro computer")),
    Entry("COIN", "Coinbase Global", F, ("coinbase",), bare="context"),
    Entry("MSTR", "Strategy Inc. (MicroStrategy)", T, ("microstrategy",)),
    # Communication services
    Entry("GOOGL", "Alphabet Inc.", C, ("alphabet inc", "googl"), ("google", "alphabet")),
    Entry("META", "Meta Platforms", C, ("meta platforms",), ("meta", "facebook"), bare="context"),
    Entry("NFLX", "Netflix Inc.", C, (), ("netflix",)),
    Entry("DIS", "The Walt Disney Company", C, ("walt disney",), ("disney",), bare="context"),
    # Consumer
    Entry("AMZN", "Amazon.com Inc.", CD, ("amazon.com",), ("amazon",)),
    Entry("TSLA", "Tesla Inc.", CD, ("tesla",)),
    Entry("HD", "The Home Depot", CD, ("home depot",), bare="context"),
    Entry("MCD", "McDonald's Corporation", CD, (), ("mcdonald's", "mcdonalds")),
    Entry("NKE", "Nike Inc.", CD, ("nike inc",), ("nike",)),
    Entry("SBUX", "Starbucks Corporation", CD, (), ("starbucks",)),
    Entry("GME", "GameStop Corp.", CD, ("gamestop",)),
    Entry("F", "Ford Motor Company", CD, ("ford motor",), bare="no"),
    Entry("GM", "General Motors", CD, ("general motors",), bare="context"),
    Entry("WMT", "Walmart Inc.", CS, ("walmart",)),
    Entry("COST", "Costco Wholesale", CS, ("costco wholesale",), ("costco",), bare="context"),
    Entry("KO", "The Coca-Cola Company", CS, ("coca-cola", "coca cola"), bare="context"),
    Entry("PEP", "PepsiCo Inc.", CS, ("pepsico",)),
    # Financials
    Entry("JPM", "JPMorgan Chase & Co.", F, ("jpmorgan", "jp morgan")),
    Entry("BAC", "Bank of America", F, ("bank of america",)),
    Entry("GS", "Goldman Sachs Group", F, ("goldman sachs",), bare="context"),
    Entry("MS", "Morgan Stanley", F, ("morgan stanley",), bare="context"),
    Entry("WFC", "Wells Fargo & Company", F, ("wells fargo",)),
    Entry("C", "Citigroup Inc.", F, ("citigroup",), bare="no"),
    Entry("BRK.B", "Berkshire Hathaway", F, ("berkshire hathaway",), ("berkshire",)),
    Entry("V", "Visa Inc.", F, ("visa inc",), ("visa",), bare="no"),
    Entry("MA", "Mastercard Incorporated", F, ("mastercard",), bare="context"),
    # Health care
    Entry("UNH", "UnitedHealth Group", H, ("unitedhealth", "unitedhealthcare", "united healthcare")),
    Entry("LLY", "Eli Lilly and Company", H, ("eli lilly",)),
    Entry("PFE", "Pfizer Inc.", H, ("pfizer",)),
    Entry("JNJ", "Johnson & Johnson", H, ("johnson & johnson", "johnson and johnson")),
    Entry("MRNA", "Moderna Inc.", H, ("moderna",)),
    Entry("NVO", "Novo Nordisk", H, ("novo nordisk",), country="DK"),
    # Energy and industrials
    Entry("XOM", "Exxon Mobil Corporation", E, ("exxon", "exxonmobil", "exxon mobil")),
    Entry("CVX", "Chevron Corporation", E, (), ("chevron",)),
    Entry("BA", "The Boeing Company", IND, ("boeing",), bare="context"),
    Entry("CAT", "Caterpillar Inc.", IND, ("caterpillar inc",), ("caterpillar",), bare="context"),
    Entry("GE", "GE Aerospace", IND, ("ge aerospace", "general electric"), bare="context"),
    Entry("LMT", "Lockheed Martin", IND, ("lockheed martin", "lockheed")),
    # More of the names people actually talk about: large, heavily traded, with listed options.
    # Symbols that are also words ("NOW", "NET", "ARM", "SNOW") or mean something else in market
    # talk ("RTX" is also a graphics card) are only taken from a cashtag or with market talk.
    Entry("QCOM", "Qualcomm Inc.", T, ("qualcomm",)),
    Entry("ADBE", "Adobe Inc.", T, ("adobe inc",), ("adobe",)),
    Entry("CSCO", "Cisco Systems", T, ("cisco systems",), ("cisco",)),
    Entry("IBM", "International Business Machines", T, ("international business machines",)),
    Entry("TXN", "Texas Instruments", T, ("texas instruments",)),
    Entry("AMAT", "Applied Materials", T, ("applied materials",)),
    Entry("DELL", "Dell Technologies", T, ("dell technologies",), ("dell",), bare="context"),
    Entry("MRVL", "Marvell Technology", T, ("marvell technology",), ("marvell",)),
    Entry("ARM", "Arm Holdings", T, ("arm holdings",), bare="no", country="GB"),
    Entry("UBER", "Uber Technologies", T, ("uber technologies",), ("uber",), bare="context"),
    Entry("SHOP", "Shopify Inc.", T, ("shopify",), bare="no", country="CA"),
    Entry("CRWD", "CrowdStrike Holdings", T, ("crowdstrike",)),
    Entry("PANW", "Palo Alto Networks", T, ("palo alto networks",)),
    Entry("SNOW", "Snowflake Inc.", T, ("snowflake inc",), ("snowflake",), bare="no"),
    Entry("NET", "Cloudflare Inc.", T, ("cloudflare",), bare="no"),
    Entry("APP", "AppLovin Corporation", T, ("applovin",), bare="no"),
    Entry("PYPL", "PayPal Holdings", F, ("paypal",)),
    Entry("HOOD", "Robinhood Markets", F, ("robinhood markets",), ("robinhood",), bare="context"),
    Entry("SOFI", "SoFi Technologies", F, ("sofi technologies",), ("sofi",)),
    Entry("AXP", "American Express", F, ("american express", "amex")),
    Entry("SCHW", "Charles Schwab", F, ("charles schwab",), ("schwab",)),
    Entry("BX", "Blackstone Inc.", F, ("blackstone",)),
    Entry("RBLX", "Roblox Corporation", C, ("roblox",)),
    Entry("RDDT", "Reddit Inc.", C, ("reddit inc",)),
    Entry("T", "AT&T Inc.", C, ("at&t",), bare="no"),
    Entry("VZ", "Verizon Communications", C, ("verizon",)),
    Entry("CMCSA", "Comcast Corporation", C, ("comcast",)),
    Entry("BABA", "Alibaba Group", CD, ("alibaba",), country="CN"),
    Entry("TGT", "Target Corporation", CD, ("target corp", "target corporation")),
    Entry("LULU", "Lululemon Athletica", CD, ("lululemon",)),
    Entry("CMG", "Chipotle Mexican Grill", CD, ("chipotle",)),
    Entry("ABNB", "Airbnb Inc.", CD, ("airbnb",)),
    Entry("DKNG", "DraftKings Inc.", CD, ("draftkings",)),
    Entry("CVNA", "Carvana Co.", CD, ("carvana",)),
    Entry("RIVN", "Rivian Automotive", CD, ("rivian",)),
    Entry("NIO", "NIO Inc.", CD, ("nio inc",), bare="context", country="CN"),
    Entry("ABBV", "AbbVie Inc.", H, ("abbvie",)),
    Entry("MRK", "Merck & Co.", H, ("merck",)),
    Entry("CVS", "CVS Health", H, ("cvs health",)),
    Entry("HIMS", "Hims & Hers Health", H, ("hims & hers", "hims and hers"), bare="context"),
    Entry("OXY", "Occidental Petroleum", E, ("occidental petroleum",)),
    Entry("COP", "ConocoPhillips", E, ("conocophillips",), bare="no"),
    Entry("FCX", "Freeport-McMoRan", M, ("freeport-mcmoran", "freeport mcmoran")),
    Entry("DE", "Deere & Company", IND, ("john deere", "deere & company"), bare="no"),
    Entry("RTX", "RTX Corporation", IND, ("raytheon",), bare="no"),
    Entry("UPS", "United Parcel Service", IND, ("united parcel service",), bare="no"),
    Entry("DAL", "Delta Air Lines", IND, ("delta air lines", "delta airlines")),
    Entry("UAL", "United Airlines Holdings", IND, ("united airlines",)),
    # Funds standing in for broad markets and assets
    Entry("SLV", "iShares Silver Trust", "Commodities", ("silver prices", "price of silver"), bare="context", asset_class="Fund"),
    Entry("XLE", "Energy Select Sector SPDR", "Energy", asset_class="Fund"),
    Entry("XLF", "Financial Select Sector SPDR", "Financials", asset_class="Fund"),
    Entry("SMH", "VanEck Semiconductor ETF", "Technology", ("semiconductor etf",), asset_class="Fund"),
    Entry("ARKK", "ARK Innovation ETF", "Technology", ("ark innovation",), asset_class="Fund"),
    Entry("SPY", "SPDR S&P 500 ETF", "Broad Market", ("s&p 500", "s&p500", "sp500", "the s&p"), asset_class="Fund"),
    Entry("QQQ", "Invesco QQQ (Nasdaq-100)", "Broad Market", ("nasdaq 100", "nasdaq-100"), asset_class="Fund"),
    Entry("IWM", "iShares Russell 2000 ETF", "Broad Market", ("russell 2000",), asset_class="Fund"),
    Entry("DIA", "SPDR Dow Jones Industrial Average ETF", "Broad Market", ("dow jones",), bare="context", asset_class="Fund"),
    Entry("TLT", "iShares 20+ Year Treasury Bond ETF", "Government", ("long bonds", "treasury bonds"), asset_class="Fund"),
    Entry("GLD", "SPDR Gold Shares", "Commodities", ("gold prices", "price of gold"), bare="context", asset_class="Fund"),
    Entry("IBIT", "iShares Bitcoin Trust", "Crypto", ("ibit",), asset_class="Fund"),
    # Crypto: spot coins, priced in dollars, trading around the clock. Symbols that are also
    # words or other things' initials (SOL, ADA, DOGE the government office) need market talk.
    Entry("BTC", "Bitcoin", "Crypto", ("bitcoin", "btc"), asset_class="Crypto", country="Global"),
    Entry("ETH", "Ethereum", "Crypto", ("ethereum",), ("ether",), asset_class="Crypto", country="Global"),
    Entry("SOL", "Solana", "Crypto", ("solana",), bare="context", asset_class="Crypto", country="Global"),
    Entry("XRP", "XRP (Ripple)", "Crypto", ("xrp",), ("ripple",), asset_class="Crypto", country="Global"),
    Entry("DOGE", "Dogecoin", "Crypto", ("dogecoin",), bare="context", asset_class="Crypto", country="Global"),
    Entry("ADA", "Cardano", "Crypto", ("cardano",), bare="context", asset_class="Crypto", country="Global"),
    Entry("AVAX", "Avalanche", "Crypto", ("avax",), asset_class="Crypto", country="Global"),
    Entry("LINK", "Chainlink", "Crypto", ("chainlink",), bare="no", asset_class="Crypto", country="Global"),
    Entry("LTC", "Litecoin", "Crypto", ("litecoin",), asset_class="Crypto", country="Global"),
    Entry("DOT", "Polkadot", "Crypto", ("polkadot",), bare="no", asset_class="Crypto", country="Global"),
    Entry("UNI", "Uniswap", "Crypto", ("uniswap",), bare="no", asset_class="Crypto", country="Global"),
    Entry("SHIB", "Shiba Inu", "Crypto", ("shiba inu",), asset_class="Crypto", country="Global"),
]

BY_TICKER: dict[str, Entry] = {e.ticker: e for e in UNIVERSE}
CRYPTO_TICKERS: frozenset[str] = frozenset(e.ticker for e in UNIVERSE if e.asset_class == "Crypto")


def lot_size(asset_class: str) -> float:
    """Smallest quantity step worth trading: whole shares and contracts, millionths of a coin."""
    return 1e-6 if asset_class == "Crypto" else 1.0


def crypto_base(symbol: str) -> str | None:
    """The coin a platform symbol stands for, or None: "BTC.X", "BTC/USD" and "BTCUSD" -> "BTC".
    A bare "BTC" is deliberately not accepted here: on stock platforms that is a fund's ticker."""
    s = symbol.upper()
    for suffix in (".X", "/USD", "USD"):
        if s.endswith(suffix) and s[: -len(suffix)] in CRYPTO_TICKERS:
            return s[: -len(suffix)]
    return None


def seed_universe(session: Session) -> dict:
    """Insert any universe securities that are missing. Existing rows are left untouched."""
    have = set(session.execute(select(Security.ticker)).scalars())
    added = []
    for e in UNIVERSE:
        if e.ticker in have:
            continue
        session.add(
            Security(ticker=e.ticker, name=e.name, asset_class=e.asset_class, currency="USD", sector=e.sector,
                     country=e.country, issuer=e.name, multiplier=1.0)
        )
        added.append(e.ticker)
    session.commit()
    return {"added": len(added), "already_present": len(UNIVERSE) - len(added), "universe": len(UNIVERSE)}


def recognition_maps(tickers: set[str]) -> tuple[dict[str, str], dict[str, str], set[str], set[str]]:
    """(aliases, context_aliases, bare_tickers, context_bare) for the curated tickers given."""
    aliases: dict[str, str] = {}
    context: dict[str, str] = {}
    bare: set[str] = set()
    context_bare: set[str] = set()
    for t in tickers:
        e = BY_TICKER.get(t)
        if e is None:
            continue
        for a in e.aliases:
            aliases[a] = t
        for a in e.context:
            context[a] = t
        mode = e.bare if len(t) >= 3 or e.bare != "yes" else "context"  # 1-2 letter symbols never match bare
        if mode == "yes":
            bare.add(t)
        elif mode == "context":
            context_bare.add(t)
    return aliases, context, bare, context_bare


def firehose_keywords(tickers: set[str]) -> list[str]:
    """Unambiguous names worth pre-filtering a firehose on (context-only names would flood it)."""
    return sorted({a for t in tickers if (e := BY_TICKER.get(t)) for a in e.aliases})
