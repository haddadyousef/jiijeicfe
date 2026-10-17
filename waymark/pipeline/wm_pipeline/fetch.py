"""P1: polite, cached fetch of Project Sidewalk label clusters. Standard library only, so Yousef can run it
natively on Windows (`py -m wm_pipeline.run fetch`) if a sandboxed shell cannot reach the host.

Raw responses are saved byte-exact, keyed by URL, and never committed (pipeline/data/raw/ is git-ignored).
Sequential requests, a User-Agent that names the project, a small delay between requests.
"""
from __future__ import annotations

import hashlib
import json
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE_URL = "https://sidewalk-sea.cs.washington.edu"
USER_AGENT = "waymark-dubhacks26/0.1 (accessibility research prototype; contact: github.com/haddadyousef)"


def tile_bboxes(bbox: list[float], step_deg: float) -> list[list[float]]:
    """Split [minLng, minLat, maxLng, maxLat] into tiles of at most step_deg on a side (row-major, deterministic)."""
    min_lng, min_lat, max_lng, max_lat = bbox
    if step_deg <= 0:
        raise ValueError("step_deg must be positive")
    tiles = []
    lat = min_lat
    while lat < max_lat - 1e-12:
        lat2 = min(lat + step_deg, max_lat)
        lng = min_lng
        while lng < max_lng - 1e-12:
            lng2 = min(lng + step_deg, max_lng)
            tiles.append([round(lng, 6), round(lat, 6), round(lng2, 6), round(lat2, 6)])
            lng = lng2
        lat = lat2
    return tiles


KINDS = ("labelClusters", "streets")  # Project Sidewalk v3 endpoints we read (both GeoJSON FeatureCollections)


def tile_url(tile: list[float], kind: str = "labelClusters") -> str:
    # Same URL shape that was verified on 2026-10-17 (bbox is longitude first, inline=true).
    if kind not in KINDS:
        raise ValueError(f"unknown endpoint {kind!r}")
    return f"{BASE_URL}/v3/api/{kind}?bbox={tile[0]:.6f},{tile[1]:.6f},{tile[2]:.6f},{tile[3]:.6f}&inline=true"


def cache_name(url: str, kind: str = "labelClusters") -> str:
    return f"{kind}_" + hashlib.sha256(url.encode("utf-8")).hexdigest()[:16] + ".json"


def manifest_name(kind: str) -> str:
    """labelClusters keeps its original manifest name; other kinds get their own so `build` never reads them."""
    return "fetch_manifest.json" if kind == "labelClusters" else f"fetch_manifest_{kind}.json"


def fetch_url(url: str, timeout: float = 60.0) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 (fixed https host)
        return resp.read()


def fetch_all(bbox: list[float], raw_dir: Path, step_deg: float = 0.01, sleep_s: float = 1.0,
              fetcher=fetch_url, log=print, kind: str = "labelClusters") -> list[dict]:
    """Fetch every tile not already cached. Returns the fetch manifest entries (also written to raw_dir)."""
    raw_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for i, tile in enumerate(tile_bboxes(bbox, step_deg)):
        url = tile_url(tile, kind)
        path = raw_dir / cache_name(url, kind)
        fetched_at = None
        if not path.exists():
            if i:
                time.sleep(sleep_s)
            data = fetcher(url)
            doc = json.loads(data)  # fail loudly on a non-JSON answer
            if not (isinstance(doc, dict) and doc.get("type") == "FeatureCollection"):
                raise ValueError(f"unexpected response shape for {url}")
            tmp = path.with_suffix(".tmp")
            tmp.write_bytes(data)
            tmp.replace(path)
            fetched_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            log(f"fetched {path.name} ({len(data)} bytes)")
        else:
            log(f"cached  {path.name}")
        data = path.read_bytes()
        entries.append({
            "file": path.name, "url": url, "tile": tile, "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "features": len(json.loads(data).get("features", [])),
            "fetched_at": fetched_at,
        })
    manifest_path = raw_dir / manifest_name(kind)
    previous = {}
    if manifest_path.exists():
        previous = {e["file"]: e for e in json.loads(manifest_path.read_text(encoding="utf-8")).get("files", [])}
    for e in entries:  # keep the original fetch time for cached files
        if e["fetched_at"] is None and e["file"] in previous:
            e["fetched_at"] = previous[e["file"]].get("fetched_at")
    manifest_path.write_text(json.dumps({"schema": "waymark.fetch_manifest.v1", "bbox_lnglat": bbox, "step_deg": step_deg,
                                         "files": entries}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return entries
