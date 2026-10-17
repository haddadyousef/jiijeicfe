"""Seeded synthetic walk generator. For testing the harness only: every figure made from this data is watermarked
SYNTHETIC. Ids start at 9000000000 (the contracts' synthetic range) so they can never collide with real clusters."""
from __future__ import annotations

import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

BUILD = "waymark-synthetic-eval"
TYPES = [  # (type, count, P(label really present))
    ("obstacle", 14, 0.55), ("surface_problem", 14, 0.65), ("missing_curb_ramp", 10, 0.75),
    ("no_sidewalk", 6, 0.8), ("curb_ramp", 12, 0.9), ("crosswalk", 4, 0.9),
]
LIDAR_SENS, LIDAR_SPEC, P_UNVERIFIABLE = 0.85, 0.9, 0.15  # how good the fake lidar is, so kappa is knowable


def _dump(o) -> str:
    return json.dumps(o, sort_keys=True, separators=(",", ":"))


def generate(seed: int = 26) -> dict:
    """Return {'priors': dict, 'evidence': [dict], 'records': [dict], 'truth': {label_id: bool}}."""
    rng = random.Random(seed)
    labels, truth, evidence = [], {}, []
    base = datetime(2026, 10, 17, 21, 0, 0, tzinfo=timezone.utc)
    nxt = 9000000100
    for typ, count, p_present in TYPES:
        for _ in range(count):
            lid = f"ps:{nxt}"
            labels.append({
                "id": lid, "type": typ, "lat": round(47.65 + rng.random() * 0.01, 6),
                "lng": round(-122.31 + rng.random() * 0.01, 6),
                "severity": rng.choice([1, 2, 3, None]), "tags": [], "n_agree": rng.randint(1, 4),
                "n_disagree": rng.randint(0, 1), "n_unsure": 0, "cluster_size": 1, "street_edge_id": None,
                "intersection_id": None, "osm_way_id": None,
                "imagery_date": f"{rng.randint(2016, 2025)}-{rng.randint(1, 12):02d}", "label_date": "2025-06",
                "source_cluster_id": nxt,
            })
            truth[lid] = rng.random() < p_present
            nxt += 1

    def line(lid, sensor, outcome, i):
        ts = (base + timedelta(seconds=30 * i)).strftime("%Y-%m-%dT%H:%M:%SZ")
        lidar = sensor.startswith("lidar")
        return {
            "schema": "waymark.evidence.v1", "label_id": lid, "outcome": outcome, "sensor": sensor, "build": BUILD,
            "ts": ts, "dist_m": round(rng.random() * 2, 2) if lidar and outcome == "confirmed" else None,
            "along_m": round(rng.uniform(-2, 2), 2) if lidar else None, "gps_acc_m": round(rng.uniform(4, 15), 1),
            "speed_mps": round(rng.uniform(0.8, 1.4), 2) if lidar else None, "tilt_deg": round(rng.uniform(3, 8), 1),
            "torso_cover": True if lidar else None, "head_cover": True if lidar else None,
        }

    i = 0
    for lab in labels:
        lid, real = lab["id"], truth[lab["id"]]
        if rng.random() < 0.7:  # spotter taps are the ground truth and are never wrong in the fake world
            evidence.append(line(lid, "spotter", "confirmed" if real else "contradicted", i)); i += 1
        if rng.random() < 0.85:
            sensor = rng.choice(["lidar_torso", "lidar_head"])
            if rng.random() < P_UNVERIFIABLE:
                out = "unverifiable"
            elif real:
                out = "confirmed" if rng.random() < LIDAR_SENS else "contradicted"
            else:
                out = "contradicted" if rng.random() < LIDAR_SPEC else "confirmed"
            evidence.append(line(lid, sensor, out, i)); i += 1
        if rng.random() < 0.3:
            evidence.append(line(lid, "ground", "confirmed" if real else "contradicted", i)); i += 1

    records = [{"kind": "waymark_load", "load_ms": str(round(rng.uniform(40, 90), 1)), "count": str(len(labels)),
                "bytes": "1071866", "source": "bundle"} for _ in range(3)]
    for k in range(40):
        lab = labels[k % len(labels)]
        rec = {"kind": "waymark_cue", "label_id": lab["id"], "label_type": lab["type"], "p": "0.8", "tau": "0.1667",
               "dist_m": str(round(rng.uniform(5, 20), 1)), "lookup_ms": str(round(rng.uniform(0.2, 2.0), 2)),
               "latency_ms": str(round(rng.uniform(120, 480), 1))}
        if k % 5 == 0:
            rec["suppressed_reason"] = "spacing"
        records.append(rec)
    priors = {"schema": "waymark.priors.v1", "generated_at": "2026-10-17T21:00:00Z",
              "source": {"name": "SYNTHETIC", "license": "CC0-1.0", "base_url": "https://example.invalid",
                         "street_geometry": "none"},
              "bbox_lnglat": [-122.31, 47.65, -122.3, 47.66], "labels": labels}
    return {"priors": priors, "evidence": evidence, "records": records, "truth": truth}


def write(out_dir: Path, seed: int = 26) -> dict:
    """Write priors.json, evidence.jsonl, records.jsonl and truth.json into out_dir (deterministic bytes)."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    g = generate(seed)
    (out_dir / "priors.json").write_text(_dump(g["priors"]) + "\n", encoding="utf-8")
    (out_dir / "evidence.jsonl").write_text("".join(_dump(e) + "\n" for e in g["evidence"]), encoding="utf-8")
    (out_dir / "records.jsonl").write_text("".join(_dump(r) + "\n" for r in g["records"]), encoding="utf-8")
    (out_dir / "truth.json").write_text(_dump(g["truth"]) + "\n", encoding="utf-8")
    return g
