"""V2 metrics (design 10.2 metrics 3 to 6): calibration, threshold sweep, staleness, positional error.
Ground truth is the spotter's decisive tap (confirmed = the hazard is there). Predicted p is the reference belief
(contracts/ref/belief.py) read just BEFORE that tap, from the prior plus every earlier non-spotter-tap line."""
from __future__ import annotations

import math
import sys
from collections import defaultdict
from pathlib import Path

_REF = Path(__file__).resolve().parents[2] / "contracts" / "ref"
if str(_REF) not in sys.path:
    sys.path.insert(0, str(_REF))
import belief as B  # noqa: E402

from .stats import MIN_N, percentile, r6, rate_cell, wilson

MIN_CALIBRATION = 30      # design 10.2 metric 3: below this, calibration cannot be assessed
MIN_SWEEP = 10            # per type, ground-truth passes needed before a minimizer is reported
TAUS = [round(0.05 + i * 0.01, 2) for i in range(91)]   # 0.05 .. 0.95 step 0.01


def build_items(evidence: list[dict], priors: dict[str, dict]) -> list[dict]:
    """One item per decisive spotter line: {label_id, type, ts, p, truth}. Evidence must be in time order
    (the loader sorts it). Lines whose label is not in the priors are skipped (no prior, no p)."""
    beliefs: dict[str, B.Belief] = {}
    items = []
    for ev in evidence:
        lab = priors.get(ev["label_id"])
        if lab is None:
            continue
        bel = beliefs.setdefault(ev["label_id"], B.Belief(lab["type"], lab.get("n_agree", 0), lab.get("n_disagree", 0)))
        now = B.parse_ts(ev["ts"])
        if ev["sensor"] == "spotter" and ev["outcome"] in ("confirmed", "contradicted"):
            items.append({"label_id": ev["label_id"], "type": lab["type"], "ts": ev["ts"],
                          "p": bel.read(now)["p"], "truth": ev["outcome"] == "confirmed"})
        bel.update(now, ev["outcome"], ev["sensor"])
    return items


# ---- metric 3: calibration ----
def calibration(items: list[dict], bins: int = 10) -> dict:
    n = len(items)
    edges = [i / bins for i in range(bins + 1)]
    rows = []
    for k in range(bins):
        sel = [x for x in items if edges[k] <= x["p"] < edges[k + 1] or (k == bins - 1 and x["p"] == 1.0)]
        t = sum(x["truth"] for x in sel)
        rows.append({"lo": edges[k], "hi": edges[k + 1], "n": len(sel), "truth": t,
                     "mean_p": r6(sum(x["p"] for x in sel) / len(sel)) if sel else None,
                     "observed": r6(t / len(sel)) if sel else None})
    out = {"n": n, "bins": rows, "assessable": n >= MIN_CALIBRATION}
    if n < MIN_CALIBRATION:
        out.update(note=f"calibration cannot be assessed with fewer than {MIN_CALIBRATION} ground-truth passes; raw counts only",
                   brier=None, brier_baseline=None)
        return out
    prev = sum(x["truth"] for x in items) / n
    out.update(note=None, brier=r6(sum((x["p"] - x["truth"]) ** 2 for x in items) / n),
               brier_baseline=r6(prev * (1 - prev)))   # Brier of always predicting the observed prevalence
    return out


# ---- metric 4: threshold sweep ----
def sweep_curve(items: list[dict], c_miss: float, c_fa: float) -> list[dict]:
    """For each tau: alert when p >= tau. tp, fp, fn, tn and cost = c_miss * fn + c_fa * fp."""
    out = []
    for t in TAUS:
        tp = sum(1 for x in items if x["p"] >= t and x["truth"])
        fp = sum(1 for x in items if x["p"] >= t and not x["truth"])
        fn = sum(1 for x in items if x["p"] < t and x["truth"])
        tn = len(items) - tp - fp - fn
        out.append({"tau": t, "alerts": tp + fp, "tp": tp, "fp": fp, "fn": fn, "tn": tn, "cost": c_miss * fn + c_fa * fp})
    return out


def minimizer(curve: list[dict]) -> float:
    """Smallest tau with the lowest cost (ties go to the smaller tau: warn more, the safer direction)."""
    best = min(c["cost"] for c in curve)
    return next(c["tau"] for c in curve if c["cost"] == best)


def cost_at(curve: list[dict], tau: float) -> float:
    return min(curve, key=lambda c: abs(c["tau"] - tau))["cost"]


def threshold_sweep(items: list[dict], hold_items: list[dict] | None = None) -> dict:
    """Per hazard type with a threshold. If hold_items is given, the minimizer is found on `items` (tune) and the
    cost at the default and at the tuned tau is reported on `hold_items` (design 10.3)."""
    by_t: dict[str, list] = defaultdict(list)
    for x in items:
        by_t[x["type"]].append(x)
    hold_by_t: dict[str, list] = defaultdict(list)
    for x in hold_items or []:
        hold_by_t[x["type"]].append(x)
    out = {}
    for typ, (c_miss, c_fa) in sorted(B.COSTS.items()):
        default = B.tau_for(typ)
        xs = by_t.get(typ, [])
        row = {"n": len(xs), "default_tau": r6(default), "c_miss": c_miss, "c_fa": c_fa}
        if len(xs) < MIN_SWEEP:
            row["note"] = f"insufficient data (fewer than {MIN_SWEEP} ground-truth passes)"
            out[typ] = row
            continue
        curve = sweep_curve(xs, c_miss, c_fa)
        row.update(note=None, minimizer_tau=minimizer(curve), cost_at_default=r6(cost_at(curve, default)),
                   cost_at_minimizer=r6(min(c["cost"] for c in curve)),
                   sensitivity={"half_c_miss": minimizer(sweep_curve(xs, c_miss / 2, c_fa)),
                                "double_c_miss": minimizer(sweep_curve(xs, c_miss * 2, c_fa))})
        ys = hold_by_t.get(typ)
        if hold_items is not None:
            if ys and len(ys) >= 1:
                hc = sweep_curve(ys, c_miss, c_fa)
                row["held_out"] = {"n": len(ys), "cost_at_default": r6(cost_at(hc, default)),
                                   "cost_at_tuned_tau": r6(cost_at(hc, row["minimizer_tau"]))}
            else:
                row["held_out"] = {"n": 0, "note": "no hold-out passes for this type"}
        out[typ] = row
    return out


# ---- metric 5: staleness ----
AGE_BUCKETS = [("0-3y", 0, 3), ("4-6y", 4, 6), ("7-9y", 7, 9), ("10y+", 10, 1000)]


def _age_years(ts: str, imagery: str) -> float:
    y, m = int(ts[:4]), int(ts[5:7])
    iy, im = int(imagery[:4]), int(imagery[5:7])
    return (y - iy) + (m - im) / 12.0


def staleness(evidence: list[dict], priors: dict[str, dict]) -> dict:
    """Confirm rate of decisive spotter taps by age of the label's street imagery at the time of the tap."""
    counts = {b[0]: [0, 0] for b in AGE_BUCKETS}   # name -> [confirmed, decisive]
    skipped = 0
    for ev in evidence:
        if ev["sensor"] != "spotter" or ev["outcome"] not in ("confirmed", "contradicted"):
            continue
        lab = priors.get(ev["label_id"])
        if not lab or not lab.get("imagery_date"):
            skipped += 1
            continue
        age = math.floor(_age_years(ev["ts"], lab["imagery_date"]))
        for name, lo, hi in AGE_BUCKETS:
            if lo <= max(age, 0) <= hi:
                counts[name][1] += 1
                counts[name][0] += ev["outcome"] == "confirmed"
                break
    cells = {name: rate_cell(k, n) for name, (k, n) in counts.items()}
    usable = [(name, c) for name, c in cells.items() if c["rate"] is not None]
    if len(usable) < 2:
        trend = "insufficient data (needs two age groups with at least 5 taps each)"
    else:
        (_, young), (_, old) = usable[0], usable[-1]
        if old["hi"] < young["lo"]:
            trend = "older imagery is confirmed less often (intervals do not overlap)"
        elif old["lo"] > young["hi"]:
            trend = "older imagery is confirmed more often (intervals do not overlap)"
        else:
            trend = "no clear trend (intervals overlap)"
    return {"by_age": cells, "taps_without_imagery_date": skipped, "trend": trend}


# ---- metric 6: positional error ----
def positional_error(evidence: list[dict]) -> dict:
    """Along-track offset (m) of confirming sensor events relative to the label point, by sensor.
    Suggests label_error (the 90th percentile of |offset|) only with at least 20 events."""
    by_s: dict[str, list[float]] = defaultdict(list)
    for ev in evidence:
        if ev["outcome"] == "confirmed" and ev.get("along_m") is not None:
            by_s[ev["sensor"]].append(float(ev["along_m"]))
    out = {}
    for s in sorted(by_s):
        v = by_s[s]
        row = {"n": len(v), "median": r6(percentile(v, 0.5)), "mean": r6(sum(v) / len(v)),
               "p90_abs": r6(percentile([abs(x) for x in v], 0.9)), "suggested_label_error_m": None}
        if len(v) >= 20:
            row["suggested_label_error_m"] = row["p90_abs"]
        else:
            row["note"] = "needs at least 20 confirming events to suggest label_error"
        out[s] = row
    return out
