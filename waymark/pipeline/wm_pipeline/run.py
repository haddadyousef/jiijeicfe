"""One-command pipeline. From waymark/pipeline:

    py -m wm_pipeline.run all                 # fetch (cached) then build
    py -m wm_pipeline.run fetch --bbox -122.32 47.64 -122.29 47.67
    py -m wm_pipeline.run build --ios-copy ../../ios/CaneKit/Resources/waymark_priors.json

Default bbox is UW campus plus University District, longitude first: minLng minLat maxLng maxLat.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import fetch as F  # stdlib only; bundle (needs jsonschema) is imported lazily in build

HERE = Path(__file__).resolve().parents[1]
DEFAULT_BBOX = [-122.32, 47.64, -122.29, 47.67]


def load_raw(raw_dir: Path) -> tuple[list[dict], list[dict], str | None, list[float] | None]:
    """Return (docs, raw_file_entries, latest fetch time, bbox from fetch manifest)."""
    from . import bundle as B
    fm_path = raw_dir / "fetch_manifest.json"
    if not fm_path.exists():
        raise SystemExit(f"no fetch_manifest.json in {raw_dir}; run the fetch step first")
    fm = json.loads(fm_path.read_text(encoding="utf-8"))
    docs, files, times = [], [], []
    for e in sorted(fm["files"], key=lambda e: e["file"]):
        data = (raw_dir / e["file"]).read_bytes()
        if B.sha256_bytes(data) != e["sha256"]:
            raise SystemExit(f"{e['file']} does not match its recorded sha256; refetch")
        docs.append(json.loads(data))
        files.append({k: e[k] for k in ("file", "url", "bytes", "sha256", "features", "fetched_at")})
        if e.get("fetched_at"):
            times.append(e["fetched_at"])
    return docs, files, (max(times) if times else None), fm.get("bbox_lnglat")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="wm_pipeline.run")
    ap.add_argument("step", choices=["fetch", "streets", "build", "all", "rank", "demo"])
    ap.add_argument("--bbox", nargs=4, type=float, metavar=("MINLNG", "MINLAT", "MAXLNG", "MAXLAT"), default=None)
    ap.add_argument("--raw", type=Path, default=HERE / "data" / "raw")
    ap.add_argument("--out", type=Path, default=HERE / "out")
    ap.add_argument("--step-deg", type=float, default=0.01)
    ap.add_argument("--sleep", type=float, default=1.0)
    ap.add_argument("--generated-at", default=None, help="override the bundle timestamp (default: latest fetch time)")
    ap.add_argument("--priors", type=Path, default=HERE.parents[1] / "ios" / "CaneKit" / "Resources" / "waymark_priors.json")
    ap.add_argument("--demo-out", type=Path, default=HERE.parent / "demo")
    ap.add_argument("--pick", type=int, default=1, help="rank to write demo files for (demo step)")
    ap.add_argument("--ios-copy", type=Path, default=None, help="also write the bundle to this path")
    ap.add_argument("--keep-majority-disagree", action="store_true")
    ap.add_argument("--min-cluster-size", type=int, default=1)
    a = ap.parse_args(argv)

    bbox = a.bbox or DEFAULT_BBOX
    if a.step in ("fetch", "all"):
        F.fetch_all(bbox, a.raw, a.step_deg, a.sleep)
    if a.step == "streets":  # street-edge geometry for route ranking (P5); never read by `build`
        F.fetch_all(bbox, a.raw, a.step_deg, a.sleep, kind="streets")
    if a.step in ("rank", "demo"):
        from . import p5
        graph, labels, ranked = p5.rank(a.raw, a.priors)
        if not ranked:
            raise SystemExit("no candidate routes found")
        files = p5.write_ranking(ranked, a.demo_out)
        if a.step == "demo":
            gen = json.loads(a.priors.read_text(encoding="utf-8"))["generated_at"]
            files += p5.write_pick(ranked, a.pick, labels, a.demo_out, gen)
        print(f"wrote {', '.join(files)} to {a.demo_out}")
    if a.step in ("build", "all"):
        from . import bundle as B
        docs, files, latest, fm_bbox = load_raw(a.raw)
        generated_at = a.generated_at or latest
        if not generated_at:
            raise SystemExit("no fetch time on record; pass --generated-at")
        filters = B.Filters(drop_majority_disagree=not a.keep_majority_disagree, min_cluster_size=a.min_cluster_size)
        bundle, stats = B.build_bundle(docs, a.bbox or fm_bbox or bbox, generated_at, filters)
        manifest = B.write_outputs(bundle, stats, a.out, files, filters, a.ios_copy)
        print(json.dumps({"kept": stats["kept"], "by_type": stats["kept_by_type"], "dropped": stats["dropped"],
                          "bytes": stats["bytes"], "sha256": manifest["bundle"]["sha256"]}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
