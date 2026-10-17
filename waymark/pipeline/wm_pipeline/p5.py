"""P5 driver: rank candidate routes from the street raw tiles and the priors bundle, then write the demo files.

    py -m wm_pipeline.run rank            # writes demo/route_ranking.md, route_ranking.json, top3.geojson
    py -m wm_pipeline.run demo --pick 1   # writes demo/route.json, route_trace.json, route.gpx, test_priors.json
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from . import demo, routes

# Approximate campus and U District points (lat, lng). They are snapped to the nearest street node within 60 m (the street data has no campus footpaths, so interior points drop out),
# so a few tens of metres of error here does not matter. Picked by hand, not surveyed.
LANDMARKS = {
    "Allen Center": (47.6532, -122.3057), "HUB": (47.6551, -122.3050), "Red Square": (47.6566, -122.3093),
    "Suzzallo Library": (47.6556, -122.3078), "Drumheller Fountain": (47.6537, -122.3078),
    "Husky Stadium": (47.6503, -122.3016), "UW light rail station": (47.6497, -122.3037),
    "U District station": (47.6613, -122.3140), "The Ave and NE 45th": (47.6613, -122.3131),
    "The Ave and NE 42nd": (47.6585, -122.3131), "Burke Museum": (47.6600, -122.3110),
    "The Ave and NE 50th": (47.6650, -122.3128), "UW Medical Center": (47.6498, -122.3070),
}


def load_street_docs(raw_dir: Path) -> list[dict]:
    mf = raw_dir / "fetch_manifest_streets.json"
    if not mf.exists():
        raise SystemExit(f"no fetch_manifest_streets.json in {raw_dir}; run `py -m wm_pipeline.run streets` first")
    docs = []
    for e in sorted(json.loads(mf.read_text(encoding="utf-8"))["files"], key=lambda e: e["file"]):
        data = (raw_dir / e["file"]).read_bytes()
        if hashlib.sha256(data).hexdigest() != e["sha256"]:
            raise SystemExit(f"{e['file']} does not match its recorded sha256; refetch")
        docs.append(json.loads(data))
    return docs


def rank(raw_dir: Path, priors_path: Path, landmarks=LANDMARKS):
    graph = routes.Graph(routes.load_streets(load_street_docs(raw_dir)))
    labels = json.loads(priors_path.read_text(encoding="utf-8"))["labels"]
    return graph, labels, routes.rank_routes(graph, landmarks, labels, snap_m=60.0)


def ranking_md(ranked: list[dict], top: int = 12) -> str:
    L = ["# Demo route ranking (P5)", "",
         "Shortest street path between every pair of landmarks (300 to 1400 m), scored by what the real priors say "
         "within 15 m of the street centreline. Score rule: `routes.score_route`. This is a shortlist; a human walks "
         "and picks (street geometry is the centreline, not the sidewalk, and crossings are not checked).", "",
         "| # | route | length m | score | hazard labels | hazard types | crosswalks | stale candidates (D-31) |",
         "|---|---|---|---|---|---|---|---|"]
    for i, r in enumerate(ranked[:top], 1):
        L.append(f"| {i} | {r['name']} | {r['length_m']:.0f} | {r['score']} | {r['hazard_labels']} | "
                 f"{', '.join(r['hazard_types'])} | {r['crosswalks']} | {len(r['stale_candidates'])} |")
    return "\n".join(L) + "\n"


def top_geojson(ranked: list[dict], n: int = 3) -> dict:
    feats = []
    for i, r in enumerate(ranked[:n], 1):
        feats.append({"type": "Feature", "properties": {"rank": i, "name": r["name"], "length_m": r["length_m"], "score": r["score"]},
                      "geometry": {"type": "LineString", "coordinates": [list(p) for p in r["points"]]}})
    return {"type": "FeatureCollection", "features": feats}


def write_ranking(ranked: list[dict], out_dir: Path) -> list[str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    slim = [{k: v for k, v in r.items() if k != "points" and (k != "labels" or i < 3)} for i, r in enumerate(ranked[:15])]
    (out_dir / "route_ranking.json").write_text(json.dumps(slim, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "route_ranking.md").write_text(ranking_md(ranked), encoding="utf-8")
    (out_dir / "top3.geojson").write_text(json.dumps(top_geojson(ranked), indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return ["route_ranking.json", "route_ranking.md", "top3.geojson"]


def write_pick(ranked: list[dict], pick: int, labels: list[dict], out_dir: Path, generated_at: str) -> list[str]:
    r = ranked[pick - 1]
    pts = [tuple(p) for p in r["points"]]
    crosswalks = [(l["lng"], l["lat"]) for l in labels if l["type"] == "crosswalk"
                  and routes.project_on(pts, l["lng"], l["lat"])[0] <= routes.CORRIDOR_M]
    src = "Project Sidewalk street centrelines (CC0), shortest path between two campus landmarks; ranked by P5"
    return demo.write_demo(out_dir, r["name"], src, pts, crosswalks, generated_at)
