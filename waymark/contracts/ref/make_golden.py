"""Deterministic generator for contracts/golden/*. Run from anywhere: python make_golden.py

Only the first label of priors_sample.json is real Project Sidewalk data (CC0, labeler ids removed).
Every other label and every evidence line is SYNTHETIC test data, marked by id range (>= 9000000001)
and build string. Do not use these files as evidence of anything.
"""
from __future__ import annotations

import copy
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import belief as B

GOLDEN = Path(__file__).resolve().parent.parent / "golden"

T0 = datetime(2026, 10, 17, 21, 0, 0, tzinfo=timezone.utc)


def iso(days: float = 0.0) -> str:
    return (T0 + timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")


def dump(path: Path, obj) -> None:
    path.write_text(json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def label(cid, typ, lat, lng, severity, tags, agree, dis, unsure, cluster, street, inter, osm, imagery, ldate):
    return {
        "id": f"ps:{cid}", "type": typ, "lat": lat, "lng": lng, "severity": severity, "tags": tags,
        "n_agree": agree, "n_disagree": dis, "n_unsure": unsure, "cluster_size": cluster,
        "street_edge_id": street, "intersection_id": inter, "osm_way_id": osm,
        "imagery_date": imagery, "label_date": ldate, "source_cluster_id": cid,
    }


SOURCE = {
    "name": "Project Sidewalk",
    "license": "CC0-1.0",
    "base_url": "https://sidewalk-sea.cs.washington.edu",
    "street_geometry": "OpenStreetMap contributors, ODbL",
}
BBOX = [-122.308, 47.652, -122.302, 47.656]


def priors_sample() -> dict:
    return {
        "schema": "waymark.priors.v1",
        "generated_at": "2026-10-17T21:00:00Z",
        "source": SOURCE,
        "bbox_lnglat": BBOX,
        "labels": [
            # REAL: the feature the Mac fetched at 13:00 and the Windows session re-counted at 13:55.
            label(13290420, "curb_ramp", 47.652233, -122.306389, 1, [], 2, 0, 0, 1, 20109, None, 283038445, "2019-05", "2019-07"),
            # SYNTHETIC from here. n_agree/n_disagree match the worked belief examples in WAYMARK_PLAN 5.3.
            label(9000000001, "obstacle", 47.6531, -122.3061, 3, ["pole"], 2, 0, 0, 2, 20110, None, 283038446, "2019-05", "2019-08"),
            label(9000000002, "missing_curb_ramp", 47.6538, -122.3052, 3, [], 1, 1, 0, 1, 20111, 4001, 283038447, "2020-06", "2020-07"),
            label(9000000003, "surface_problem", 47.6544, -122.3043, 1.5, ["cracks", "uneven"], 3, 1, 1, 4, 20112, None, None, "2018-09", "2018-10"),
            label(9000000004, "no_sidewalk", 47.6550, -122.3034, None, [], 0, 0, 0, 1, None, None, None, None, None),
            label(9000000005, "crosswalk", 47.6553, -122.3028, None, [], 4, 0, 0, 3, 20113, 4002, 283038448, "2021-04", "2021-04"),
            label(9000000006, "other", 47.6554, -122.3022, 2, ["fountain"], 0, 0, 2, 1, 20114, None, None, "2019-11", "2019-12"),
        ],
    }


def priors_unknown_type() -> dict:
    d = copy.deepcopy(priors_sample())
    d["labels"] = [d["labels"][0], label(9000000007, "future_type", 47.6541, -122.3049, 2, [], 1, 0, 0, 1, None, None, None, None, None)]
    return d


def priors_invalid_cases() -> dict:
    base = priors_sample()
    base["labels"] = base["labels"][:3]

    def mutate(fn):
        d = copy.deepcopy(base)
        fn(d)
        return d

    def set_label(i, key, value):
        return lambda d: d["labels"][i].__setitem__(key, value)

    cases = [
        ("wrong_schema_id", True, "schema id must be waymark.priors.v1", lambda d: d.__setitem__("schema", "waymark.priors.v2")),
        ("missing_labels", True, "labels is required", lambda d: d.pop("labels")),
        ("lat_out_of_range", True, "lat above 90", set_label(1, "lat", 91.0)),
        ("lng_out_of_range", True, "lng below -180", set_label(1, "lng", -181.0)),
        ("severity_too_high", True, "severity above 3", set_label(1, "severity", 4)),
        ("severity_too_low", True, "severity below 1", set_label(1, "severity", 0.5)),
        ("negative_count", True, "n_agree below 0", set_label(1, "n_agree", -1)),
        ("missing_required_field", True, "label without n_unsure", lambda d: d["labels"][1].pop("n_unsure")),
        ("bad_month", False, "imagery_date month 13 (decoders may treat dates as opaque strings)", set_label(1, "imagery_date", "2019-13")),
        ("bbox_wrong_order", False, "bbox min greater than max (semantic check only)", lambda d: d.__setitem__("bbox_lnglat", [-122.302, 47.656, -122.308, 47.652])),
        ("id_mismatch", False, "id does not equal ps: + source_cluster_id (semantic check only)", set_label(1, "source_cluster_id", 5)),
        ("unsorted_labels", False, "labels not sorted by source_cluster_id (semantic check only)", lambda d: d["labels"].reverse()),
    ]
    out = []
    for name, decoder_must_reject, reason, fn in cases:
        out.append({"name": name, "reason": reason, "decoder_must_reject": decoder_must_reject, "doc": mutate(fn)})
    return {
        "note": "Producer validation (ref/validate.py) rejects every case. A Swift decoder must reject the cases with decoder_must_reject true; for false it may accept. Not covered here: more than 20000 labels (generate in the test).",
        "cases": out,
    }


def evidence_lines() -> list[dict]:
    def ev(label_id, outcome, sensor, minute, **kw):
        base = {
            "schema": "waymark.evidence.v1", "label_id": label_id, "outcome": outcome, "sensor": sensor,
            "dist_m": None, "along_m": None, "gps_acc_m": None, "speed_mps": None, "tilt_deg": None,
            "torso_cover": None, "head_cover": None,
            "build": "waymark-synthetic-golden",
            "ts": (T0 + timedelta(minutes=minute)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        base.update(kw)
        return base

    return [
        ev("ps:9000000001", "confirmed", "lidar_torso", 41, dist_m=0.9, along_m=1.4, gps_acc_m=8.0, speed_mps=1.1, tilt_deg=5.0, torso_cover=True, head_cover=True),
        ev("ps:9000000001", "contradicted", "lidar_torso", 71, dist_m=None, along_m=0.0, gps_acc_m=6.0, speed_mps=1.0, tilt_deg=6.5, torso_cover=True, head_cover=False),
        ev("ps:9000000002", "contradicted", "spotter", 42, gps_acc_m=9.5, tilt_deg=4.0),
        ev("ps:9000000002", "confirmed", "spotter", 72, gps_acc_m=7.0),
        ev("ps:9000000002", "confirmed", "ground", 43, dist_m=0.0, along_m=-0.5, gps_acc_m=10.0, speed_mps=0.9, tilt_deg=5.5, torso_cover=True, head_cover=False),
        ev("ps:9000000003", "confirmed", "spotter", 44, gps_acc_m=12.0),
        ev("ps:9000000001", "unverifiable", "lidar_head", 45, gps_acc_m=35.0, speed_mps=1.2, tilt_deg=30.0, torso_cover=False, head_cover=False),
        ev("ps:9000000004", "contradicted", "vision", 46),
    ]


def belief_vectors() -> dict:
    def case(name, typ, agree, dis, events, read_days):
        b = B.Belief(typ, agree, dis)
        ev_out = [{"at": iso(d), "outcome": o, "sensor": s} for d, o, s in events]
        # Events apply in the order given; reads are computed after all events with at <= the read time.
        reads = []
        applied = 0
        ordered_events = sorted(enumerate(events), key=lambda x: (x[1][0], x[0]))
        for rd in sorted(read_days):
            while applied < len(ordered_events) and ordered_events[applied][1][0] <= rd:
                _, (d, o, s) = ordered_events[applied]
                b.update(B.parse_ts(iso(d)), o, s)
                applied += 1
            r = b.read(B.parse_ts(iso(rd)))
            reads.append({"at": iso(rd), **r})
        return {"name": name, "type": typ, "n_agree": agree, "n_disagree": dis, "events": ev_out, "reads": reads}

    cases = [
        case("obstacle_2_0_spotter_contradicts_then_decays", "obstacle", 2, 0,
             [(0, "contradicted", "spotter")], [-1, 0, 60, 120]),
        case("missing_curb_ramp_1_1_torso_then_spotter_confirm", "missing_curb_ramp", 1, 1,
             [(0, "confirmed", "lidar_torso"), (0, "confirmed", "spotter")], [-1, 0]),
        case("obstacle_0_0_confirm_then_contradict_60d_later", "obstacle", 0, 0,
             [(0, "confirmed", "lidar_torso"), (60, "contradicted", "lidar_torso")], [30, 60, 120]),
        case("surface_problem_unverifiable_is_a_no_op", "surface_problem", 0, 0,
             [(0, "confirmed", "spotter"), (120, "unverifiable", "lidar_torso")], [120, 240]),
        case("crosswalk_uses_default_half_life_365", "crosswalk", 0, 0,
             [(0, "confirmed", "lidar_torso")], [365, 730]),
        case("same_instant_ground_and_vision_weights", "no_sidewalk", 0, 0,
             [(0, "confirmed", "ground"), (0, "contradicted", "vision")], [0]),
        case("many_agree_no_evidence", "curb_ramp", 10, 0, [], [0, 400]),
        case("read_before_first_event_is_the_prior", "missing_curb_ramp", 0, 0,
             [(10, "confirmed", "spotter")], [5, 10]),
    ]
    return {
        "schema": "waymark.belief_vectors.v1",
        "note": "Expected values come from ref/belief.py and are cross-checked against hand-computed rows in tests/test_contracts.py. Events are applied in time order (ties keep listed order) before each read at or after them; a read earlier than an event is taken before that event. Swift tolerance 1e-9.",
        "constants": {
            "half_life_days": {"obstacle": 60.0, "surface_problem": 120.0, "default": 365.0},
            "weights": B.WEIGHTS,
        },
        "cases": cases,
    }


def threshold_vectors() -> dict:
    types = ["obstacle", "missing_curb_ramp", "no_sidewalk", "surface_problem"]
    tau_cases = [{"type": t, "c_miss": B.COSTS[t][0], "c_fa": B.COSTS[t][1], "tau": B.tau_for(t)} for t in types]
    generic = [{"c_miss": cm, "c_fa": cf, "tau": B.tau(cm, cf)} for cm, cf in [(5, 1), (1, 1), (10, 1), (2, 3)]]
    alerts = []
    for t, p in [("obstacle", 0.1), ("obstacle", 1 / 6), ("obstacle", 0.5), ("missing_curb_ramp", 0.19), ("missing_curb_ramp", 0.2),
                 ("surface_problem", 0.3), ("surface_problem", 0.34), ("no_sidewalk", 0.2),
                 ("curb_ramp", 0.99), ("crosswalk", 0.99), ("other", 0.99)]:
        alerts.append({"type": t, "p": p, "consider_alert": B.should_consider_alert(t, p)})
    return {
        "schema": "waymark.threshold_vectors.v1",
        "note": "tau = c_fa / (c_fa + c_miss), computed, never a literal. consider_alert means p >= tau; curb_ramp, crosswalk and other have no threshold and never alert by threshold (curb_ramp is spoken only at Detailed, by policy). Tolerance 1e-12.",
        "tau": tau_cases,
        "generic_tau": generic,
        "alerts": alerts,
    }


def main(out: Path = GOLDEN) -> None:
    global GOLDEN
    GOLDEN = out
    GOLDEN.mkdir(parents=True, exist_ok=True)
    dump(GOLDEN / "priors_sample.json", priors_sample())
    dump(GOLDEN / "priors_unknown_type.json", priors_unknown_type())
    dump(GOLDEN / "priors_invalid_cases.json", priors_invalid_cases())
    (GOLDEN / "evidence_sample.jsonl").write_text(
        "".join(json.dumps(o, sort_keys=True, separators=(",", ":")) + "\n" for o in evidence_lines()), encoding="utf-8")
    dump(GOLDEN / "belief_vectors.json", belief_vectors())
    dump(GOLDEN / "threshold_vectors.json", threshold_vectors())
    print("golden files written to", GOLDEN)


if __name__ == "__main__":
    main()
