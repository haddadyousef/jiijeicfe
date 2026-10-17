"""Assemble summary.json, by_type.csv, report.md and the outcome plot. Same inputs give identical summary.json bytes."""
from __future__ import annotations

import csv
import io
import json
from pathlib import Path

from . import metrics, v2
from .stats import holdout_split

SYNTH_PREFIX = "waymark-synthetic"


def is_synthetic(evidence: list[dict], forced: bool = False) -> bool:
    """Watermark rule: any synthetic-build evidence line taints the whole report."""
    return forced or any(e["build"].startswith(SYNTH_PREFIX) for e in evidence)


def build_summary(priors: dict, evidence: list[dict], records: list[dict], *, rejected: int = 0,
                  skipped_records: int = 0, holdout: bool = False, seed: int = 26, synthetic: bool = False) -> dict:
    split = None
    tune_ev = None
    if holdout:
        tune, hold = holdout_split([e["label_id"] for e in evidence], 0.3, seed)
        keep = set(hold)
        split = {"seed": seed, "fraction": 0.3, "tune_labels": len(tune), "reported_labels": len(hold)}
        tune_ev = [e for e in evidence if e["label_id"] not in keep]
        evidence = [e for e in evidence if e["label_id"] in keep]
    tune_items, hold_items = v2_items(priors, evidence, tune_ev)
    unknown = sorted({e["label_id"] for e in evidence if e["label_id"] not in priors})
    return {
        "schema": "waymark.eval_summary.v1",
        "synthetic": synthetic,
        "watermark": "SYNTHETIC" if synthetic else None,
        "holdout": split,
        "inputs": {"priors_labels": len(priors), "evidence_lines": len(evidence), "evidence_rejected": rejected,
                   "records": len(records), "records_unreadable": skipped_records,
                   "evidence_label_ids_not_in_priors": len(unknown)},
        "outcome_rates": metrics.outcome_rates(evidence, priors),
        "sensor_vs_spotter": metrics.sensor_vs_spotter(evidence),
        "load_latency": metrics.load_latency(records),
        "calibration": v2.calibration(hold_items),
        "threshold_sweep": v2.threshold_sweep(tune_items, hold_items if holdout else None),
        "staleness": v2.staleness(evidence, priors),
        "positional_error": v2.positional_error(evidence),
    }


def v2_items(priors: dict, evidence: list[dict], tune_evidence: list[dict] | None = None):
    """(items used to find thresholds, items that are reported). Without a hold-out both are the same list."""
    reported = v2.build_items(evidence, priors)
    if tune_evidence is None:
        return reported, reported
    return v2.build_items(tune_evidence, priors), reported


def summary_bytes(summary: dict) -> bytes:
    return (json.dumps(summary, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _cell(c: dict) -> list:
    return [c["k"], c["n"], "" if c["rate"] is None else c["rate"], "" if c["lo"] is None else c["lo"],
            "" if c["hi"] is None else c["hi"]]


def by_type_csv(summary: dict) -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    head = ["type", "lines", "labels"]
    for name in ("confirmed", "contradicted", "unverifiable", "confirm_rate_decisive"):
        head += [f"{name}_k", f"{name}_n", f"{name}_rate", f"{name}_lo", f"{name}_hi"]
    w.writerow(head)
    for t, row in summary["outcome_rates"].items():
        cells = [row["outcomes"][o] for o in metrics.OUTCOMES] + [row["confirm_rate_decisive"]]
        w.writerow([t, row["lines"], row["labels_with_evidence"]] + [x for c in cells for x in _cell(c)])
    return buf.getvalue()


def _pct(c: dict) -> str:
    if c["rate"] is None:
        return f"insufficient data (n={c['n']})"
    return f"{c['rate'] * 100:.0f}% [{c['lo'] * 100:.0f}, {c['hi'] * 100:.0f}] (n={c['n']})"


def report_md(summary: dict) -> str:
    L = []
    if summary["synthetic"]:
        L += ["> **SYNTHETIC. These numbers come from generated test data and say nothing about the real world.**", ""]
    L += ["# Waymark evaluation report", ""]
    inp = summary["inputs"]
    L += [f"Priors: {inp['priors_labels']} labels. Evidence: {inp['evidence_lines']} lines "
          f"({inp['evidence_rejected']} rejected as invalid). Records: {inp['records']}.", ""]
    if summary["holdout"]:
        h = summary["holdout"]
        L += [f"Hold-out: {h['reported_labels']} labels (30%, seed {h['seed']}) are reported here; "
              f"{h['tune_labels']} labels are kept for tuning.", ""]
    L += ["## 1. Outcome rates per label type", "",
          "Wilson 95% intervals in brackets. A rate with fewer than 5 observations is not printed. Several lines can "
          "come from one label, so the intervals are optimistic.", "",
          "| type | lines | confirmed | contradicted | unverifiable | confirm rate (decisive only) |", "|---|---|---|---|---|---|"]
    for t, r in summary["outcome_rates"].items():
        o = r["outcomes"]
        L.append(f"| {t} | {r['lines']} | {_pct(o['confirmed'])} | {_pct(o['contradicted'])} | "
                 f"{_pct(o['unverifiable'])} | {_pct(r['confirm_rate_decisive'])} |")
    L += ["", "## 2. Sensor vs spotter agreement", "",
          "Spotter taps are the reference. Cohen's kappa needs at least 5 labels that have both a spotter and a "
          "sensor verdict.", "", "| sensor | paired labels | agreement | kappa | spotter confirmed: sensor yes / no | "
          "spotter contradicted: sensor yes / no |", "|---|---|---|---|---|---|"]
    for g, s in summary["sensor_vs_spotter"].items():
        m = s["matrix"]
        k = "n/a" if s["kappa"] is None else f"{s['kappa']:.2f}"
        ag = "n/a" if s["agreement"] is None else f"{s['agreement'] * 100:.0f}%"
        L.append(f"| {g} | {s['paired_labels']} | {ag} | {k} | {m['spotter_confirmed']['sensor_confirmed']} / "
                 f"{m['spotter_confirmed']['sensor_contradicted']} | {m['spotter_contradicted']['sensor_confirmed']} / "
                 f"{m['spotter_contradicted']['sensor_contradicted']} |")
    cal = summary["calibration"]
    L += ["", "## 3. Calibration", "", f"{cal['n']} ground-truth passes (a spotter tap with a belief read just before it)."]
    if not cal["assessable"]:
        L += ["", f"**{cal['note']}.**", ""]
    else:
        L += ["", f"Brier score {cal['brier']:.3f} (always predicting the observed prevalence scores {cal['brier_baseline']:.3f}; lower is better).", ""]
    L += ["| p bin | passes | hazard there | mean p | observed |", "|---|---|---|---|---|"]
    for b in cal["bins"]:
        if b["n"]:
            L.append(f"| {b['lo']:.1f} to {b['hi']:.1f} | {b['n']} | {b['truth']} | {b['mean_p']:.2f} | {b['observed']:.2f} |")
    sw = summary["threshold_sweep"]
    L += ["", "## 4. Threshold sweep", "",
          "Alert when p is at least tau. Cost = C_miss x missed hazards + C_fa x false alarms, over spotter-checked passes. "
          "Ties go to the smaller tau.", "",
          "| type | passes | default tau | best tau | cost at default | cost at best | best tau at half / double C_miss |",
          "|---|---|---|---|---|---|---|"]
    for t, r in sw.items():
        if r.get("note"):
            L.append(f"| {t} | {r['n']} | {r['default_tau']:.3f} | {r['note']} | | | |")
        else:
            s2 = r["sensitivity"]
            L.append(f"| {t} | {r['n']} | {r['default_tau']:.3f} | {r['minimizer_tau']:.2f} | {r['cost_at_default']:g} | "
                     f"{r['cost_at_minimizer']:g} | {s2['half_c_miss']:.2f} / {s2['double_c_miss']:.2f} |")
    for t, r in sw.items():
        if r.get("held_out") and r["held_out"].get("n"):
            h = r["held_out"]
            L.append(f"\nHold-out for {t}: {h['n']} passes, cost {h['cost_at_default']:g} at the default tau, {h['cost_at_tuned_tau']:g} at the tuned tau.")
    st = summary["staleness"]
    L += ["", "## 5. Staleness (imagery age vs confirm rate)", "", f"{st['trend'].capitalize()}.", "",
          "| imagery age at the tap | confirm rate (decisive spotter taps) |", "|---|---|"]
    for name, c in st["by_age"].items():
        L.append(f"| {name} | {_pct(c)} |")
    pe = summary["positional_error"]
    L += ["", "## 6. Positional error (along-track metres, confirming events)", ""]
    if not pe:
        L += ["No confirming events with an along-track offset.", ""]
    else:
        L += ["| sensor | n | median | mean | p90 of abs | suggested label_error |", "|---|---|---|---|---|---|"]
        for sname, r in pe.items():
            sug = "needs 20 events" if r["suggested_label_error_m"] is None else f"{r['suggested_label_error_m']} m"
            L.append(f"| {sname} | {r['n']} | {r['median']} | {r['mean']} | {r['p90_abs']} | {sug} |")
    ll = summary["load_latency"]
    L += ["", "## 7. Load and latency (milliseconds)", "", f"{ll['loads']} load records, {ll['cues']} cue records.", "",
          "| measure | n | min | median | p95 | max | note |", "|---|---|---|---|---|---|---|"]
    for name in ("prior_load_ms", "lookup_ms", "fix_to_dispatch_ms"):
        t = ll[name]
        g = lambda k: "" if t.get(k) is None else t[k]
        L.append(f"| {name} | {t['n']} | {g('min')} | {g('median')} | {g('p95')} | {g('max')} | {t.get('note') or ''} |")
    return "\n".join(L) + "\n"


def plot_outcomes(summary: dict, path: Path) -> bool:
    """Bar chart of the decisive confirm rate with Wilson bars. Returns False when no type has enough data."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rows = [(t, r["confirm_rate_decisive"]) for t, r in summary["outcome_rates"].items()
            if t != "all" and r["confirm_rate_decisive"]["rate"] is not None]
    if not rows:
        return False
    fig, ax = plt.subplots(figsize=(7, 4))
    xs = range(len(rows))
    rates = [c["rate"] for _, c in rows]
    ax.bar(xs, rates, yerr=[[c["rate"] - c["lo"] for _, c in rows], [c["hi"] - c["rate"] for _, c in rows]], capsize=4)
    ax.set_xticks(list(xs), [f"{t}\n(n={c['n']})" for t, c in rows], fontsize=8)
    ax.set_ylim(0, 1)
    ax.set_ylabel("confirmed / (confirmed + contradicted)")
    ax.set_title("How often a prior was confirmed when checked")
    if summary["synthetic"]:
        fig.text(0.5, 0.5, "SYNTHETIC", fontsize=60, color="red", alpha=0.25, ha="center", va="center", rotation=25)
    fig.tight_layout()
    fig.savefig(path, dpi=110, metadata={"Software": None})
    plt.close(fig)
    return True


def _watermark(fig, summary):
    if summary["synthetic"]:
        fig.text(0.5, 0.5, "SYNTHETIC", fontsize=60, color="red", alpha=0.25, ha="center", va="center", rotation=25)


def plot_calibration(summary: dict, path: Path) -> bool:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    pts = [(b["mean_p"], b["observed"], b["n"]) for b in summary["calibration"]["bins"] if b["n"]]
    if not pts:
        return False
    fig, ax = plt.subplots(figsize=(5, 5))
    ax.plot([0, 1], [0, 1], "k--", lw=1, label="perfect")
    ax.scatter([p[0] for p in pts], [p[1] for p in pts], s=[20 + 6 * p[2] for p in pts], label="bins (size = passes)")
    ax.set_xlim(0, 1); ax.set_ylim(0, 1)
    ax.set_xlabel("predicted p before the tap"); ax.set_ylabel("observed: hazard was there")
    ax.set_title("Reliability" + ("" if summary["calibration"]["assessable"] else " (too few passes to judge)"))
    ax.legend(loc="upper left", fontsize=8)
    _watermark(fig, summary)
    fig.tight_layout(); fig.savefig(path, dpi=110, metadata={"Software": None}); plt.close(fig)
    return True


def plot_sweep(summary: dict, items: list[dict], path: Path) -> bool:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from . import v2 as V2
    drawn = 0
    fig, ax = plt.subplots(figsize=(7, 4))
    for typ, row in summary["threshold_sweep"].items():
        if row.get("note"):
            continue
        xs = [x for x in items if x["type"] == typ]
        curve = V2.sweep_curve(xs, row["c_miss"], row["c_fa"])
        line, = ax.plot([c["tau"] for c in curve], [c["cost"] for c in curve], label=f"{typ} (n={row['n']})")
        ax.axvline(row["default_tau"], color=line.get_color(), ls=":", lw=1)
        ax.plot([row["minimizer_tau"]], [row["cost_at_minimizer"]], "o", color=line.get_color())
        drawn += 1
    if not drawn:
        plt.close(fig)
        return False
    ax.set_xlabel("tau (dotted = default, dot = best)"); ax.set_ylabel("expected cost")
    ax.set_title("Threshold sweep"); ax.legend(fontsize=8)
    _watermark(fig, summary)
    fig.tight_layout(); fig.savefig(path, dpi=110, metadata={"Software": None}); plt.close(fig)
    return True


def sweep_csv(summary: dict, items: list[dict]) -> str:
    from . import v2 as V2
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(["type", "tau", "alerts", "tp", "fp", "fn", "tn", "cost"])
    for typ, row in summary["threshold_sweep"].items():
        if row.get("note"):
            continue
        for c in V2.sweep_curve([x for x in items if x["type"] == typ], row["c_miss"], row["c_fa"]):
            w.writerow([typ, c["tau"], c["alerts"], c["tp"], c["fp"], c["fn"], c["tn"], f"{c['cost']:g}"])
    return buf.getvalue()


def write_all(summary: dict, out_dir: Path, tune_items: list[dict] | None = None) -> list[str]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "summary.json").write_bytes(summary_bytes(summary))
    (out_dir / "by_type.csv").write_text(by_type_csv(summary), encoding="utf-8")
    (out_dir / "report.md").write_text(report_md(summary), encoding="utf-8")
    files = ["summary.json", "by_type.csv", "report.md"]
    if plot_outcomes(summary, out_dir / "outcome_rates.png"):
        files.append("outcome_rates.png")
    if plot_calibration(summary, out_dir / "calibration.png"):
        files.append("calibration.png")
    if tune_items is not None:
        if plot_sweep(summary, tune_items, out_dir / "threshold_sweep.png"):
            files.append("threshold_sweep.png")
        csv_text = sweep_csv(summary, tune_items)
        if csv_text.count("\n") > 1:
            (out_dir / "threshold_sweep.csv").write_text(csv_text, encoding="utf-8")
            files.append("threshold_sweep.csv")
    return files
