"""Rule library. Each rule turns (spec, valued positions) into zero or more breaches.

Add a rule by decorating a function with @rule("type_name"). `params` is free-form JSON stored
on the ComplianceRule row; document the expected keys in the docstring.

Most rules only need the holdings. A few (the settlement rules) need the history behind them
and the trades being tested; those are registered with `context=True` and receive a `Context`.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import asdict, dataclass

from sqlalchemy.orm import Session

from spectre.models import ComplianceRule, Severity
from spectre.portfolio.exposures import exposure_by
from spectre.portfolio.positions import ValuedPositions

EPS = 1e-9


@dataclass(frozen=True)
class RuleSpec:
    id: int | None
    name: str
    rule_type: str
    params: dict
    severity: Severity
    portfolio_id: int | None = None

    @classmethod
    def from_orm(cls, r: ComplianceRule) -> RuleSpec:
        return cls(r.id, r.name, r.rule_type, dict(r.params or {}), Severity(r.severity), r.portfolio_id)


@dataclass
class Breach:
    rule_id: int | None
    rule_name: str
    rule_type: str
    severity: Severity
    scope: str  # what breached: a ticker, a sector bucket, "portfolio", ...
    observed: float | None
    limit: float | None
    excess: float  # how far past the limit; larger = worse. Used to detect "made worse".
    message: str

    @property
    def key(self) -> tuple:
        return (self.rule_id, self.rule_name, self.scope)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["severity"] = self.severity.value
        return d


@dataclass(frozen=True)
class Context:
    """What a history-aware rule may look at: the ledger, and the trades being tested (none
    when the question is about the portfolio as it stands)."""

    session: Session
    portfolio_id: int
    trades: tuple = ()


RuleFn = Callable[..., list[Breach]]
REGISTRY: dict[str, RuleFn] = {}
NEEDS_CONTEXT: set[str] = set()


def rule(name: str, context: bool = False) -> Callable[[RuleFn], RuleFn]:
    def deco(fn: RuleFn) -> RuleFn:
        REGISTRY[name] = fn
        if context:
            NEEDS_CONTEXT.add(name)
        return fn

    return deco


def _breach(spec: RuleSpec, scope: str, observed: float, limit: float, excess: float, msg: str) -> Breach:
    return Breach(spec.id, spec.name, spec.rule_type, spec.severity, scope, observed, limit, excess, msg)


@rule("max_position_weight")
def max_position_weight(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """params: limit (fraction), exclude_asset_classes (list, optional)."""
    limit = float(spec.params["limit"])
    exclude = set(spec.params.get("exclude_asset_classes", []))
    df = v.positions
    over = df[(df["weight"] > limit + EPS) & ~df["asset_class"].isin(exclude)]
    return [
        _breach(
            spec, row.ticker, float(row.weight), limit, float(row.weight) - limit,
            f"{row.ticker} is {row.weight:.2%} of the portfolio; limit {limit:.2%}",
        )
        for row in over.itertuples()
    ]


@rule("max_group_weight")
def max_group_weight(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """params: dimension, limit, bucket (optional: one bucket; else every bucket), include_cash (default false)."""
    dim = spec.params["dimension"]
    limit = float(spec.params["limit"])
    bucket = spec.params.get("bucket")
    exp = exposure_by(v, dim, include_cash=bool(spec.params.get("include_cash", False)))
    if bucket is not None:
        exp = exp[exp.index == bucket]
    over = exp[exp["weight"] > limit + EPS]
    return [
        _breach(
            spec, str(b), float(w), limit, float(w) - limit,
            f"{dim} '{b}' is {w:.2%} of the portfolio; limit {limit:.2%}",
        )
        for b, w in over["weight"].items()
    ]


@rule("min_group_weight")
def min_group_weight(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """params: dimension, bucket, limit (minimum fraction)."""
    dim = spec.params["dimension"]
    bucket = spec.params["bucket"]
    limit = float(spec.params["limit"])
    exp = exposure_by(v, dim, include_cash=True)
    w = float(exp["weight"].get(bucket, 0.0))
    if w < limit - EPS:
        return [
            _breach(
                spec, str(bucket), w, limit, limit - w,
                f"{dim} '{bucket}' is {w:.2%} of the portfolio; minimum {limit:.2%}",
            )
        ]
    return []


@rule("restricted_list")
def restricted_list(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """params: tickers (list). Any holding of a restricted name is a breach."""
    banned = set(spec.params.get("tickers", []))
    df = v.positions
    held = df[df["ticker"].isin(banned) & (df["quantity"].abs() > EPS)]
    return [
        _breach(
            spec, row.ticker, float(row.weight), 0.0, abs(float(row.weight)),
            f"{row.ticker} is on the restricted list",
        )
        for row in held.itertuples()
    ]


@rule("min_cash_weight")
def min_cash_weight(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """params: limit (minimum cash fraction)."""
    limit = float(spec.params["limit"])
    w = v.cash_weight
    if w < limit - EPS:
        return [_breach(spec, "cash", w, limit, limit - w, f"Cash is {w:.2%}; minimum {limit:.2%}")]
    return []


@rule("max_cash_weight")
def max_cash_weight(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """params: limit (maximum cash fraction)."""
    limit = float(spec.params["limit"])
    w = v.cash_weight
    if w > limit + EPS:
        return [_breach(spec, "cash", w, limit, w - limit, f"Cash is {w:.2%}; maximum {limit:.2%}")]
    return []


@rule("max_issuer_weight")
def max_issuer_weight(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """params: limit, exclude_sectors (list, optional; e.g. ["Government"] to exempt sovereigns).

    Aggregates every security of the same issuer (equity + its bonds).
    """
    limit = float(spec.params["limit"])
    exclude = set(spec.params.get("exclude_sectors", []))
    df = v.positions
    df = df[~df["sector"].isin(exclude)]
    if len(df) == 0:
        return []
    by_issuer = df.groupby("issuer")["weight"].sum()
    over = by_issuer[by_issuer > limit + EPS]
    return [
        _breach(
            spec, str(i), float(w), limit, float(w) - limit,
            f"Issuer '{i}' is {w:.2%} across all instruments; limit {limit:.2%}",
        )
        for i, w in over.items()
    ]


@rule("no_short_positions")
def no_short_positions(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """No params. Any negative quantity is a breach."""
    df = v.positions
    shorts = df[df["quantity"] < -EPS]
    return [
        _breach(spec, row.ticker, float(row.quantity), 0.0, abs(float(row.quantity)),
                f"{row.ticker} is short {abs(row.quantity):,.0f} units")
        for row in shorts.itertuples()
    ]


@rule("no_negative_cash")
def no_negative_cash(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """No params. Cash below zero (overdraft) is a breach."""
    if v.cash < -1e-6:
        return [_breach(spec, "cash", v.cash, 0.0, -v.cash,
                        f"Cash balance is {v.cash:,.2f} {v.base_currency}")]
    return []


@rule("no_naked_options")
def no_naked_options(spec: RuleSpec, v: ValuedPositions) -> list[Breach]:
    """No params. Every sold option must be covered: a sold call by 100 shares of the underlying
    per contract, a sold put by cash equal to strike x 100 per contract. Bought options always pass."""
    from spectre.execution.alpaca import parse_occ

    df = v.positions
    shorts = df[(df["asset_class"] == "Option") & (df["quantity"] < -EPS)]
    if shorts.empty:
        return []
    shares = df[df["asset_class"] != "Option"].set_index("ticker")["quantity"].to_dict()
    need_shares: dict[str, float] = {}
    need_cash = 0.0
    out: list[Breach] = []
    for row in shorts.itertuples():
        parsed = parse_occ(row.ticker)
        contracts = -float(row.quantity)
        if parsed is None:
            out.append(_breach(spec, row.ticker, contracts, 0.0, contracts,
                               f"cannot verify cover for sold option {row.ticker}"))
            continue
        root, _, kind, strike = parsed
        if kind == "call":
            need_shares[root] = need_shares.get(root, 0.0) + contracts * float(row.multiplier)
        else:
            need_cash += contracts * float(row.multiplier) * strike
    for root, need in need_shares.items():
        have = max(float(shares.get(root, 0.0)), 0.0)
        if have + EPS < need:
            out.append(_breach(spec, root, have, need, need - have,
                               f"sold calls on {root} need {need:,.0f} shares as cover; holding {have:,.0f}"))
    if need_cash > v.cash + 1e-6:
        out.append(_breach(spec, "cash", v.cash, need_cash, need_cash - v.cash,
                           f"sold puts need {need_cash:,.0f} in cash as cover; cash is {v.cash:,.0f}"))
    return out


@rule("no_good_faith_violations", context=True)
def no_good_faith_violations(spec: RuleSpec, v: ValuedPositions, ctx: Context) -> list[Breach]:
    """No params. For an account that cannot borrow: something bought with the proceeds of a sale
    may not itself be sold until that sale has settled. Blocks the sale that would break this."""
    from spectre.portfolio.settlement import simulate

    if not ctx.trades:
        return []
    state = simulate(ctx.session, ctx.portfolio_id, v.as_of, proposed=list(ctx.trades))
    return [
        _breach(spec, x.ticker, x.quantity, 0.0, x.quantity,
                f"{x.ticker} was bought on {x.bought_on} with money from a sale that settles on {x.funds_settle_on}; "
                f"selling it before then is a good-faith violation")
        for x in state.violations if x.proposed
    ]


@rule("settled_funds_only", context=True)
def settled_funds_only(spec: RuleSpec, v: ValuedPositions, ctx: Context) -> list[Breach]:
    """No params. Stricter than `no_good_faith_violations`: purchases may use only money that has
    settled, so nothing is ever bought with the proceeds of a sale still in flight."""
    from spectre.portfolio.settlement import simulate

    state = simulate(ctx.session, ctx.portfolio_id, v.as_of, proposed=list(ctx.trades))
    if state.funds_available >= -0.005:
        return []
    return [_breach(spec, "cash", state.funds_available, 0.0, -state.funds_available,
                    f"purchases exceed settled money by {-state.funds_available:,.2f} "
                    f"({state.receivable:,.2f} of sale proceeds has yet to settle)")]


def rule_types() -> dict[str, str]:
    return {name: (fn.__doc__ or "").strip() for name, fn in REGISTRY.items()}
