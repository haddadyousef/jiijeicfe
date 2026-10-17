"""P2: normalize one Project Sidewalk labelClusters GeoJSON feature to a waymark.priors.v1 label.

Never invents a field the API did not provide (null instead). The labeler id list (`users`) and the raw
`label_ids` are never copied. See WAYMARK_PLAN 5.2 for the field rules and the type mapping.
"""
from __future__ import annotations

import re
from typing import Any

# Keys are lowercase with spaces, underscores and hyphens removed.
TYPE_MAP = {
    "curbramp": "curb_ramp",
    "nocurbramp": "missing_curb_ramp",
    "surfaceproblem": "surface_problem",
    "obstacle": "obstacle",
    "nosidewalk": "no_sidewalk",
    "crosswalk": "crosswalk",
    "signal": "other",
    "other": "other",
}
KNOWN_SOURCE_TYPES = frozenset(TYPE_MAP)

_MONTH = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])")


def type_key(raw: Any) -> str:
    return re.sub(r"[\s_\-]", "", str(raw)).lower()


def map_type(raw: Any) -> tuple[str, bool]:
    """Return (waymark type, was_unknown_source_type)."""
    key = type_key(raw)
    if key in TYPE_MAP:
        return TYPE_MAP[key], False
    return "other", True


def month(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    m = _MONTH.match(value)
    return f"{m.group(1)}-{m.group(2)}" if m else None


def as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return None


def non_negative(value: Any, default: int) -> int:
    n = as_int(value)
    return default if n is None or n < 0 else n


def severity(value: Any) -> tuple[float | None, bool]:
    """Return (severity or None, was_out_of_range). Stored as the API gives it, at most 2 decimals."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None, False
    if not (1 <= value <= 3):
        return None, True
    return (int(value) if float(value).is_integer() else round(float(value), 2)), False


def normalize_feature(feature: Any) -> tuple[dict | None, dict]:
    """Return (label or None, info). info carries 'drop' (reason string) or flags for the stats."""
    info: dict[str, Any] = {}
    if not isinstance(feature, dict):
        return None, {"drop": "not_a_feature"}
    props = feature.get("properties")
    geom = feature.get("geometry")
    if not isinstance(props, dict):
        return None, {"drop": "no_properties"}
    if not isinstance(geom, dict) or geom.get("type") != "Point":
        return None, {"drop": "no_point_geometry"}
    coords = geom.get("coordinates")
    if not (isinstance(coords, (list, tuple)) and len(coords) >= 2
            and all(isinstance(c, (int, float)) and not isinstance(c, bool) for c in coords[:2])):
        return None, {"drop": "bad_coordinates"}
    lng, lat = float(coords[0]), float(coords[1])
    if not (-180 <= lng <= 180 and -90 <= lat <= 90):
        return None, {"drop": "coordinates_out_of_range"}
    cid = as_int(props.get("label_cluster_id"))
    if cid is None or cid < 0:
        return None, {"drop": "bad_cluster_id"}

    typ, unknown = map_type(props.get("label_type"))
    if unknown:
        info["unknown_source_type"] = str(props.get("label_type"))
    sev, sev_bad = severity(props.get("median_severity"))
    if sev_bad:
        info["severity_out_of_range"] = True

    tag_counts = props.get("tag_counts")
    tags: list[str] = []
    if isinstance(tag_counts, dict):
        tags = sorted({str(k) for k in tag_counts if isinstance(k, str) and k})

    label = {
        "id": f"ps:{cid}",
        "type": typ,
        "lat": round(lat, 6),
        "lng": round(lng, 6),
        "severity": sev,
        "tags": tags,
        "n_agree": non_negative(props.get("agree_count"), 0),
        "n_disagree": non_negative(props.get("disagree_count"), 0),
        "n_unsure": non_negative(props.get("unsure_count"), 0),
        "cluster_size": max(1, non_negative(props.get("cluster_size"), 1)),
        "street_edge_id": as_int(props.get("street_edge_id")),
        "intersection_id": as_int(props.get("intersection_id")),
        "osm_way_id": as_int(props.get("osm_way_id")),
        "imagery_date": month(props.get("avg_image_capture_date")),
        "label_date": month(props.get("avg_label_date")),
        "source_cluster_id": cid,
    }
    return label, info
