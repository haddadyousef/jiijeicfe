"""P3 and P4: filter, deduplicate, validate and write the deterministic priors bundle plus a manifest.

Same raw input and same settings give a byte-identical bundle. Budgets: at most 20,000 labels and 3 MB.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from collections import Counter
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Iterable

from .normalize import normalize_feature

_REF = Path(__file__).resolve().parents[2] / "contracts" / "ref"
if str(_REF) not in sys.path:
    sys.path.insert(0, str(_REF))
import validate as contract_validate  # noqa: E402

MAX_LABELS = 20_000
MAX_BYTES = 3 * 1024 * 1024
BASE_URL = "https://sidewalk-sea.cs.washington.edu"
SOURCE = {
    "name": "Project Sidewalk",
    "license": "CC0-1.0",
    "base_url": BASE_URL,
    "street_geometry": "OpenStreetMap contributors, ODbL",
}


class BudgetError(RuntimeError):
    pass


@dataclass(frozen=True)
class Filters:
    """Quality filter settings [H]. Recorded in the manifest. Stricter means fewer, cleaner priors."""
    drop_majority_disagree: bool = True   # drop a cluster whose validators disagreed more than they agreed
    min_cluster_size: int = 1


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def serialize(bundle: dict) -> bytes:
    return (json.dumps(bundle, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def iter_features(raw: Iterable[dict]) -> Iterable[dict]:
    for doc in raw:
        if isinstance(doc, dict) and doc.get("type") == "FeatureCollection":
            yield from doc.get("features", [])


def _prefer(a: dict, b: dict) -> dict:
    """Deterministic choice between two versions of the same cluster seen in overlapping tiles."""
    ka = (a["cluster_size"], a["n_agree"], a["n_agree"] - a["n_disagree"])
    kb = (b["cluster_size"], b["n_agree"], b["n_agree"] - b["n_disagree"])
    return b if kb > ka else a


def build_bundle(raw_docs: list[dict], bbox_lnglat: list[float], generated_at: str,
                 filters: Filters = Filters()) -> tuple[dict, dict]:
    """Return (bundle, stats). Raises BudgetError if the label budget is exceeded."""
    min_lng, min_lat, max_lng, max_lat = bbox_lnglat
    stats: dict[str, Any] = {
        "features_seen": 0, "dropped": Counter(), "unknown_source_types": Counter(),
        "severity_out_of_range": 0, "duplicates_merged": 0,
    }
    by_id: dict[int, dict] = {}
    for feat in iter_features(raw_docs):
        stats["features_seen"] += 1
        label, info = normalize_feature(feat)
        if label is None:
            stats["dropped"][info["drop"]] += 1
            continue
        if "unknown_source_type" in info:
            stats["unknown_source_types"][info["unknown_source_type"]] += 1
        if info.get("severity_out_of_range"):
            stats["severity_out_of_range"] += 1
        if not (min_lng <= label["lng"] <= max_lng and min_lat <= label["lat"] <= max_lat):
            stats["dropped"]["outside_bbox"] += 1
            continue
        cid = label["source_cluster_id"]
        if cid in by_id:
            stats["duplicates_merged"] += 1
            by_id[cid] = _prefer(by_id[cid], label)
        else:
            by_id[cid] = label

    kept: list[dict] = []
    for cid in sorted(by_id):
        lab = by_id[cid]
        if filters.drop_majority_disagree and lab["n_disagree"] > lab["n_agree"]:
            stats["dropped"]["majority_disagree"] += 1
            continue
        if lab["cluster_size"] < filters.min_cluster_size:
            stats["dropped"]["below_min_cluster_size"] += 1
            continue
        kept.append(lab)

    if len(kept) > MAX_LABELS:
        raise BudgetError(f"{len(kept)} labels exceed the {MAX_LABELS} budget; narrow the bbox or tighten the filters")

    bundle = {
        "schema": "waymark.priors.v1",
        "generated_at": generated_at,
        "source": dict(SOURCE),
        "bbox_lnglat": [round(x, 6) for x in bbox_lnglat],
        "labels": kept,
    }
    errors = contract_validate.validate_priors(bundle)
    if errors:
        raise ValueError("bundle failed contract validation: " + "; ".join(errors[:5]))
    payload = serialize(bundle)
    if len(payload) > MAX_BYTES:
        raise BudgetError(f"bundle is {len(payload)} bytes, over the {MAX_BYTES} budget")

    stats["dropped"] = dict(sorted(stats["dropped"].items()))
    stats["unknown_source_types"] = dict(sorted(stats["unknown_source_types"].items()))
    stats["kept"] = len(kept)
    stats["kept_by_type"] = dict(sorted(Counter(l["type"] for l in kept).items()))
    stats["bytes"] = len(payload)
    stats["sha256"] = sha256_bytes(payload)
    km2 = _area_km2(bbox_lnglat)
    stats["bbox_area_km2"] = round(km2, 4)
    stats["labels_per_km2"] = round(len(kept) / km2, 1) if km2 > 0 else None
    edges = Counter(l["street_edge_id"] for l in kept if l["street_edge_id"] is not None)
    stats["street_edges_with_labels"] = len(edges)
    stats["max_labels_on_one_street_edge"] = max(edges.values()) if edges else 0
    return bundle, stats


def _area_km2(bbox: list[float]) -> float:
    min_lng, min_lat, max_lng, max_lat = bbox
    mid = math.radians((min_lat + max_lat) / 2)
    return abs(max_lat - min_lat) * 111.32 * abs(max_lng - min_lng) * 111.32 * math.cos(mid)


def write_outputs(bundle: dict, stats: dict, out_dir: Path, raw_files: list[dict], filters: Filters,
                  extra_copy: Path | None = None) -> dict:
    """Write bundle (compact, deterministic), report.json and manifest.json. Returns the manifest."""
    out_dir.mkdir(parents=True, exist_ok=True)
    payload = serialize(bundle)
    (out_dir / "waymark_priors.json").write_bytes(payload)
    if extra_copy is not None:
        extra_copy.parent.mkdir(parents=True, exist_ok=True)
        extra_copy.write_bytes(payload)
    (out_dir / "report.json").write_text(json.dumps(stats, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    manifest = {
        "schema": "waymark.pipeline_manifest.v1",
        "generated_at": bundle["generated_at"],
        "source": SOURCE,
        "bbox_lnglat": bundle["bbox_lnglat"],
        "filters": asdict(filters),
        "raw_files": raw_files,
        "counts": {"features_seen": stats["features_seen"], "kept": stats["kept"],
                   "kept_by_type": stats["kept_by_type"], "dropped": stats["dropped"],
                   "duplicates_merged": stats["duplicates_merged"],
                   "unknown_source_types": stats["unknown_source_types"]},
        "bundle": {"file": "waymark_priors.json", "bytes": stats["bytes"], "sha256": stats["sha256"]},
        "budgets": {"max_labels": MAX_LABELS, "max_bytes": MAX_BYTES},
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest
