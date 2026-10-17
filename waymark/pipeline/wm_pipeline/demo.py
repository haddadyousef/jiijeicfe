"""P5 outputs for one chosen route: route JSON (the app's format, M_NOTES 1.1), replay trace JSON and GPX
(M_NOTES 1.2), and a small SYNTHETIC test priors file aligned to the route for the e2e replay (X-e2e).
Pure functions plus one writer. Deterministic."""
from __future__ import annotations

import json
import math
from pathlib import Path

from .routes import M_PER_DEG_LAT, M_PER_DEG_LNG, dist_m, polyline_len, xy

SYNTH_BASE_ID = 9_000_001_000


def bearing_deg(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Compass bearing a to b, degrees in [0, 360); a, b are (lng, lat)."""
    ax, ay = xy(*a); bx, by = xy(*b)
    return (math.degrees(math.atan2(bx - ax, by - ay)) + 360.0) % 360.0


def ang_diff(a: float, b: float) -> float:
    """Signed smallest turn from bearing a to bearing b, in (-180, 180]; positive is a right turn."""
    d = (b - a + 180.0) % 360.0 - 180.0
    return 180.0 if d == -180.0 else d


def resample(pts: list[tuple[float, float]], step_m: float) -> list[tuple[float, float]]:
    """Points every step_m along the polyline, always including the first and last vertex."""
    total = polyline_len(pts)
    out, s = [], 0.0
    while s < total:
        out.append(point_at(pts, s)[:2])
        s += step_m
    out.append(pts[-1])
    return out


def point_at(pts: list[tuple[float, float]], s: float) -> tuple[float, float, float]:
    """(lng, lat, bearing) at distance s along the polyline (clamped to its ends)."""
    run = 0.0
    for i in range(len(pts) - 1):
        seg = dist_m(pts[i], pts[i + 1])
        if seg > 0 and (s <= run + seg or i == len(pts) - 2):
            t = max(0.0, min(1.0, (s - run) / seg))
            lng = pts[i][0] + t * (pts[i + 1][0] - pts[i][0])
            lat = pts[i][1] + t * (pts[i + 1][1] - pts[i][1])
            return lng, lat, bearing_deg(pts[i], pts[i + 1])
        run += seg
    return pts[0][0], pts[0][1], 0.0


def find_turns(pts: list[tuple[float, float]], min_turn_deg: float = 40.0, spacing_m: float = 40.0) -> list[tuple[float, float]]:
    """(along_m, signed turn degrees) for each real turn, measured over 30 m windows so road curvature is ignored."""
    step = 10.0
    r = resample(pts, step)
    cands = []
    for i in range(3, len(r) - 3):
        d = ang_diff(bearing_deg(r[i - 3], r[i]), bearing_deg(r[i], r[i + 3]))
        if abs(d) >= min_turn_deg:
            cands.append((i * step, d))
    turns: list[tuple[float, float]] = []
    for s, d in sorted(cands, key=lambda c: (-abs(c[1]), c[0])):   # strongest first, keep those far from a kept turn
        if all(abs(s - t) >= spacing_m for t, _ in turns):
            turns.append((s, d))
    return sorted(turns)


def make_route_json(name: str, source: str, pts: list[tuple[float, float]], crosswalks: list[tuple[float, float]],
                    max_gap_m: float = 150.0) -> dict:
    """Waypoints at the start, at each turn, every max_gap_m on long straights, and at the end."""
    total = polyline_len(pts)
    marks: list[tuple[float, str]] = [(0.0, "start")]
    for s, d in find_turns(pts):
        if 20 < s < total - 20:
            marks.append((s, "right" if d > 0 else "left"))
    marks.append((total, "end"))
    marks.sort()
    filled: list[tuple[float, str]] = []
    for s, kind in marks:
        if filled and s - filled[-1][0] > max_gap_m:
            s0, gap = filled[-1][0], s - filled[-1][0]
            k = math.ceil(gap / max_gap_m)
            filled += [(s0 + gap * j / k, "straight") for j in range(1, k)]
        filled.append((s, kind))
    wps = []
    for i, (s, kind) in enumerate(filled, 1):
        lng, lat, brg = point_at(pts, s)
        nxt = point_at(pts, min(total, s + 25.0))
        out_b = bearing_deg((lng, lat), (nxt[0], nxt[1])) if s < total else brg
        say = {"start": "Starting the route. Walk straight ahead.", "straight": "Keep going straight.",
               "left": "Turn left.", "right": "Turn right.", "end": "You have arrived."}[kind]
        near_cw = any(dist_m((lng, lat), c) <= 12.0 for c in crosswalks)
        wps.append({"id": i, "lat": round(lat, 6), "lon": round(lng, 6),
                    "radius_m": 20.0 if kind == "end" else (12.0 if kind in ("left", "right") else 15.0),
                    "say": say, "crossing": bool(near_cw and kind not in ("start", "end")),
                    "bearing_next_deg": None if kind == "end" else round(out_b, 1), "curved": False})
    for w in wps:
        if w["bearing_next_deg"] is None:
            del w["bearing_next_deg"]
    return {"name": name, "source": source, "waypoints": wps}


def make_trace_json(name: str, route_path: str, source: str, pts: list[tuple[float, float]], step_m: float = 5.0) -> dict:
    r = resample(pts, step_m)
    return {"name": name, "route": route_path, "source": source, "length_m": round(polyline_len(pts)),
            "points": [[round(lat, 6), round(lng, 6)] for lng, lat in r]}


def make_gpx(name: str, pts: list[tuple[float, float]], step_m: float = 5.0) -> str:
    r = resample(pts, step_m)
    body = "".join(f'<trkpt lat="{lat:.6f}" lon="{lng:.6f}"/>' for lng, lat in r)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<gpx version="1.1" creator="waymark" '
            'xmlns="http://www.topografix.com/GPX/1.1">\n'
            f'<metadata><name>{name}</name></metadata>\n<trk><name>{name}</name><trkseg>{body}</trkseg></trk>\n</gpx>\n')


# (type, metres along the route, side offset m, n_agree, n_disagree). Synthetic, planted to exercise every rule.
TEST_PLAN = [
    ("surface_problem", 0.10, 4.0, 0, 0),   # the D-31 candidate: one 'not there' tap drops it below tau
    ("obstacle", 0.28, -4.0, 2, 0),
    ("missing_curb_ramp", 0.45, 4.0, 1, 0),
    ("curb_ramp", 0.52, -4.0, 3, 0),
    ("no_sidewalk", 0.70, 4.0, 0, 0),
    ("obstacle", 0.85, -4.0, 1, 0),
]


def make_test_priors(pts: list[tuple[float, float]], generated_at: str, plan=TEST_PLAN) -> dict:
    """SYNTHETIC labels placed at fractions of the route length (never mistaken for real clusters: id >= 9e9)."""
    total = polyline_len(pts)
    labels = []
    for i, (typ, frac, side, na, nd) in enumerate(plan):
        lng, lat, brg = point_at(pts, total * frac)
        rad = math.radians(brg + 90.0)                      # perpendicular to the walking direction
        lng += side * math.sin(rad) / M_PER_DEG_LNG
        lat += side * math.cos(rad) / M_PER_DEG_LAT
        cid = SYNTH_BASE_ID + i
        labels.append({"id": f"ps:{cid}", "type": typ, "lat": round(lat, 6), "lng": round(lng, 6), "severity": 2 if typ != "curb_ramp" else None,
                       "tags": [], "n_agree": na, "n_disagree": nd, "n_unsure": 0, "cluster_size": 1,
                       "street_edge_id": None, "intersection_id": None, "osm_way_id": None,
                       "imagery_date": "2019-06", "label_date": "2019-07", "source_cluster_id": cid})
    lats = [l["lat"] for l in labels]; lngs = [l["lng"] for l in labels]
    bbox = [round(min(lngs) - 0.002, 6), round(min(lats) - 0.002, 6), round(max(lngs) + 0.002, 6), round(max(lats) + 0.002, 6)]
    return {"schema": "waymark.priors.v1", "generated_at": generated_at,
            "source": {"name": "SYNTHETIC test priors (waymark demo)", "license": "CC0-1.0",
                       "base_url": "https://example.invalid", "street_geometry": "none"},
            "bbox_lnglat": bbox, "labels": labels}


def dump(o) -> str:
    return json.dumps(o, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def write_demo(out_dir: Path, name: str, source: str, pts: list[tuple[float, float]], crosswalks: list[tuple[float, float]],
               generated_at: str) -> list[str]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    route = make_route_json(name, source, pts, crosswalks)
    (out_dir / "route.json").write_text(dump(route), encoding="utf-8")
    (out_dir / "route_trace.json").write_text(dump(make_trace_json(name, "waymark/demo/route.json", source, pts)), encoding="utf-8")
    (out_dir / "route.gpx").write_text(make_gpx(name, pts), encoding="utf-8")
    (out_dir / "test_priors.json").write_text(dump(make_test_priors(pts, generated_at)), encoding="utf-8")
    return ["route.json", "route_trace.json", "route.gpx", "test_priors.json"]
