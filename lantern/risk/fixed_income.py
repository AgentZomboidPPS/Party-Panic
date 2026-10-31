"""Plain-vanilla fixed-coupon bond analytics. Prices are per 100 face unless stated otherwise."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date

import numpy as np
from scipy.optimize import brentq

from lantern.models import Security


def years_between(start: date, end: date) -> float:
    return (end - start).days / 365.25


def cashflow_schedule(face: float, coupon_rate: float, years: float, freq: int) -> tuple[np.ndarray, np.ndarray]:
    """Payment times (in years) and amounts for a bond with `years` to maturity.

    The final coupon is at maturity; earlier coupons step back every 1/freq years.
    """
    if years <= 0:
        return np.array([0.0]), np.array([face])
    n = int(np.ceil(years * freq - 1e-9))
    times = years - np.arange(n)[::-1] / freq  # ..., years - 2/f, years - 1/f, years
    times = times[times > 1e-9]
    coupon = face * coupon_rate / freq
    cfs = np.full(times.shape, coupon)
    cfs[-1] += face
    return times, cfs


def _discount(times: np.ndarray, ytm: float, freq: int) -> np.ndarray:
    return (1.0 + ytm / freq) ** (-times * freq)


def bond_price(face: float, coupon_rate: float, ytm: float, years: float, freq: int = 2) -> float:
    t, cf = cashflow_schedule(face, coupon_rate, years, freq)
    return float(np.sum(cf * _discount(t, ytm, freq)))


def bond_ytm(price: float, face: float, coupon_rate: float, years: float, freq: int = 2) -> float:
    f = lambda y: bond_price(face, coupon_rate, y, years, freq) - price  # noqa: E731
    return float(brentq(f, -0.99, 5.0, maxiter=200))


def macaulay_duration(face: float, coupon_rate: float, ytm: float, years: float, freq: int = 2) -> float:
    t, cf = cashflow_schedule(face, coupon_rate, years, freq)
    pv = cf * _discount(t, ytm, freq)
    return float(np.sum(t * pv) / np.sum(pv))


def modified_duration(face: float, coupon_rate: float, ytm: float, years: float, freq: int = 2) -> float:
    return macaulay_duration(face, coupon_rate, ytm, years, freq) / (1.0 + ytm / freq)


def convexity(face: float, coupon_rate: float, ytm: float, years: float, freq: int = 2) -> float:
    t, cf = cashflow_schedule(face, coupon_rate, years, freq)
    pv = cf * _discount(t, ytm, freq)
    n = t * freq
    return float(np.sum(pv * n * (n + 1)) / (np.sum(pv) * freq**2 * (1.0 + ytm / freq) ** 2))


@dataclass
class BondAnalytics:
    ticker: str
    price: float
    years_to_maturity: float
    ytm: float
    macaulay_duration: float
    modified_duration: float
    convexity: float
    dv01_per_100: float  # price change for 1bp, per 100 face

    def to_dict(self) -> dict:
        return asdict(self)


def bond_analytics(security: Security, price: float, as_of: date) -> BondAnalytics | None:
    """Analytics for a fixed-income security, or None when terms are missing."""
    if not security.is_fixed_income() or security.maturity_date is None or security.coupon_rate is None:
        return None
    years = years_between(as_of, security.maturity_date)
    if years <= 0:
        return None
    face = security.face_value or 100.0
    freq = security.coupon_frequency or 2
    # Prices are stored per 100 face; scale to the bond's face for the yield solve.
    px = price * face / 100.0
    y = bond_ytm(px, face, security.coupon_rate, years, freq)
    mod = modified_duration(face, security.coupon_rate, y, years, freq)
    return BondAnalytics(
        ticker=security.ticker,
        price=price,
        years_to_maturity=years,
        ytm=y,
        macaulay_duration=macaulay_duration(face, security.coupon_rate, y, years, freq),
        modified_duration=mod,
        convexity=convexity(face, security.coupon_rate, y, years, freq),
        dv01_per_100=mod * price * 1e-4,
    )
