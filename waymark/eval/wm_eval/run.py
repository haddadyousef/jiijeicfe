"""CLI. From waymark/eval:

    py -m wm_eval.run --priors P.json --evidence E.jsonl [--records R.jsonl] --out out/ [--holdout]
    py -m wm_eval.run --synthetic --out out/synthetic      # generate seeded fake walks, then report (watermarked)
"""
from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

from . import loader, report, synth


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wm_eval.run")
    ap.add_argument("--priors", type=Path)
    ap.add_argument("--evidence", type=Path, nargs="+", default=[])
    ap.add_argument("--records", type=Path, nargs="*", default=[])
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--holdout", action="store_true", help="report only the 30%% hold-out labels (seeded)")
    ap.add_argument("--seed", type=int, default=26)
    ap.add_argument("--synthetic", action="store_true", help="generate fake data with --seed and report it")
    ap.add_argument("--allow-rejected", action="store_true", help="exit 0 even if evidence lines were invalid")
    a = ap.parse_args(argv)

    if a.synthetic:
        d = Path(tempfile.mkdtemp(prefix="wm_synth_"))
        synth.write(d, a.seed)
        a.priors, a.evidence, a.records = d / "priors.json", [d / "evidence.jsonl"], [d / "records.jsonl"]
    if not a.priors or not a.evidence:
        ap.error("--priors and --evidence are required unless --synthetic")

    priors = loader.load_priors(a.priors)
    evidence, rejected = loader.load_evidence(a.evidence)
    records, skipped = loader.load_records(a.records)
    summary = report.build_summary(priors, evidence, records, rejected=len(rejected), skipped_records=skipped,
                                   holdout=a.holdout, seed=a.seed,
                                   synthetic=report.is_synthetic(evidence, a.synthetic))
    tune_ev = None
    if a.holdout:
        from .stats import holdout_split
        _, hold = holdout_split([e["label_id"] for e in evidence], 0.3, a.seed)
        tune_ev = [e for e in evidence if e["label_id"] not in set(hold)]
    tune_items, _ = report.v2_items(priors, [e for e in evidence if not a.holdout or e["label_id"] in set(hold)], tune_ev)
    files = report.write_all(summary, a.out, tune_items)
    print(f"wrote {', '.join(files)} to {a.out}" + ("  [SYNTHETIC]" if summary["synthetic"] else ""))
    for r in rejected[:5]:
        print(f"rejected {r['file']}:{r['line']}: {'; '.join(r['errors'])}", file=sys.stderr)
    return 1 if rejected and not a.allow_rejected else 0


if __name__ == "__main__":
    sys.exit(main())
