"""Validators for the Waymark contracts: JSON Schema plus the semantic rules the schema cannot express."""
from __future__ import annotations

import json
from decimal import Decimal
from pathlib import Path

from jsonschema import Draft202012Validator

CONTRACTS = Path(__file__).resolve().parent.parent
KNOWN_TYPES = (
    "curb_ramp", "missing_curb_ramp", "obstacle", "surface_problem",
    "no_sidewalk", "crosswalk", "other",
)

_priors_validator = Draft202012Validator(json.loads((CONTRACTS / "priors_v1.schema.json").read_text(encoding="utf-8")))
_evidence_validator = Draft202012Validator(json.loads((CONTRACTS / "evidence_v1.schema.json").read_text(encoding="utf-8")))


def _decimals(raw: str) -> int:
    d = Decimal(raw)
    exp = d.as_tuple().exponent
    return max(0, -exp) if isinstance(exp, int) else 0


def validate_priors(doc: object, *, allow_unknown_types: bool = False) -> list[str]:
    """Return a list of error strings; empty means valid."""
    errors = [f"schema: {'/'.join(map(str, e.absolute_path))}: {e.message}" for e in _priors_validator.iter_errors(doc)]
    if errors or not isinstance(doc, dict):
        return errors
    box = doc["bbox_lnglat"]
    if not (box[0] < box[2] and box[1] < box[3]):
        errors.append("semantic: bbox_lnglat must be [minLng, minLat, maxLng, maxLat] with min < max")
    last = None
    seen: set[str] = set()
    for i, lab in enumerate(doc["labels"]):
        where = f"labels[{i}] {lab['id']}"
        if lab["id"] in seen:
            errors.append(f"semantic: {where}: duplicate id")
        seen.add(lab["id"])
        if lab["id"] != f"ps:{lab['source_cluster_id']}":
            errors.append(f"semantic: {where}: id does not equal 'ps:' + source_cluster_id")
        if last is not None and lab["source_cluster_id"] <= last:
            errors.append(f"semantic: {where}: labels must be sorted ascending by source_cluster_id")
        last = lab["source_cluster_id"]
        if not allow_unknown_types and lab["type"] not in KNOWN_TYPES:
            errors.append(f"semantic: {where}: unknown type {lab['type']!r} (producer must map to 'other')")
        for key in ("lat", "lng"):
            if _decimals(repr(lab[key])) > 6:
                errors.append(f"semantic: {where}: {key} has more than 6 decimals")
        if lab["tags"] != sorted(lab["tags"]):
            errors.append(f"semantic: {where}: tags must be sorted")
    return errors


def validate_evidence_line(obj: object) -> list[str]:
    return [f"schema: {'/'.join(map(str, e.absolute_path))}: {e.message}" for e in _evidence_validator.iter_errors(obj)]
