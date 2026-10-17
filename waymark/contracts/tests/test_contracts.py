"""Contract tests. Run: cd waymark/contracts && python -m pytest -q"""
import json
import math
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ref"))

import belief as B  # noqa: E402
import make_golden  # noqa: E402
import validate as V  # noqa: E402

GOLDEN = ROOT / "golden"


def load(name):
    return json.loads((GOLDEN / name).read_text(encoding="utf-8"))


# ---------- priors ----------

def test_priors_sample_is_valid():
    assert V.validate_priors(load("priors_sample.json")) == []


def test_priors_sample_first_label_is_the_real_one_and_matches_plan_5_2():
    lab = load("priors_sample.json")["labels"][0]
    assert lab["id"] == "ps:13290420" and lab["type"] == "curb_ramp"
    assert (lab["lat"], lab["lng"]) == (47.652233, -122.306389)
    assert lab["severity"] == 1 and lab["n_agree"] == 2 and lab["imagery_date"] == "2019-05"
    assert "users" not in lab  # labeler ids never enter a bundle


def test_unknown_type_is_rejected_by_producer_but_allowed_for_decoder_tests():
    d = load("priors_unknown_type.json")
    assert V.validate_priors(d) != []
    assert V.validate_priors(d, allow_unknown_types=True) == []


def test_every_invalid_case_is_rejected():
    data = load("priors_invalid_cases.json")
    assert len(data["cases"]) >= 12
    for c in data["cases"]:
        assert V.validate_priors(c["doc"]) != [], c["name"]


def test_fractional_severity_is_accepted():
    sev = [l["severity"] for l in load("priors_sample.json")["labels"]]
    assert 1.5 in sev


# ---------- evidence ----------

def test_evidence_lines_valid_and_never_use_t_or_kind():
    lines = (GOLDEN / "evidence_sample.jsonl").read_text(encoding="utf-8").splitlines()
    assert len(lines) >= 8
    seen = set()
    for line in lines:
        obj = json.loads(line)
        assert V.validate_evidence_line(obj) == [], line
        assert "t" not in obj and "kind" not in obj
        seen.add((obj["outcome"], obj["sensor"]))
    assert {"confirmed", "contradicted", "unverifiable"} <= {o for o, _ in seen}


def test_evidence_rejects_bad_lines():
    good = json.loads((GOLDEN / "evidence_sample.jsonl").read_text(encoding="utf-8").splitlines()[0])
    for patch in ({"outcome": "maybe"}, {"sensor": "radar"}, {"label_id": "123"}, {"ts": "2026-10-17 21:00"}, {"kind": "x"}):
        bad = {**good, **patch}
        assert V.validate_evidence_line(bad) != [], patch


# ---------- belief: independent hand-computed rows (WAYMARK_PLAN 5.3) ----------

DAY = 86400.0


def test_plan_5_3_worked_rows():
    b = B.Belief("obstacle", 2, 0)
    r = b.read(0)
    assert (r["a"], r["b"]) == (3.0, 1.0) and r["p"] == 0.75
    b.update(0, "contradicted", "spotter")
    r = b.read(0)
    assert (r["a"], r["b"], r["p"]) == (3.0, 3.0, 0.5)
    r = b.read(60 * DAY)
    assert (r["a"], r["b"]) == (3.0, 2.0) and math.isclose(r["p"], 0.6, abs_tol=1e-12)
    r = b.read(120 * DAY)
    assert (r["a"], r["b"]) == (3.0, 1.5) and math.isclose(r["p"], 2 / 3, abs_tol=1e-12)

    m = B.Belief("missing_curb_ramp", 1, 1)
    r = m.read(0)
    assert (r["a"], r["b"], r["p"]) == (2.0, 2.0, 0.5)
    m.update(0, "confirmed", "lidar_torso")
    r = m.read(0)
    assert (r["a"], r["b"]) == (3.0, 2.0) and math.isclose(r["p"], 0.6, abs_tol=1e-12)
    m.update(0, "confirmed", "spotter")
    r = m.read(0)
    assert (r["a"], r["b"]) == (5.0, 2.0) and math.isclose(r["p"], 5 / 7, abs_tol=1e-12)


def test_decay_halves_per_half_life_by_type():
    for typ, hl in (("obstacle", 60), ("surface_problem", 120), ("no_sidewalk", 365), ("crosswalk", 365), ("unknown_future", 365)):
        b = B.Belief(typ, 0, 0)
        b.update(0, "confirmed", "spotter")  # e_a = 2
        assert math.isclose(b.read(hl * DAY)["a"], 1 + 1.0, abs_tol=1e-12), typ
        assert math.isclose(b.read(2 * hl * DAY)["a"], 1 + 0.5, abs_tol=1e-12), typ


def test_unverifiable_is_a_no_op():
    a = B.Belief("obstacle", 1, 1)
    a.update(0, "confirmed", "spotter")
    before = a.read(10 * DAY)
    a.update(5 * DAY, "unverifiable", "lidar_torso")
    assert a.read(10 * DAY) == before
    assert a.t_last == 0


def test_read_before_last_update_does_not_decay_backwards():
    b = B.Belief("obstacle", 0, 0)
    b.update(100 * DAY, "confirmed", "spotter")
    assert b.read(50 * DAY) == b.read(100 * DAY)


def test_bad_inputs_raise():
    b = B.Belief("obstacle", 0, 0)
    with pytest.raises(ValueError):
        b.update(0, "confirmed", "radar")
    with pytest.raises(ValueError):
        b.update(0, "maybe", "spotter")


def test_determinism():
    def run():
        b = B.Belief("obstacle", 3, 1)
        for i, (o, s) in enumerate([("confirmed", "lidar_torso"), ("contradicted", "spotter"), ("confirmed", "ground")]):
            b.update(i * 9 * DAY, o, s)
        return b.read(50 * DAY)
    assert run() == run()


# ---------- threshold (WAYMARK_PLAN 5.4) ----------

def test_threshold_exact_values():
    assert math.isclose(B.tau_for("obstacle"), 1 / 6, abs_tol=1e-12)
    assert math.isclose(B.tau_for("missing_curb_ramp"), 0.2, abs_tol=1e-12)
    assert math.isclose(B.tau_for("no_sidewalk"), 0.2, abs_tol=1e-12)
    assert math.isclose(B.tau_for("surface_problem"), 1 / 3, abs_tol=1e-12)
    for t in ("curb_ramp", "crosswalk", "other", "future"):
        assert B.tau_for(t) is None and B.should_consider_alert(t, 1.0) is False


def test_threshold_monotonic_in_miss_cost():
    taus = [B.tau(cm, 1.0) for cm in (1, 2, 4, 8, 16)]
    assert taus == sorted(taus, reverse=True)


# ---------- golden vectors agree with the reference ----------

def test_belief_vectors_replay_matches_reference():
    vec = load("belief_vectors.json")
    assert vec["constants"]["weights"] == B.WEIGHTS
    assert len(vec["cases"]) >= 8
    for c in vec["cases"]:
        b = B.Belief(c["type"], c["n_agree"], c["n_disagree"])
        events = sorted(enumerate(c["events"]), key=lambda x: (B.parse_ts(x[1]["at"]), x[0]))
        i = 0
        for r in sorted(c["reads"], key=lambda r: B.parse_ts(r["at"])):
            while i < len(events) and B.parse_ts(events[i][1]["at"]) <= B.parse_ts(r["at"]):
                e = events[i][1]
                b.update(B.parse_ts(e["at"]), e["outcome"], e["sensor"])
                i += 1
            got = b.read(B.parse_ts(r["at"]))
            for k in ("a", "b", "p", "n_eff"):
                assert math.isclose(got[k], r[k], abs_tol=1e-9), (c["name"], r["at"], k)


def test_belief_vectors_contain_the_plan_rows():
    vec = {c["name"]: c for c in load("belief_vectors.json")["cases"]}
    c = vec["obstacle_2_0_spotter_contradicts_then_decays"]
    ps = [round(r["p"], 6) for r in c["reads"]]
    assert ps == [0.75, 0.5, 0.6, 0.666667]
    c = vec["missing_curb_ramp_1_1_torso_then_spotter_confirm"]
    assert [round(r["p"], 6) for r in c["reads"]] == [0.5, 0.714286]


def test_threshold_vectors_match_reference():
    vec = load("threshold_vectors.json")
    for c in vec["tau"]:
        assert math.isclose(B.tau_for(c["type"]), c["tau"], abs_tol=1e-12)
    for c in vec["generic_tau"]:
        assert math.isclose(B.tau(c["c_miss"], c["c_fa"]), c["tau"], abs_tol=1e-12)
    for c in vec["alerts"]:
        assert B.should_consider_alert(c["type"], c["p"]) is c["consider_alert"]


# ---------- generator is deterministic and the committed files are its output ----------

def test_committed_golden_equals_generator_output():
    with tempfile.TemporaryDirectory() as tmp:
        make_golden.main(Path(tmp))
        for f in sorted(GOLDEN.iterdir()):
            assert (Path(tmp) / f.name).read_bytes() == f.read_bytes(), f.name
        assert sorted(p.name for p in Path(tmp).iterdir()) == sorted(p.name for p in GOLDEN.iterdir())
    make_golden.GOLDEN = GOLDEN
