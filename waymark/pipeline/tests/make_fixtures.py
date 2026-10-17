"""Deterministic raw fixtures for pipeline tests. Run: python tests/make_fixtures.py

Feature 13290420 is the real Project Sidewalk cluster verified on 2026-10-17 (CC0) with the labeler id
replaced by an all-zero UUID. Every other feature is SYNTHETIC (ids from 9100000001).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIX = HERE / "fixtures"
sys.path.insert(0, str(HERE.parent))

ZERO_UUID = "00000000-0000-0000-0000-000000000000"
BBOX = [-122.308, 47.652, -122.302, 47.656]
GENERATED_AT = "2026-10-17T21:00:00Z"


def feat(cid, typ, lng, lat, sev=None, agree=0, dis=0, unsure=0, size=1, tags=None, street=None, inter=None, osm=None,
         img="2019-05-01T00:00Z", ldate="2019-07-24T18:34:41.145Z", geometry="point"):
    geom = {"type": "Point", "coordinates": [lng, lat]} if geometry == "point" else None
    return {
        "type": "Feature", "geometry": geom,
        "properties": {
            "label_cluster_id": cid, "label_type": typ, "street_edge_id": street, "intersection_id": inter,
            "osm_way_id": osm, "region_id": 16, "region_name": "University District",
            "avg_image_capture_date": img, "avg_label_date": ldate, "median_severity": sev,
            "agree_count": agree, "disagree_count": dis, "unsure_count": unsure, "cluster_size": size,
            "label_ids": [1, 2], "users": [ZERO_UUID], "tag_counts": tags or {},
        },
    }


def tile_a():
    return {"type": "FeatureCollection", "features": [
        feat(13290420, "CurbRamp", -122.306388855, 47.6522331238, 1, 2, 0, 0, 1, None, 20109, None, 283038445),
        feat(9100000001, "NoCurbRamp", -122.3052, 47.6538, 3, 1, 1, 0, 1, None, 20111, 4001, 283038447),
        feat(9100000002, "Obstacle", -122.3061, 47.6531, 2.0, 2, 0, 0, 2, {"pole": 2, "bench": 1}, 20110, None, 283038446),
        feat(9100000003, "SurfaceProblem", -122.3043, 47.6544, 1.5, 3, 1, 1, 4, {"cracks": 1}, 20112, None, None, "2018-09-01T00:00Z", "2018-10-02T10:00:00.000Z"),
        feat(9100000004, "Crosswalk", -122.3028, 47.6553, None, 4, 0, 0, 3, None, 20113, 4002, 283038448, "2021-04-01T00:00Z", "2021-04-30T00:00:00.000Z"),
        feat(9100000005, "Signal", -122.3050, 47.6540, None, 1, 0, 0, 1),
        feat(9100000006, "Occlusion", -122.3055, 47.6542, None, 1, 0, 0, 1),
        feat(9100000007, "Obstacle", -122.3059, 47.6555, 2, 0, 2, 0, 1),            # majority disagree: dropped
        feat(9100000008, "Obstacle", -122.3047, 47.6529, 2, 1, 0, 0, 1, geometry=None),  # no geometry: dropped
        feat(9100000009, "Obstacle", -122.2000, 47.6540, 2, 1, 0, 0, 1),            # outside bbox: dropped
    ]}


def tile_b():
    return {"type": "FeatureCollection", "features": [
        feat(9100000001, "NoCurbRamp", -122.3052, 47.6538, 3, 2, 1, 0, 2, None, 20111, 4001, 283038447),  # duplicate, larger cluster wins
        feat(9100000010, "NoSidewalk", -122.3034, 47.6550, None, 0, 0, 0, 1, None, None, None, None, None, None),
        feat(9100000011, "Obstacle", -122.3036, 47.6557 - 0.0002, 7, 1, 0, 0, 1),  # severity out of range: becomes null
    ]}


def write():
    FIX.mkdir(parents=True, exist_ok=True)
    for name, doc in (("raw_tile_a.json", tile_a()), ("raw_tile_b.json", tile_b())):
        (FIX / name).write_text(json.dumps(doc, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    from wm_pipeline import bundle as B
    bundle, _ = B.build_bundle([tile_a(), tile_b()], BBOX, GENERATED_AT)
    (FIX / "expected_priors.json").write_bytes(B.serialize(bundle))
    print("fixtures written")


if __name__ == "__main__":
    write()
