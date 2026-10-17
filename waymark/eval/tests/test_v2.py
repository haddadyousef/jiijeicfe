"""V2 tests: belief-before-tap items, Brier on a toy case, sweep minimizer and sensitivity on hand-built cases,
staleness trend, positional error, refusal on small n, hold-out discipline."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from wm_eval import report, v2, synth  # noqa: E402


def item(p, truth, typ="surface_problem"):
    return {"label_id": "ps:1", "type": typ, "ts": "2026-10-17T21:00:00Z", "p": p, "truth": truth}


def ev(label, sensor, outcome, ts, along=None):
    return {"schema": "waymark.evidence.v1", "label_id": label, "outcome": outcome, "sensor": sensor, "build": "b",
            "ts": ts, "along_m": along}


PRIORS = {"ps:1": {"type": "obstacle", "n_agree": 1, "n_disagree": 0, "imagery_date": "2019-05"}}


# ---- build_items ----
def test_items_use_the_belief_read_just_before_each_tap():
    lines = [ev("ps:1", "spotter", "confirmed", "2026-10-17T21:00:00Z"),
             ev("ps:1", "lidar_torso", "unverifiable", "2026-10-17T21:01:00Z"),   # no-op
             ev("ps:1", "spotter", "contradicted", "2026-10-17T21:02:00Z"),
             ev("ps:9", "spotter", "confirmed", "2026-10-17T21:03:00Z")]          # not in priors: skipped
    items = v2.build_items(lines, PRIORS)
    assert [i["p"] for i in items] == [pytest.approx(2 / 3, abs=1e-6), pytest.approx(0.8, abs=1e-4)]  # a=2,b=1; then +2 confirmed: a=4,b=1 (2 min of decay is ~1e-6)
    assert [i["truth"] for i in items] == [True, False]


def test_items_skip_non_spotter_and_unverifiable_taps():
    lines = [ev("ps:1", "lidar_torso", "confirmed", "2026-10-17T21:00:00Z"), ev("ps:1", "spotter", "unverifiable", "2026-10-17T21:01:00Z")]
    assert v2.build_items(lines, PRIORS) == []


# ---- calibration ----
def test_calibration_refuses_below_30_and_shows_raw_counts():
    c = v2.calibration([item(0.8, True)] * 29)
    assert c["assessable"] is False and c["brier"] is None and "cannot be assessed" in c["note"]
    assert sum(b["n"] for b in c["bins"]) == 29


def test_brier_on_a_toy_case():
    items = [item(0.8, True)] * 16 + [item(0.8, False)] * 4 + [item(0.2, True)] * 4 + [item(0.2, False)] * 16
    c = v2.calibration(items)
    assert c["assessable"] and c["brier"] == pytest.approx(0.16)
    assert c["brier_baseline"] == pytest.approx(0.25)    # prevalence 20/40 = 0.5
    b = {round(x["lo"], 1): x for x in c["bins"]}
    assert b[0.8]["n"] == 20 and b[0.8]["observed"] == pytest.approx(0.8) and b[0.2]["observed"] == pytest.approx(0.2)


def test_p_of_exactly_one_lands_in_the_top_bin():
    c = v2.calibration([item(1.0, True)] * 30)
    assert c["bins"][-1]["n"] == 30 and c["brier"] == 0.0


# ---- threshold sweep ----
def test_sweep_minimizer_hand_built():
    items = [item(0.9, True, "obstacle")] * 6 + [item(0.3, False, "obstacle")] * 4
    s = v2.threshold_sweep(items)["obstacle"]
    assert s["minimizer_tau"] == 0.31 and s["cost_at_minimizer"] == 0.0     # smallest tau that rejects the p=0.3 false alarms
    assert s["cost_at_default"] == 4.0                                       # default 1/6 still fires on all four of them


def test_sweep_cost_sensitivity_moves_the_minimizer():
    items = [item(0.6, True)] * 5 + [item(0.2, True)] * 2 + [item(0.2, False)] * 3        # surface_problem: C_miss 2, C_fa 1
    s = v2.threshold_sweep(items)["surface_problem"]
    assert s["minimizer_tau"] == 0.05 and s["cost_at_minimizer"] == 3.0                    # alert on all: 3 false alarms vs 2 misses x 2
    assert s["sensitivity"] == {"half_c_miss": 0.21, "double_c_miss": 0.05}               # cheap misses: stop alerting on p=0.2


def test_sweep_ties_go_to_the_smaller_tau_and_refuses_small_n():
    assert v2.threshold_sweep([item(0.9, True)] * 12)["surface_problem"]["minimizer_tau"] == 0.05
    r = v2.threshold_sweep([item(0.9, True)] * 9)["surface_problem"]
    assert "insufficient data" in r["note"] and "minimizer_tau" not in r


def test_sweep_uses_the_computed_default_tau_and_skips_types_without_costs():
    s = v2.threshold_sweep([item(0.9, True, "curb_ramp")] * 20)
    assert set(s) == {"missing_curb_ramp", "no_sidewalk", "obstacle", "surface_problem"}
    assert s["obstacle"]["default_tau"] == pytest.approx(1 / 6, abs=1e-6) and s["surface_problem"]["default_tau"] == pytest.approx(1 / 3, abs=1e-6)


def test_holdout_sweep_tunes_on_tune_and_reports_on_hold_out():
    tune = [item(0.9, True)] * 6 + [item(0.4, False)] * 4
    hold = [item(0.4, False)] * 2 + [item(0.9, True)] * 3
    s = v2.threshold_sweep(tune, hold)["surface_problem"]
    assert s["minimizer_tau"] == 0.41
    assert s["held_out"] == {"n": 5, "cost_at_default": 2.0, "cost_at_tuned_tau": 0.0}   # default 0.333 fires on both p=0.4 false alarms


# ---- staleness ----
def _stale_priors(year):
    return {f"ps:{i}": {"type": "obstacle", "n_agree": 1, "n_disagree": 0, "imagery_date": f"{year}-06"} for i in range(1, 11)}


def test_staleness_trend_direction_and_refusal():
    pri = {**{k: v for k, v in _stale_priors(2025).items()},
           **{f"ps:{100 + i}": {"type": "obstacle", "n_agree": 1, "n_disagree": 0, "imagery_date": "2012-06"} for i in range(10)}}
    lines = [ev(f"ps:{i}", "spotter", "confirmed", "2026-10-17T21:00:00Z") for i in range(1, 11)]                    # 1y old, all there
    lines += [ev(f"ps:{100 + i}", "spotter", "contradicted", "2026-10-17T21:00:00Z") for i in range(10)]            # 14y old, all gone
    st = v2.staleness(lines, pri)
    assert st["by_age"]["0-3y"]["rate"] == 1.0 and st["by_age"]["10y+"]["rate"] == 0.0
    assert "older imagery is confirmed less often" in st["trend"]
    one = v2.staleness(lines[:10], pri)
    assert one["trend"].startswith("insufficient data")


def test_staleness_no_trend_when_intervals_overlap_and_counts_taps_without_dates():
    pri = {**_stale_priors(2025), **{f"ps:{100 + i}": {"type": "obstacle", "n_agree": 1, "n_disagree": 0, "imagery_date": "2012-06"} for i in range(10)}}
    young = ["confirmed"] * 6 + ["contradicted"] * 4
    old = ["confirmed"] * 5 + ["contradicted"] * 5
    lines = [ev(f"ps:{i + 1}", "spotter", o, "2026-10-17T21:00:00Z") for i, o in enumerate(young)]
    lines += [ev(f"ps:{100 + i}", "spotter", o, "2026-10-17T21:00:00Z") for i, o in enumerate(old)]
    pri["ps:500"] = {"type": "obstacle", "n_agree": 1, "n_disagree": 0, "imagery_date": None}
    lines.append(ev("ps:500", "spotter", "confirmed", "2026-10-17T21:00:00Z"))
    st = v2.staleness(lines, pri)
    assert st["trend"] == "no clear trend (intervals overlap)" and st["taps_without_imagery_date"] == 1


# ---- positional error ----
def test_positional_error_percentiles_and_refusal():
    lines = [ev("ps:1", "lidar_torso", "confirmed", "2026-10-17T21:00:00Z", along=float(a)) for a in range(-10, 10)]      # 20 events: -10..9
    lines += [ev("ps:1", "lidar_torso", "contradicted", "2026-10-17T21:00:00Z", along=99.0),                              # not a confirm: ignored
              ev("ps:1", "ground", "confirmed", "2026-10-17T21:00:00Z", along=1.0)]
    pe = v2.positional_error(lines)
    t = pe["lidar_torso"]
    assert t["n"] == 20 and t["median"] == -1.0 and t["p90_abs"] == 9.0 and t["suggested_label_error_m"] == 9.0
    assert pe["ground"]["n"] == 1 and pe["ground"]["suggested_label_error_m"] is None and "20" in pe["ground"]["note"]


# ---- integration ----
def test_summary_contains_v2_sections_and_is_deterministic_on_synthetic_data():
    g = synth.generate(26)
    priors = {l["id"]: l for l in g["priors"]["labels"]}
    s1 = report.build_summary(priors, g["evidence"], g["records"], synthetic=True)
    s2 = report.build_summary(priors, g["evidence"], g["records"], synthetic=True)
    assert report.summary_bytes(s1) == report.summary_bytes(s2)
    assert {"calibration", "threshold_sweep", "staleness", "positional_error"} <= set(s1)
    assert s1["calibration"]["n"] == 40 and s1["calibration"]["assessable"]
    md = report.report_md(s1)
    for h in ("## 3. Calibration", "## 4. Threshold sweep", "## 5. Staleness", "## 6. Positional error"):
        assert h in md


def test_holdout_summary_tunes_on_the_rest():
    g = synth.generate(26)
    priors = {l["id"]: l for l in g["priors"]["labels"]}
    s = report.build_summary(priors, g["evidence"], g["records"], holdout=True, synthetic=True)
    assert s["calibration"]["n"] < 40 and s["holdout"]["tune_labels"] > s["holdout"]["reported_labels"]
    sweeps = [r for r in s["threshold_sweep"].values() if not r.get("note")]
    assert all("held_out" in r for r in sweeps)
