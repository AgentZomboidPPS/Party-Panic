import pytest

from lantern.compliance.engine import post_trade_check, pre_trade_check
from lantern.models import ComplianceRule, Severity, Side
from lantern.portfolio.whatif import ProposedTrade
from tests.conftest import D1


def _rule(session, rule_type, params, severity=Severity.HARD, portfolio_id=None, name=None):
    r = ComplianceRule(portfolio_id=portfolio_id, name=name or rule_type, rule_type=rule_type,
                       params=params, severity=severity.value)
    session.add(r)
    session.commit()
    return r


def test_post_trade_reports_breaches(mini):
    s, pf = mini["session"], mini["pf"]
    _rule(s, "max_position_weight", {"limit": 0.10}, portfolio_id=pf.id)  # AAA 10.76%, BND 19.4%, EEE 11.7%
    _rule(s, "min_cash_weight", {"limit": 0.80}, Severity.SOFT, portfolio_id=pf.id)  # cash 58%
    res = post_trade_check(s, pf.id, D1, record=False)
    assert not res.passed
    scopes = {b.scope for b in res.breaches}
    assert scopes == {"AAA", "EEE", "BND", "cash"}
    assert len(res.warnings) == 1 and res.warnings[0].scope == "cash"


def test_pre_trade_blocks_new_hard_breach_but_allows_small_trade(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    _rule(s, "max_position_weight", {"limit": 0.12, "exclude_asset_classes": ["Fixed Income"]}, portfolio_id=pf.id)
    # +500 AAA at 110 -> 165,000 / 1,022,000 = 16.1% > 12%: blocked
    res = pre_trade_check(s, pf.id, [ProposedTrade(aaa.id, Side.BUY, 500)], D1, record=False)
    assert res.blocked and not res.passed
    assert [b.scope for b in res.new_breaches] == ["AAA"]
    # +100 AAA -> 121,000 / 1,022,000 = 11.8%: fine
    res = pre_trade_check(s, pf.id, [ProposedTrade(aaa.id, Side.BUY, 100)], D1, record=False)
    assert res.passed and not res.breaches


def test_pre_existing_breach_does_not_block_unless_worsened(mini):
    s, pf, eee = mini["session"], mini["pf"], mini["eee"]
    _rule(s, "restricted_list", {"tickers": ["EEE"]})  # firm-wide; already held
    # Selling down a restricted name is allowed (not worse).
    res = pre_trade_check(s, pf.id, [ProposedTrade(eee.id, Side.SELL, 500)], D1, record=False)
    assert res.passed and not res.blocked
    assert [b.scope for b in res.pre_existing] == ["EEE"]
    # Buying more is worse: blocked.
    res = pre_trade_check(s, pf.id, [ProposedTrade(eee.id, Side.BUY, 500)], D1, record=False)
    assert res.blocked


def test_soft_breach_warns_but_passes(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    _rule(s, "max_group_weight", {"dimension": "sector", "limit": 0.12}, Severity.SOFT, portfolio_id=pf.id)
    res = pre_trade_check(s, pf.id, [ProposedTrade(aaa.id, Side.BUY, 500)], D1, record=False)
    assert res.passed and not res.blocked
    assert len(res.warnings) == 1 and res.warnings[0].scope == "Technology"


def test_issuer_rule_aggregates_equity_and_bonds(mini):
    s, pf = mini["session"], mini["pf"]
    _rule(s, "max_issuer_weight", {"limit": 0.25}, portfolio_id=pf.id)  # Alpha Inc = 308,000 / 1,022,000 = 30.1%
    res = post_trade_check(s, pf.id, D1, record=False)
    assert [b.scope for b in res.breaches] == ["Alpha Inc"]
    assert res.breaches[0].observed == pytest.approx(308_000 / 1_022_000)


def test_overdraft_and_short_rules(mini):
    s, pf, aaa = mini["session"], mini["pf"], mini["aaa"]
    _rule(s, "no_negative_cash", {})
    _rule(s, "no_short_positions", {})
    res = pre_trade_check(s, pf.id, [ProposedTrade(aaa.id, Side.SELL, 1500)], D1, record=False)
    assert res.blocked and {b.scope for b in res.new_breaches} == {"AAA"}
    res = pre_trade_check(s, pf.id, [ProposedTrade(aaa.id, Side.BUY, 10_000)], D1, record=False)  # 1.1m > cash
    assert res.blocked and {b.scope for b in res.new_breaches} == {"cash"}


def test_unknown_rule_type_is_a_hard_breach(mini):
    s, pf = mini["session"], mini["pf"]
    _rule(s, "does_not_exist", {}, portfolio_id=pf.id)
    res = post_trade_check(s, pf.id, D1, record=False)
    assert not res.passed and res.breaches[0].scope == "rule"


def test_scoped_rules_only_apply_to_their_portfolio(mini):
    from lantern.models import Portfolio

    s, pf = mini["session"], mini["pf"]
    other = Portfolio(name="Other", base_currency="USD")
    s.add(other)
    s.commit()
    _rule(s, "max_position_weight", {"limit": 0.01}, portfolio_id=other.id)
    assert post_trade_check(s, pf.id, D1, record=False).passed
