"""V1 metrics (design 10.2): 1 outcome rates per type, 2 sensor-vs-spotter agreement, 7 load and latency."""
from __future__ import annotations

from collections import Counter, defaultdict

from .stats import MIN_N, cohen_kappa, percentile, r6, rate_cell

OUTCOMES = ("confirmed", "contradicted", "unverifiable")
SENSOR_GROUPS = {  # machine sensors compared with the spotter
    "lidar": ("lidar_torso", "lidar_head"),
    "ground": ("ground",),
    "vision": ("vision",),
}


def label_type(label_id: str, priors: dict[str, dict]) -> str:
    lab = priors.get(label_id)
    return lab["type"] if lab else "unknown"


def outcome_rates(evidence: list[dict], priors: dict[str, dict]) -> dict:
    """Metric 1. Per label type (and 'all'): counts and Wilson 95% intervals for each outcome over all lines,
    plus the confirm rate among decisive lines (confirmed + contradicted). n is reported in every cell and a
    rate with n < 5 is replaced by an explicit 'insufficient data' marker."""
    by_type: dict[str, Counter] = defaultdict(Counter)
    labels: dict[str, set] = defaultdict(set)
    for ev in evidence:
        t = label_type(ev["label_id"], priors)
        for key in (t, "all"):
            by_type[key][ev["outcome"]] += 1
            labels[key].add(ev["label_id"])
    out = {}
    for t in sorted(by_type):
        c = by_type[t]
        n = sum(c.values())
        decisive = c["confirmed"] + c["contradicted"]
        out[t] = {
            "lines": n,
            "labels_with_evidence": len(labels[t]),
            "outcomes": {o: rate_cell(c[o], n) for o in OUTCOMES},
            "confirm_rate_decisive": rate_cell(c["confirmed"], decisive),
        }
    return out


def _decide(outcomes: list[str]) -> str | None:
    """One verdict for a label from one rater group: majority of decisive outcomes; None if none or tied."""
    c = Counter(o for o in outcomes if o in ("confirmed", "contradicted"))
    if not c or c["confirmed"] == c["contradicted"]:
        return None
    return "confirmed" if c["confirmed"] > c["contradicted"] else "contradicted"


def sensor_vs_spotter(evidence: list[dict]) -> dict:
    """Metric 2. Labels that have a decisive spotter verdict and a decisive verdict from a machine sensor group.
    Rows are the spotter (reference), columns the sensor. Kappa is withheld below 5 paired labels."""
    spotter: dict[str, list[str]] = defaultdict(list)
    machine: dict[str, dict[str, list[str]]] = {g: defaultdict(list) for g in SENSOR_GROUPS}
    for ev in evidence:
        if ev["sensor"] == "spotter":
            spotter[ev["label_id"]].append(ev["outcome"])
        else:
            for g, members in SENSOR_GROUPS.items():
                if ev["sensor"] in members:
                    machine[g][ev["label_id"]].append(ev["outcome"])
    out = {}
    for g in SENSOR_GROUPS:
        a = b = c = d = tied = 0
        for lid, s_out in sorted(spotter.items()):
            if lid not in machine[g]:
                continue
            ref, got = _decide(s_out), _decide(machine[g][lid])
            if ref is None or got is None:
                tied += 1
                continue
            if ref == "confirmed":
                a, b = (a + 1, b) if got == "confirmed" else (a, b + 1)
            else:
                c, d = (c + 1, d) if got == "confirmed" else (c, d + 1)
        n = a + b + c + d
        kappa = cohen_kappa(a, b, c, d) if n >= MIN_N else None
        out[g] = {
            "paired_labels": n,
            "undecided_pairs": tied,
            "matrix": {"spotter_confirmed": {"sensor_confirmed": a, "sensor_contradicted": b},
                       "spotter_contradicted": {"sensor_confirmed": c, "sensor_contradicted": d}},
            "agreement": r6((a + d) / n) if n >= MIN_N else None,
            "kappa": r6(kappa),
            "note": None if n >= MIN_N else "insufficient data (fewer than 5 paired labels)",
        }
    return out


def _timing(values: list[float]) -> dict:
    n = len(values)
    if n == 0:
        return {"n": 0, "note": "no records carry this field"}
    s = {"n": n, "min": r6(min(values)), "median": r6(percentile(values, 0.5)), "max": r6(max(values)), "p95": None,
         "note": None}
    if n >= 20:
        s["p95"] = r6(percentile(values, 0.95))
    else:
        s["note"] = "p95 needs at least 20 records"
    return s


def load_latency(records: list[dict]) -> dict:
    """Metric 7 from exported `waymark_load` and `waymark_cue` records (design 10.2, 11). Fields, all in milliseconds:
    `load_ms` on waymark_load; `lookup_ms` and `latency_ms` (GPS fix to speech dispatch) on waymark_cue.
    A field missing from every record is reported as absent, never as zero."""
    loads = [r for r in records if r.get("kind") == "waymark_load"]
    cues = [r for r in records if r.get("kind") == "waymark_cue"]
    suppressed = Counter(str(r.get("suppressed_reason") or "spoken") for r in cues)
    return {
        "loads": len(loads),
        "cues": len(cues),
        "cue_outcomes": dict(sorted(suppressed.items())),
        "prior_load_ms": _timing([r["load_ms"] for r in loads if r.get("load_ms") is not None]),
        "lookup_ms": _timing([r["lookup_ms"] for r in cues if r.get("lookup_ms") is not None]),
        "fix_to_dispatch_ms": _timing([r["latency_ms"] for r in cues if r.get("latency_ms") is not None]),
    }


def unverifiable_reasons(records: list[dict]) -> dict:
    """Why evidence came back unverifiable, from exported `waymark_evidence` trip-log records.
    The app writes a `reason` code on those records only (not on the evidence line, whose schema is closed):
    lateral, left, reversed, gps_jump, unclean, few_frames, short_pass, between, route_end.
    Returns {} when no record carries a reason, so reports from older logs are unchanged."""
    c = Counter(str(r["reason"]) for r in records
                if r.get("kind") == "waymark_evidence" and r.get("outcome") == "unverifiable" and r.get("reason"))
    return dict(sorted(c.items()))
