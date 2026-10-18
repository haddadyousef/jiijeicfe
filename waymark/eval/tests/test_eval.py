"""V1 tests: stats against known values, metrics on hand-built cases, determinism, watermark, refusal on small n."""
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from wm_eval import loader, metrics, report, stats, synth  # noqa: E402
from wm_eval.run import main as run_main  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "fixtures" / "synthetic"


def ev(label, sensor, outcome, build="real-build", ts="2026-10-17T21:00:00Z"):
    return {"schema": "waymark.evidence.v1", "label_id": label, "outcome": outcome, "sensor": sensor, "build": build,
            "ts": ts}


# ---- stats ----
def test_wilson_known_values():
    lo, hi = stats.wilson(5, 10)
    assert (round(lo, 4), round(hi, 4)) == (0.2366, 0.7634)
    lo, hi = stats.wilson(0, 10)
    assert lo == 0.0 and round(hi, 4) == 0.2775
    lo, hi = stats.wilson(10, 10)
    assert round(lo, 4) == 0.7225 and hi == 1.0
    assert stats.wilson(0, 0) is None
    with pytest.raises(ValueError):
        stats.wilson(3, 2)


def test_rate_cell_refuses_small_n():
    c = stats.rate_cell(3, 4)
    assert c["rate"] is None and c["note"] == "insufficient data" and c["n"] == 4 and c["k"] == 3
    c = stats.rate_cell(3, 5)
    assert c["rate"] == 0.6 and c["lo"] is not None and c["note"] is None


def test_kappa_hand_built():
    assert stats.cohen_kappa(20, 5, 10, 15) == pytest.approx(0.4)
    assert stats.cohen_kappa(10, 0, 0, 10) == pytest.approx(1.0)
    assert stats.cohen_kappa(5, 5, 5, 5) == pytest.approx(0.0)
    assert stats.cohen_kappa(10, 0, 0, 0) is None  # expected agreement is 1, kappa undefined
    assert stats.cohen_kappa(0, 0, 0, 0) is None


def test_percentile_nearest_rank():
    v = list(range(1, 101))
    assert stats.percentile(v, 0.5) == 50 and stats.percentile(v, 0.95) == 95 and stats.percentile(v, 1.0) == 100
    assert stats.percentile([], 0.5) is None


def test_holdout_split_is_deterministic_disjoint_and_order_free():
    ids = [f"ps:{i}" for i in range(100)]
    tune, hold = stats.holdout_split(ids)
    tune2, hold2 = stats.holdout_split(list(reversed(ids)) + ids[:5])
    assert (tune, hold) == (tune2, hold2)
    assert len(hold) == 30 and not set(tune) & set(hold) and sorted(tune + hold) == sorted(ids)
    assert stats.holdout_split(ids, seed=1)[1] != hold


# ---- metric 1 ----
def test_outcome_rates_refuses_small_n_and_counts_unknown_labels():
    priors = {"ps:1": {"type": "obstacle"}, "ps:2": {"type": "curb_ramp"}}
    lines = [ev("ps:1", "spotter", "confirmed")] * 4 + [ev("ps:2", "spotter", "confirmed")] * 6 + [ev("ps:9", "ground", "contradicted")]
    r = metrics.outcome_rates(lines, priors)
    assert r["obstacle"]["outcomes"]["confirmed"]["rate"] is None  # n=4
    assert r["obstacle"]["outcomes"]["confirmed"]["note"] == "insufficient data"
    assert r["curb_ramp"]["outcomes"]["confirmed"]["rate"] == 1.0 and r["curb_ramp"]["outcomes"]["confirmed"]["n"] == 6
    assert r["unknown"]["lines"] == 1
    assert r["all"]["lines"] == 11 and r["all"]["labels_with_evidence"] == 3


def test_confirm_rate_uses_decisive_lines_only():
    priors = {"ps:1": {"type": "obstacle"}}
    lines = [ev("ps:1", "spotter", "confirmed")] * 3 + [ev("ps:1", "spotter", "contradicted")] * 3 + [ev("ps:1", "vision", "unverifiable")] * 4
    cell = metrics.outcome_rates(lines, priors)["obstacle"]["confirm_rate_decisive"]
    assert (cell["k"], cell["n"], cell["rate"]) == (3, 6, 0.5)


# ---- metric 2 ----
def _pairs(spec):
    """spec: list of (spotter_outcome, lidar_outcome); one label each."""
    out = []
    for i, (s, l) in enumerate(spec):
        out += [ev(f"ps:{i}", "spotter", s), ev(f"ps:{i}", "lidar_torso", l)]
    return out


def test_sensor_vs_spotter_matrix_and_kappa():
    spec = [("confirmed", "confirmed")] * 20 + [("confirmed", "contradicted")] * 5 + \
           [("contradicted", "confirmed")] * 10 + [("contradicted", "contradicted")] * 15
    r = metrics.sensor_vs_spotter(_pairs(spec))["lidar"]
    assert r["matrix"] == {"spotter_confirmed": {"sensor_confirmed": 20, "sensor_contradicted": 5},
                           "spotter_contradicted": {"sensor_confirmed": 10, "sensor_contradicted": 15}}
    assert r["kappa"] == pytest.approx(0.4) and r["agreement"] == pytest.approx(0.7) and r["paired_labels"] == 50


def test_sensor_vs_spotter_refuses_below_five_pairs_and_skips_unverifiable():
    r = metrics.sensor_vs_spotter(_pairs([("confirmed", "confirmed")] * 4))["lidar"]
    assert r["kappa"] is None and r["agreement"] is None and "insufficient" in r["note"]
    r = metrics.sensor_vs_spotter(_pairs([("confirmed", "confirmed")] * 5 + [("confirmed", "unverifiable")] * 3))["lidar"]
    assert r["paired_labels"] == 5 and r["undecided_pairs"] == 3


def test_sensor_vs_spotter_majority_and_tie():
    lines = [ev("ps:1", "spotter", "confirmed"), ev("ps:1", "spotter", "confirmed"), ev("ps:1", "spotter", "contradicted"),
             ev("ps:1", "lidar_torso", "confirmed"), ev("ps:1", "lidar_head", "confirmed"),
             ev("ps:2", "spotter", "confirmed"), ev("ps:2", "spotter", "contradicted"), ev("ps:2", "lidar_torso", "confirmed")]
    r = metrics.sensor_vs_spotter(lines)["lidar"]
    assert r["matrix"]["spotter_confirmed"]["sensor_confirmed"] == 1 and r["undecided_pairs"] == 1


# ---- metric 7 ----
def test_load_latency_missing_field_is_absent_not_zero_and_p95_rule():
    recs = [{"kind": "waymark_load", "load_ms": 50.0}] + \
           [{"kind": "waymark_cue", "lookup_ms": float(i)} for i in range(1, 21)]
    r = metrics.load_latency(recs)
    assert r["prior_load_ms"]["n"] == 1 and r["prior_load_ms"]["p95"] is None
    assert r["lookup_ms"]["n"] == 20 and r["lookup_ms"]["p95"] == 19.0 and r["lookup_ms"]["median"] == 10.0
    assert r["fix_to_dispatch_ms"] == {"n": 0, "note": "no records carry this field"}
    assert r["cue_outcomes"] == {"spoken": 20}


def test_load_records_keeps_only_waymark_kinds_and_coerces_strings(tmp_path):
    f = tmp_path / "r.jsonl"
    f.write_text('{"kind":"waymark_load","load_ms":"41.5"}\n{"kind":"speech","text":"x"}\nnot json\n\n'
                 '{"kind":"waymark_cue","latency_ms":"300","suppressed_reason":"spacing"}\n', encoding="utf-8")
    recs, skipped = loader.load_records([f])
    assert [r["kind"] for r in recs] == ["waymark_load", "waymark_cue"] and skipped == 1
    assert recs[0]["load_ms"] == 41.5 and recs[1]["latency_ms"] == 300.0


# ---- loader ----
def test_loader_rejects_invalid_evidence(tmp_path):
    f = tmp_path / "e.jsonl"
    good = ev("ps:1", "spotter", "confirmed")
    bad = dict(good, t=1.0)  # `t` is forbidden by the contract
    f.write_text(json.dumps(good) + "\n" + json.dumps(bad) + "\nnot json\n", encoding="utf-8")
    lines, rejected = loader.load_evidence([f])
    assert len(lines) == 1 and len(rejected) == 2 and rejected[0]["line"] == 2


# ---- synthetic data, watermark, determinism ----
def test_synthetic_generator_is_seeded_valid_and_in_the_synthetic_id_range(tmp_path):
    a, b = tmp_path / "a", tmp_path / "b"
    synth.write(a, 26); synth.write(b, 26)
    for n in ("priors.json", "evidence.jsonl", "records.jsonl", "truth.json"):
        assert (a / n).read_bytes() == (b / n).read_bytes()
    synth.write(tmp_path / "c", 27)
    assert (tmp_path / "c" / "evidence.jsonl").read_bytes() != (a / "evidence.jsonl").read_bytes()
    priors = loader.load_priors(a / "priors.json")
    lines, rejected = loader.load_evidence([a / "evidence.jsonl"])
    assert not rejected and lines and all(int(k.split(":")[1]) >= 9_000_000_000 for k in priors)
    assert all(e["build"].startswith("waymark-synthetic") for e in lines)


def test_committed_synthetic_fixtures_match_the_generator(tmp_path):
    synth.write(tmp_path, 26)
    for n in ("priors.json", "evidence.jsonl", "records.jsonl", "truth.json"):
        assert (FIX / n).read_bytes() == (tmp_path / n).read_bytes(), f"{n} drifted; rerun wm_eval.synth"


def test_committed_summary_matches_a_fresh_run_and_is_watermarked(tmp_path):
    priors = loader.load_priors(FIX / "priors.json")
    ev_, _ = loader.load_evidence([FIX / "evidence.jsonl"])
    recs, sk = loader.load_records([FIX / "records.jsonl"])
    s = report.build_summary(priors, ev_, recs, skipped_records=sk, synthetic=report.is_synthetic(ev_))
    assert s["synthetic"] is True and s["watermark"] == "SYNTHETIC"
    assert (FIX / "summary.json").read_bytes() == report.summary_bytes(s)
    assert report.report_md(s).startswith("> **SYNTHETIC")


def test_real_evidence_is_not_watermarked():
    assert report.is_synthetic([ev("ps:1", "spotter", "confirmed")]) is False
    s = report.build_summary({"ps:1": {"type": "obstacle"}}, [ev("ps:1", "spotter", "confirmed")], [])
    assert s["watermark"] is None and not report.report_md(s).startswith("> **SYNTHETIC")


def test_synthetic_lidar_agreement_is_in_the_planted_range():
    g = synth.generate(26)
    k = metrics.sensor_vs_spotter(g["evidence"])["lidar"]
    assert k["paired_labels"] >= 20 and 0.5 < k["kappa"] <= 1.0  # planted: 85% sensitivity, 90% specificity


def test_holdout_reports_only_held_out_labels():
    g = synth.generate(26)
    s_all = report.build_summary(g["priors"] and {l["id"]: l for l in g["priors"]["labels"]}, g["evidence"], [])
    s_ho = report.build_summary({l["id"]: l for l in g["priors"]["labels"]}, g["evidence"], [], holdout=True)
    assert s_ho["holdout"]["reported_labels"] + s_ho["holdout"]["tune_labels"] == s_all["outcome_rates"]["all"]["labels_with_evidence"]
    assert s_ho["outcome_rates"]["all"]["labels_with_evidence"] == s_ho["holdout"]["reported_labels"]


def test_cli_end_to_end_is_byte_deterministic_and_exit_codes(tmp_path):
    assert run_main(["--synthetic", "--out", str(tmp_path / "o1")]) == 0
    assert run_main(["--synthetic", "--out", str(tmp_path / "o2")]) == 0
    assert (tmp_path / "o1" / "summary.json").read_bytes() == (tmp_path / "o2" / "summary.json").read_bytes()
    assert (tmp_path / "o1" / "outcome_rates.png").stat().st_size > 1000
    bad = tmp_path / "bad.jsonl"
    bad.write_text('{"nope":1}\n', encoding="utf-8")
    argv = ["--priors", str(FIX / "priors.json"), "--evidence", str(FIX / "evidence.jsonl"), str(bad), "--out", str(tmp_path / "o3")]
    assert run_main(argv) == 1
    assert run_main(argv + ["--allow-rejected"]) == 0


def test_unverifiable_reasons_counts_only_unverifiable_with_a_reason():
    recs = [{"kind": "waymark_evidence", "outcome": "unverifiable", "reason": "lateral"},
            {"kind": "waymark_evidence", "outcome": "unverifiable", "reason": "lateral"},
            {"kind": "waymark_evidence", "outcome": "unverifiable", "reason": "route_end"},
            {"kind": "waymark_evidence", "outcome": "unverifiable"},
            {"kind": "waymark_evidence", "outcome": "confirmed", "reason": "x"},
            {"kind": "waymark_cue", "outcome": "unverifiable", "reason": "y"}]
    assert metrics.unverifiable_reasons(recs) == {"lateral": 2, "route_end": 1}
    assert metrics.unverifiable_reasons([]) == {}
