"""Small, dependency-free statistics used by the harness. Every function is pure and deterministic."""
from __future__ import annotations

import math
import random
from typing import Sequence

Z95 = 1.959963984540054
MIN_N = 5  # a rate with fewer observations than this is never printed (design 10.2 metric 1)


def r6(x: float | None) -> float | None:
    """Round for stable JSON bytes."""
    return None if x is None else round(float(x), 6)


def wilson(k: int, n: int, z: float = Z95) -> tuple[float, float] | None:
    """Wilson score interval for k successes in n trials; None when n == 0."""
    if n <= 0:
        return None
    if not 0 <= k <= n:
        raise ValueError("k must be between 0 and n")
    p = k / n
    d = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    lo = 0.0 if k == 0 else max(0.0, centre - half)  # the interval touches the bound exactly when k is 0 or n
    hi = 1.0 if k == n else min(1.0, centre + half)
    return lo, hi


def rate_cell(k: int, n: int) -> dict:
    """{k, n, rate, lo, hi} or an explicit 'insufficient data' marker when n < MIN_N."""
    if n < MIN_N:
        return {"k": k, "n": n, "rate": None, "lo": None, "hi": None, "note": "insufficient data"}
    lo, hi = wilson(k, n)
    return {"k": k, "n": n, "rate": r6(k / n), "lo": r6(lo), "hi": r6(hi), "note": None}


def cohen_kappa(a: int, b: int, c: int, d: int) -> float | None:
    """Cohen's kappa for a 2x2 table [[a, b], [c, d]] (rows: reference rater, columns: other rater).
    None when undefined (empty table, or expected agreement is exactly 1)."""
    n = a + b + c + d
    if n == 0:
        return None
    po = (a + d) / n
    pe = ((a + b) * (a + c) + (c + d) * (b + d)) / (n * n)
    if math.isclose(pe, 1.0):
        return None
    return (po - pe) / (1 - pe)


def percentile(values: Sequence[float], q: float) -> float | None:
    """Nearest-rank percentile (q in 0..1); None for an empty sequence."""
    if not values:
        return None
    s = sorted(values)
    return s[max(0, math.ceil(q * len(s)) - 1)]


def holdout_split(ids: Sequence[str], fraction: float = 0.3, seed: int = 26) -> tuple[list[str], list[str]]:
    """Deterministic split by label (design 10.3): returns (tune, hold_out), each sorted.
    The same ids and seed always give the same split, whatever order the ids arrive in."""
    uniq = sorted(set(ids))
    rng = random.Random(seed)
    k = round(len(uniq) * fraction)
    hold = set(rng.sample(uniq, k)) if k else set()
    return [i for i in uniq if i not in hold], [i for i in uniq if i in hold]
