"""Reference implementation of WAYMARK_PLAN 5.3 (belief) and 5.4 (threshold).

The Swift types must agree with this to 1e-9 on contracts/golden/belief_vectors.json
and threshold_vectors.json. Spec text in the plan is normative; this file is the
executable form of it. No hidden clock, no randomness, double precision.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

HALF_LIFE_DAYS = {"obstacle": 60.0, "surface_problem": 120.0}
DEFAULT_HALF_LIFE_DAYS = 365.0

# sensor weights [H]
WEIGHTS = {
    "spotter": 2.0,
    "lidar_torso": 1.0,
    "lidar_head": 1.0,
    "ground": 0.5,
    "vision": 0.5,
}

# (C_miss, C_fa) design choices [H]. curb_ramp is informational: no entry, never alerts by threshold.
COSTS = {
    "obstacle": (5.0, 1.0),
    "missing_curb_ramp": (4.0, 1.0),
    "no_sidewalk": (4.0, 1.0),
    "surface_problem": (2.0, 1.0),
}

OUTCOMES = ("confirmed", "contradicted", "unverifiable")


def parse_ts(s: str) -> float:
    """UTC seconds since the epoch from 'YYYY-MM-DDTHH:MM:SSZ'."""
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()


def half_life_days(label_type: str) -> float:
    return HALF_LIFE_DAYS.get(label_type, DEFAULT_HALF_LIFE_DAYS)


def decay(e: float, dt_seconds: float, label_type: str) -> float:
    dt_days = max(0.0, dt_seconds) / 86400.0
    return e * 0.5 ** (dt_days / half_life_days(label_type))


@dataclass
class Belief:
    label_type: str
    n_agree: int
    n_disagree: int
    e_a: float = 0.0
    e_b: float = 0.0
    t_last: float | None = None  # UTC seconds of the last counted update

    def _decayed(self, now: float) -> tuple[float, float]:
        if self.t_last is None:
            return self.e_a, self.e_b
        dt = now - self.t_last
        return decay(self.e_a, dt, self.label_type), decay(self.e_b, dt, self.label_type)

    def read(self, now: float) -> dict:
        ea, eb = self._decayed(now)
        a = 1.0 + self.n_agree + ea
        b = 1.0 + self.n_disagree + eb
        return {
            "a": a,
            "b": b,
            "p": a / (a + b),
            "n_eff": self.n_agree + self.n_disagree + ea + eb,
        }

    def update(self, now: float, outcome: str, sensor: str) -> None:
        if outcome not in OUTCOMES:
            raise ValueError(f"unknown outcome {outcome!r}")
        if sensor not in WEIGHTS:
            raise ValueError(f"unknown sensor {sensor!r}")
        if outcome == "unverifiable":
            return  # no change at all, including t_last
        ea, eb = self._decayed(now)
        w = WEIGHTS[sensor]
        if outcome == "confirmed":
            ea += w
        else:
            eb += w
        self.e_a, self.e_b, self.t_last = ea, eb, now


def tau(c_miss: float, c_fa: float) -> float:
    """Cost-minimizing alert threshold for a calibrated probability: C_fa / (C_fa + C_miss)."""
    return c_fa / (c_fa + c_miss)


def tau_for(label_type: str) -> float | None:
    """None means the type never alerts by threshold (curb_ramp informational, crosswalk, other)."""
    costs = COSTS.get(label_type)
    if costs is None:
        return None
    return tau(costs[0], costs[1])


def should_consider_alert(label_type: str, p: float) -> bool:
    t = tau_for(label_type)
    return t is not None and p >= t
