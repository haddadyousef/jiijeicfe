"""P5: rank walking routes by what Waymark has to say about them, and write the demo route files.

Input: Project Sidewalk street edges (GeoJSON LineStrings from `run.py streets`) and the priors bundle.
Street geometry is the street centreline, not the sidewalk, so "within the corridor" means within about
15 m of the centreline. Everything is deterministic: same inputs, same ranking, same bytes.
Labeler ids (`user_ids`) in the street data are never read.
"""
from __future__ import annotations

import heapq
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

LAT0 = 47.655                      # local projection origin (Seattle); good to well under 1 m over a few km
M_PER_DEG_LAT = 110_574.0
M_PER_DEG_LNG = 111_320.0 * math.cos(math.radians(LAT0))
SKIP_WAY_TYPES = {"motorway", "motorway_link", "trunk", "trunk_link"}   # not walkable
HAZARD_TYPES = ("obstacle", "missing_curb_ramp", "no_sidewalk", "surface_problem")   # the types Waymark warns about
CORRIDOR_M = 15.0
NODE_DIGITS = 5                    # about 1 m: street edges meet at shared OSM nodes


def xy(lng: float, lat: float) -> tuple[float, float]:
    return lng * M_PER_DEG_LNG, lat * M_PER_DEG_LAT


def dist_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    """a, b are (lng, lat)."""
    ax, ay = xy(*a)
    bx, by = xy(*b)
    return math.hypot(ax - bx, ay - by)


def polyline_len(pts: list[tuple[float, float]]) -> float:
    return sum(dist_m(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


# ---------- street graph ----------
def load_streets(docs: list[dict]) -> list[dict]:
    """Walkable street edges, one per street_edge_id (sorted). Only geometry and ids are kept."""
    by_id: dict[int, dict] = {}
    for doc in docs:
        for f in doc.get("features", []):
            p, g = f.get("properties") or {}, f.get("geometry") or {}
            eid = p.get("street_edge_id")
            if not isinstance(eid, int) or g.get("type") != "LineString":
                continue
            if str(p.get("way_type", "")).lower() in SKIP_WAY_TYPES:
                continue
            pts = [(float(c[0]), float(c[1])) for c in g.get("coordinates", []) if len(c) >= 2]
            if len(pts) < 2:
                continue
            by_id.setdefault(eid, {"id": eid, "osm_way_id": p.get("osm_way_id"), "way_type": p.get("way_type"),
                                   "coords": pts})
    return [by_id[k] for k in sorted(by_id)]


def _key(pt: tuple[float, float]) -> tuple[float, float]:
    return round(pt[0], NODE_DIGITS), round(pt[1], NODE_DIGITS)


class Graph:
    def __init__(self, edges: list[dict]):
        self.adj: dict[tuple, list[tuple]] = defaultdict(list)   # node -> [(other, length, edge_id, forward)]
        self.edges = {e["id"]: e for e in edges}
        for e in edges:
            a, b = _key(e["coords"][0]), _key(e["coords"][-1])
            if a == b:
                continue
            n = polyline_len(e["coords"])
            self.adj[a].append((b, n, e["id"], True))
            self.adj[b].append((a, n, e["id"], False))
        self.nodes = sorted(self.adj)

    def snap(self, lng: float, lat: float, max_m: float = 80.0) -> tuple | None:
        best, bd = None, max_m
        for n in self.nodes:
            d = dist_m((lng, lat), n)
            if d < bd:
                best, bd = n, d
        return best

    def shortest(self, src: tuple, dst: tuple, penalty: dict[int, float] | None = None) -> list[tuple[float, float]] | None:
        """Dijkstra. `penalty` maps edge id to a multiplier (>= 1) so alternatives can be asked for."""
        penalty = penalty or {}
        best = {src: 0.0}
        prev: dict[tuple, tuple] = {}
        heap = [(0.0, src)]
        while heap:
            d, u = heapq.heappop(heap)
            if u == dst:
                break
            if d > best.get(u, math.inf):
                continue
            for v, n, eid, fwd in self.adj[u]:
                nd = d + n * penalty.get(eid, 1.0)
                if nd < best.get(v, math.inf) - 1e-9:
                    best[v] = nd
                    prev[v] = (u, eid, fwd)
                    heapq.heappush(heap, (nd, v))
        if dst not in best:
            return None
        legs, cur = [], dst
        while cur != src:
            u, eid, fwd = prev[cur]
            legs.append((eid, fwd))
            cur = u
        pts: list[tuple[float, float]] = []
        for eid, fwd in reversed(legs):
            c = self.edges[eid]["coords"]
            c = c if fwd else c[::-1]
            pts += c if not pts else c[1:]
        return pts


# ---------- labels along a route ----------
def project_on(pts: list[tuple[float, float]], lng: float, lat: float) -> tuple[float, float]:
    """(cross-track distance m, along-track distance m from the start) of the nearest point on the polyline."""
    px, py = xy(lng, lat)
    best_d, best_along, run = math.inf, 0.0, 0.0
    for i in range(len(pts) - 1):
        ax, ay = xy(*pts[i]); bx, by = xy(*pts[i + 1])
        dx, dy = bx - ax, by - ay
        seg = math.hypot(dx, dy)
        t = 0.0 if seg == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (seg * seg)))
        d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
        if d < best_d - 1e-9:
            best_d, best_along = d, run + t * seg
        run += seg
    return best_d, best_along


def labels_along(pts: list[tuple[float, float]], labels: list[dict], corridor_m: float = CORRIDOR_M) -> list[dict]:
    """Labels within the corridor, with their cross and along distances, ordered along the route."""
    out = []
    for lab in labels:
        cross, along = project_on(pts, lab["lng"], lab["lat"])
        if cross <= corridor_m:
            out.append({"id": lab["id"], "type": lab["type"], "cross_m": round(cross, 1), "along_m": round(along, 1),
                        "n_agree": lab["n_agree"], "n_disagree": lab["n_disagree"], "severity": lab["severity"],
                        "imagery_date": lab["imagery_date"]})
    out.sort(key=lambda r: (r["along_m"], r["id"]))
    return out


STALE_MIN_ALONG_M = 100.0   # a line needs room to be spoken (trigger distance up to 35 m plus margin) before the label
STALE_END_MARGIN_M = 60.0   # and the walker must still be walking when it is reached


def stale_candidates(found: list[dict], length_m: float | None = None) -> list[dict]:
    """D-31: labels one spotter tap can push below tau, so a demo can show 'the memory learned'.
    tau: surface_problem 1/3, missing_curb_ramp 0.2. One 'not there' tap adds weight 2 to b.
    Needs p after the tap < tau, with a = 1 + n_agree and b = 1 + n_disagree + 2.
    With length_m the label must also sit at least 100 m from the start and 60 m from the end of the route."""
    tau = {"surface_problem": 1 / 3, "missing_curb_ramp": 0.2}
    out = []
    for r in found:
        t = tau.get(r["type"])
        if t is None:
            continue
        a, b = 1 + r["n_agree"], 1 + r["n_disagree"] + 2.0
        if a / (a + b) < t and (length_m is None or r.get("along_m") is None
                                       or STALE_MIN_ALONG_M <= r["along_m"] <= length_m - STALE_END_MARGIN_M):
            out.append(r)
    return out


def score_route(found: list[dict], length_m: float) -> dict:
    """Demo score, higher is a better demo. Explicit so it can be argued with:
    +3 per distinct hazard type present (max 12), +1 per hazard label up to 8, +4 if a D-31 candidate exists,
    +2 per crosswalk up to 3, -(distance outside 500..1000 m)/100, -0.25 per hazard beyond 12 (only 6 are spoken per route, extra labels add noise)."""
    hz = [r for r in found if r["type"] in HAZARD_TYPES]
    types = {r["type"] for r in hz}
    cw = sum(1 for r in found if r["type"] == "crosswalk")
    cand = stale_candidates(found, length_m)
    out_of_range = max(0.0, 500 - length_m, length_m - 1000)
    score = (3 * len(types) + min(len(hz), 8) + (4 if cand else 0) + 2 * min(cw, 3)
             - out_of_range / 100 - 0.25 * max(0, len(hz) - 12))
    return {"score": round(score, 2), "hazard_labels": len(hz), "hazard_types": sorted(types), "crosswalks": cw,
            "stale_candidates": [c["id"] for c in cand], "by_type": dict(sorted(Counter(r["type"] for r in found).items()))}


def _sig(pts: list) -> tuple:
    """Direction-free fingerprint of a path, so a route and its reverse count once."""
    k = max(1, len(pts) // 8)
    f, r = tuple(pts[::k]), tuple(pts[::-1][::k])
    return min(f, r)


def _entry(name: str, a: str, b: str, pts: list, labels: list[dict]) -> dict:
    length = polyline_len(pts)
    found = labels_along(pts, labels)
    return {"name": name, "from": a, "to": b, "length_m": round(length, 1), **score_route(found, length),
            "points": [(round(x, 6), round(y, 6)) for x, y in pts], "labels": found}


def via_routes(graph: Graph, snapped: dict[str, tuple], labels: list[dict], min_m: float, max_m: float,
               max_detour: float = 1.5, snap_m: float = 40.0) -> list[dict]:
    """Routes a -> stale candidate -> b, so the candidate sits in the middle of the walk (D-31). Candidates are
    labels that one spotter tap can push below tau. A route must not be more than max_detour times the direct a-b path."""
    out, names = [], sorted(snapped)
    for cand in stale_candidates([{**l, "along_m": 1e9} for l in labels]):
        c = graph.snap(cand["lng"], cand["lat"], snap_m)
        if c is None:
            continue
        for a in names:
            if snapped[a] == c:
                continue
            leg1 = graph.shortest(snapped[a], c)
            if not leg1:
                continue
            for b in names:
                if b == a or snapped[b] in (c, snapped[a]):
                    continue
                leg2, direct = graph.shortest(c, snapped[b]), graph.shortest(snapped[a], snapped[b])
                if not leg2 or not direct:
                    continue
                pts = leg1 + leg2[1:]
                n = polyline_len(pts)
                if min_m <= n <= max_m and n <= max_detour * polyline_len(direct):
                    out.append(_entry(f"{a} via {cand['id']} to {b}", a, b, pts, labels))
    return out


def rank_routes(graph: Graph, landmarks: dict[str, tuple[float, float]], labels: list[dict],
                min_m: float = 300.0, max_m: float = 1400.0, snap_m: float = 120.0) -> list[dict]:
    """Every ordered pair of landmarks (shortest path), plus routes through stale candidates, scored.
    Sorted by score then name (deterministic). Landmarks farther than snap_m from a street node are dropped."""
    snapped = {}
    for name, (lat, lng) in sorted(landmarks.items()):
        n = graph.snap(lng, lat, snap_m)
        if n is not None:
            snapped[name] = n
    names = sorted(snapped)
    seen, out = set(), []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if snapped[a] == snapped[b]:
                continue
            pts = graph.shortest(snapped[a], snapped[b])
            if not pts:
                continue
            if not (min_m <= polyline_len(pts) <= max_m):
                continue
            sig = _sig(pts)
            if sig in seen:
                continue
            seen.add(sig)
            out.append(_entry(f"{a} to {b}", a, b, pts, labels))
    for r in via_routes(graph, snapped, labels, min_m, max_m):
        sig = _sig([tuple(p) for p in r["points"]])
        if sig not in seen:
            seen.add(sig)
            out.append(r)
    out.sort(key=lambda r: (-r["score"], r["name"]))
    return out
