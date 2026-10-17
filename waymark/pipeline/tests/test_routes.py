"""P5 tests on a small synthetic street grid (no real data): graph, corridor, scoring, demo file formats."""
import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "contracts" / "ref"))
from wm_pipeline import demo, routes  # noqa: E402
import validate as V  # noqa: E402

LAT0, LNG0 = 47.650, -122.310
DLAT = 100 / routes.M_PER_DEG_LAT      # 100 m in degrees
DLNG = 100 / routes.M_PER_DEG_LNG


def pt(i, j):  # grid node i east, j north (100 m apart)
    return (round(LNG0 + i * DLNG, 6), round(LAT0 + j * DLAT, 6))


def grid_edges(n=5, skip=()):
    edges, eid = [], 1
    for j in range(n):
        for i in range(n - 1):
            if ((i, j), (i + 1, j)) not in skip:
                edges.append({"type": "Feature", "properties": {"street_edge_id": eid, "osm_way_id": eid, "way_type": "residential", "user_ids": ["SECRET"]},
                              "geometry": {"type": "LineString", "coordinates": [list(pt(i, j)), list(pt(i + 1, j))]}}); eid += 1
    for i in range(n):
        for j in range(n - 1):
            edges.append({"type": "Feature", "properties": {"street_edge_id": eid, "osm_way_id": eid, "way_type": "residential"},
                          "geometry": {"type": "LineString", "coordinates": [list(pt(i, j)), list(pt(i, j + 1))]}}); eid += 1
    return {"type": "FeatureCollection", "features": edges}


def lab(i, typ, lng, lat, na=1, nd=0):
    return {"id": f"ps:{i}", "type": typ, "lat": lat, "lng": lng, "severity": 2, "n_agree": na, "n_disagree": nd,
            "imagery_date": "2019-05"}


def graph(**kw):
    return routes.Graph(routes.load_streets([grid_edges(**kw)]))


def test_load_streets_drops_user_ids_non_walkable_and_duplicates():
    doc = grid_edges()
    doc["features"].append({"type": "Feature", "properties": {"street_edge_id": 999, "way_type": "motorway"},
                            "geometry": {"type": "LineString", "coordinates": [[-122.3, 47.6], [-122.31, 47.6]]}})
    doc["features"].append(doc["features"][0])  # duplicate edge id
    edges = routes.load_streets([doc])
    assert len(edges) == 40 and all("user_ids" not in e for e in edges) and 999 not in {e["id"] for e in edges}


def test_shortest_path_length_and_snap():
    g = graph()
    a, b = g.snap(*pt(0, 0)), g.snap(*pt(3, 2))
    pts = g.shortest(a, b)
    assert routes.polyline_len(pts) == pytest.approx(500, abs=1.0)  # Manhattan 3 + 2 blocks
    assert g.snap(pt(0, 0)[0] + 0.01, pt(0, 0)[1]) is None  # too far from any node


def test_penalty_forces_a_different_route():
    g = graph()
    a, b = g.snap(*pt(0, 0)), g.snap(*pt(2, 0))
    direct = g.shortest(a, b)
    bad = {e["id"]: 10.0 for e in g.edges.values() if e["coords"][0][1] == e["coords"][-1][1] == pt(0, 0)[1]}
    around = g.shortest(a, b, bad)
    assert routes.polyline_len(direct) == pytest.approx(200, abs=1) and routes.polyline_len(around) == pytest.approx(400, abs=1)


def test_unreachable_returns_none():
    edges = routes.load_streets([grid_edges(n=3)])
    g = routes.Graph(edges + [{"id": 5000, "coords": [(-122.2, 47.7), (-122.19, 47.7)], "osm_way_id": 1, "way_type": "x"}])
    assert g.shortest(g.snap(*pt(0, 0)), g.snap(-122.2, 47.7, 1e9)) is None


def test_project_and_corridor_along_and_cross():
    pts = [pt(0, 0), pt(3, 0)]                                    # 300 m east
    lng, lat = pt(1, 0)[0], pt(1, 0)[1] + 10 / routes.M_PER_DEG_LAT   # 10 m north of the 100 m mark
    cross, along = routes.project_on(pts, lng, lat)
    assert cross == pytest.approx(10, abs=0.1) and along == pytest.approx(100, abs=0.5)
    labs = [lab(1, "obstacle", lng, lat), lab(2, "obstacle", lng, lat + 20 / routes.M_PER_DEG_LAT),
            lab(3, "obstacle", pt(2, 0)[0], pt(2, 0)[1] + 5 / routes.M_PER_DEG_LAT)]
    found = routes.labels_along(pts, labs)
    assert [r["id"] for r in found] == ["ps:1", "ps:3"]            # the 20 m one is outside the 15 m corridor, order by along


def test_stale_candidates_follow_the_d31_arithmetic():
    cands = routes.stale_candidates([
        {"id": "a", "type": "surface_problem", "n_agree": 0, "n_disagree": 0},   # 1/4 = 0.25 < 1/3: yes
        {"id": "b", "type": "surface_problem", "n_agree": 1, "n_disagree": 0},   # 2/5 = 0.4: no
        {"id": "c", "type": "missing_curb_ramp", "n_agree": 0, "n_disagree": 0}, # 0.25 > 0.2: no
        {"id": "d", "type": "obstacle", "n_agree": 0, "n_disagree": 0}])         # 0.25 > 1/6: no
    assert [c["id"] for c in cands] == ["a"]


def test_score_route_prefers_variety_candidate_and_good_length():
    base = [{"id": "1", "type": "obstacle", "n_agree": 1, "n_disagree": 0},
            {"id": "2", "type": "missing_curb_ramp", "n_agree": 1, "n_disagree": 0}]
    s1 = routes.score_route(base, 700)
    s2 = routes.score_route(base + [{"id": "3", "type": "surface_problem", "n_agree": 0, "n_disagree": 0}], 700)
    assert s2["score"] > s1["score"] and s2["stale_candidates"] == ["3"]
    assert routes.score_route(base, 700)["score"] > routes.score_route(base, 2000)["score"]


def test_rank_routes_is_deterministic_and_orders_by_score():
    g = graph()
    landmarks = {"A": (LAT0, LNG0), "B": (LAT0 + 3 * DLAT, LNG0 + 2 * DLNG), "C": (LAT0 + 4 * DLAT, LNG0)}
    mid = pt(1, 0)
    labels = [lab(1, "obstacle", mid[0], mid[1] + 5 / routes.M_PER_DEG_LAT),
              lab(2, "surface_problem", mid[0] + 0.0004, mid[1] + 5 / routes.M_PER_DEG_LAT, 0, 0)]
    r1 = routes.rank_routes(g, landmarks, labels, min_m=100, max_m=1000)
    r2 = routes.rank_routes(g, landmarks, labels, min_m=100, max_m=1000)
    assert json.dumps(r1, sort_keys=True) == json.dumps(r2, sort_keys=True)
    assert [r["score"] for r in r1] == sorted((r["score"] for r in r1), reverse=True) and len(r1) >= 3
    assert {r['name'] for r in r1} >= {'A to B', 'A to C', 'B to C'}


# ---- demo files ----
def l_route():
    return [pt(0, 0), pt(3, 0), pt(3, 3)]   # 600 m, one right turn... (east then north is a left turn)


def test_find_turns_ignores_curvature_and_finds_the_corner():
    t = demo.find_turns(l_route())
    assert len(t) == 1 and t[0][0] == pytest.approx(300, abs=10) and t[0][1] == pytest.approx(-90, abs=5)  # left turn
    arc = [(LNG0 + 300 * math.sin(a / 40) / routes.M_PER_DEG_LNG, LAT0 + 300 * (1 - math.cos(a / 40)) / routes.M_PER_DEG_LAT) for a in range(0, 41)]
    assert demo.find_turns(arc) == []


def test_route_json_matches_the_app_format():
    r = demo.make_route_json("Test", "synthetic grid", l_route(), crosswalks=[pt(3, 0)], max_gap_m=150)
    ids = [w["id"] for w in r["waypoints"]]
    assert ids == list(range(1, len(ids) + 1)) and r["waypoints"][-1]["say"] == "You have arrived." and r["waypoints"][-1]["radius_m"] == 20.0
    assert all({"id", "lat", "lon", "radius_m", "say", "crossing"} <= set(w) for w in r["waypoints"])
    assert all("lng" not in w for w in r["waypoints"])
    gaps = [routes.dist_m((a["lon"], a["lat"]), (b["lon"], b["lat"])) for a, b in zip(r["waypoints"], r["waypoints"][1:])]
    assert max(gaps) <= 155
    turn = [w for w in r["waypoints"] if w["crossing"]]
    assert len(turn) == 1 and turn[0]["radius_m"] == 12.0 and "listen for traffic" in turn[0]["say"]   # crosswalk sits on the corner
    assert "bearing_next_deg" not in r["waypoints"][-1]


def test_trace_and_gpx_follow_the_route(tmp_path):
    tr = demo.make_trace_json("T", "waymark/demo/route.json", "synthetic", l_route())
    assert tr["length_m"] == 600 and tr["points"][0] == [round(LAT0, 6), round(LNG0, 6)] and len(tr["points"]) >= 120
    gap = max(routes.dist_m((b[1], b[0]), (a[1], a[0])) for a, b in zip(tr["points"], tr["points"][1:]))
    assert gap <= 5.5
    root = ET.fromstring(demo.make_gpx("T", l_route()))
    ns = {"g": "http://www.topografix.com/GPX/1.1"}
    assert len(root.findall(".//g:trkpt", ns)) == len(tr["points"])


def test_test_priors_validate_and_sit_near_the_route():
    doc = demo.make_test_priors(l_route(), "2026-10-17T22:00:00Z")
    assert V.validate_priors(doc) == []
    assert all(int(l["source_cluster_id"]) >= 9_000_000_000 for l in doc["labels"])
    found = routes.labels_along(l_route(), doc["labels"], 6.0)
    assert len(found) == len(doc["labels"])                                  # every planted label within 6 m of the route
    assert routes.stale_candidates(found)[0]["type"] == "surface_problem"   # exactly the D-31 candidate is planted
    assert len(routes.stale_candidates(found)) == 1


def test_write_demo_is_byte_deterministic(tmp_path):
    a = demo.write_demo(tmp_path / "a", "T", "synthetic", l_route(), [], "2026-10-17T22:00:00Z")
    demo.write_demo(tmp_path / "b", "T", "synthetic", l_route(), [], "2026-10-17T22:00:00Z")
    for n in a:
        assert (tmp_path / "a" / n).read_bytes() == (tmp_path / "b" / n).read_bytes()


def test_rank_and_demo_cli_from_raw_street_tiles(tmp_path):
    import hashlib
    from wm_pipeline import fetch as F
    from wm_pipeline import run as R
    raw = tmp_path / "raw"
    raw.mkdir()
    body = json.dumps(grid_edges(), sort_keys=True).encode()
    name = F.cache_name("u", "streets")
    (raw / name).write_bytes(body)
    (raw / "fetch_manifest_streets.json").write_text(json.dumps({"files": [{"file": name, "sha256": hashlib.sha256(body).hexdigest()}]}))
    g = tmp_path / "priors.json"
    mid = pt(1, 0)
    g.write_text(json.dumps({"schema": "waymark.priors.v1", "generated_at": "2026-10-17T22:00:00Z", "labels": [lab(1, "obstacle", mid[0], mid[1] + 4 / routes.M_PER_DEG_LAT)]}))
    from wm_pipeline import p5
    lm = {"A": (LAT0, LNG0), "B": (LAT0 + 4 * DLAT, LNG0 + 3 * DLNG), "C": (LAT0, LNG0 + 4 * DLNG)}
    graph, labels, ranked = p5.rank(raw, g, lm)
    assert ranked and ranked[0]["hazard_labels"] >= 0
    files = p5.write_ranking(ranked, tmp_path / "demo")
    files += p5.write_pick(ranked, 1, labels, tmp_path / "demo", "2026-10-17T22:00:00Z")
    assert {"route_ranking.md", "top3.geojson", "route.json", "route.gpx", "test_priors.json", "route_trace.json"} <= set(files)
    assert "| 1 |" in (tmp_path / "demo" / "route_ranking.md").read_text()
    bad = tmp_path / "raw2"
    bad.mkdir()
    with pytest.raises(SystemExit):
        p5.load_street_docs(bad)


def test_stale_candidate_needs_room_before_and_after():
    r = {"id": "a", "type": "surface_problem", "n_agree": 0, "n_disagree": 0}
    assert routes.stale_candidates([{**r, "along_m": 50}], 600) == []          # too close to the start to be spoken about
    assert routes.stale_candidates([{**r, "along_m": 560}], 600) == []         # too close to the end
    assert len(routes.stale_candidates([{**r, "along_m": 300}], 600)) == 1
    assert len(routes.stale_candidates([{**r, "along_m": 5}])) == 1            # without a length the old rule applies


def test_via_routes_put_the_candidate_in_the_middle():
    g = graph()
    mid = pt(2, 0)
    labels = [lab(1, "surface_problem", mid[0], mid[1] + 4 / routes.M_PER_DEG_LAT, 0, 0)]
    lm = {"A": (LAT0, LNG0), "B": (LAT0, LNG0 + 4 * DLNG)}
    ranked = routes.rank_routes(g, lm, labels, min_m=100, max_m=1000)
    assert ranked[0]["name"] == "A to B" and ranked[0]["stale_candidates"] == ["ps:1"]     # the plain route already passes it mid-way
    off = [lab(1, "surface_problem", pt(2, 1)[0], pt(2, 1)[1] + 4 / routes.M_PER_DEG_LAT, 0, 0)]
    snapped = {n: g.snap(lng, lat) for n, (lat, lng) in lm.items()}
    via = routes.via_routes(g, snapped, off, 100, 1500, max_detour=2.0)
    assert via and via[0]["stale_candidates"] == ["ps:1"] and via[0]["length_m"] == pytest.approx(600, abs=2)
    assert routes.via_routes(g, snapped, off, 100, 1500, max_detour=1.1) == []      # too much of a detour


def test_crosswalk_mid_block_becomes_its_own_crossing_waypoint():
    pts = [pt(0, 0), pt(3, 0)]
    cw = [(pt(1, 0)[0], pt(1, 0)[1] + 3 / routes.M_PER_DEG_LAT), (pt(1, 0)[0] + 5 / routes.M_PER_DEG_LNG, pt(1, 0)[1])]   # two labels, one crossing
    r = demo.make_route_json("T", "s", pts, cw, max_gap_m=150)
    crossings = [w for w in r["waypoints"] if w["crossing"]]
    assert len(crossings) == 1 and crossings[0]["radius_m"] == 12.0
    assert routes.dist_m((crossings[0]["lon"], crossings[0]["lat"]), pt(1, 0)) < 10
    far = demo.make_route_json("T", "s", pts, [(pt(1, 3)[0], pt(1, 3)[1])], max_gap_m=150)      # 300 m off the route: ignored
    assert not any(w["crossing"] for w in far["waypoints"])
    ends = demo.make_route_json("T", "s", pts, [pt(0, 0)], max_gap_m=150)                        # at the very start: not a crossing waypoint
    assert not any(w["crossing"] for w in ends["waypoints"])
