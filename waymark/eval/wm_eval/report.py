"""Assemble summary.json, by_type.csv, report.md and the outcome plot. Same inputs give identical summary.json bytes."""
from __future__ import annotations

import csv
import io
import json
from pathlib import Path

from . import metrics
from .stats import holdout_split

SYNTH_PREFIX = "waymark-synthetic"


def is_synthetic(evidence: list[dict], forced: bool = False) -> bool:
    """Watermark rule: any synthetic-build evidence line taints the whole report."""
    return forced or any(e["build"].startswith(SYNTH_PREFIX) for e in evidence)


def build_summary(priors: dict, evidence: list[dict], records: list[dict], *, rejected: int = 0,
                  skipped_records: int = 0, holdout: bool = False, seed: int = 26, synthetic: bool = False) -> dict:
    split = None
    if holdout:
        tune, hold = holdout_split([e["label_id"] for e in evidence], 0.3, seed)
        keep = set(hold)
        split = {"seed": seed, "fraction": 0.3, "tune_labels": len(tune), "reported_labels": len(hold)}
        evidence = [e for e in evidence if e["label_id"] in keep]
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
    }


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


def write_all(summary: dict, out_dir: Path) -> list[str]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "summary.json").write_bytes(summary_bytes(summary))
    (out_dir / "by_type.csv").write_text(by_type_csv(summary), encoding="utf-8")
    (out_dir / "report.md").write_text(report_md(summary), encoding="utf-8")
    files = ["summary.json", "by_type.csv", "report.md"]
    if plot_outcomes(summary, out_dir / "outcome_rates.png"):
        files.append("outcome_rates.png")
    return files
