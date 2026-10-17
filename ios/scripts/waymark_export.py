#!/usr/bin/env python3
"""Waymark E2 (plan v1.1 board, decision D-14): turn files copied off the phone into the two
committable inputs of the Windows eval harness, with no coordinates in them.

Inputs (AirDrop / Files from the phone's Documents folder):
  --evidence  Documents/waymark/evidence.jsonl  (one `waymark.evidence.v1` line per outcome; E1)
  --log       Documents/canekit-*.jsonl         (trip logs; only `waymark_*` records are kept)

Outputs in --out (the names `waymark/eval/README.md` expects):
  evidence.jsonl          valid `waymark.evidence.v1` lines, de-duplicated, in input order
  waymark_records.jsonl   every `waymark_load` / `waymark_cue` / `waymark_evidence` /
                          `waymark_spotter` record, in input order, with any coordinate-like key removed
  export_report.json      counts (kept, rejected, removed keys) — no data

Rules:
  * Trip logs hold GPS traces; they never enter git (D-14). Only the outputs above do.
  * A key that names a position (lat, lng, lon, latitude, longitude, coordinate(s), location, gps_*
    except gps_acc_m) is removed from records and makes an evidence line invalid. The run then
    re-reads its own output and fails (exit 2) if any such key survived.
  * Evidence lines must parse, carry schema "waymark.evidence.v1", a label_id "ps:<n>", an outcome
    in {confirmed, contradicted, unverifiable} and a known sensor; others are counted as rejected.
  * Same inputs give byte-identical outputs.

Usage:
  python3 ios/scripts/waymark_export.py --evidence evidence.jsonl --log canekit-*.jsonl --out waymark/eval/data/evidence/walk1
  python3 ios/scripts/waymark_export.py --selftest      # dry run on a built-in sample, no files needed

Exit codes: 0 ok, 1 bad arguments or unreadable input, 2 a coordinate survived (should never happen).
Owner: Mac session (ios/**). Consumer: waymark/eval (Windows).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from pathlib import Path

SCHEMA = "waymark.evidence.v1"
OUTCOMES = {"confirmed", "contradicted", "unverifiable"}
SENSORS = {"spotter", "lidar_torso", "lidar_head", "ground", "vision"}
RECORD_KINDS = {"waymark_load", "waymark_cue", "waymark_evidence", "waymark_spotter"}
# Keys that would carry a position. `gps_acc_m` (accuracy, not a position) is allowed.
COORD_KEY = re.compile(r"^(lat|lng|lon|long|latitude|longitude|coord|coords|coordinate|coordinates|"
                       r"location|position|point|geometry|gps_(?!acc_m$).*)$", re.IGNORECASE)
LABEL_ID = re.compile(r"^ps:[0-9]+$")


def coord_keys(obj, prefix: str = "") -> list[str]:
    """Every coordinate-like key in `obj`, recursively, as dotted paths."""
    found: list[str] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            path = f"{prefix}.{k}" if prefix else str(k)
            if COORD_KEY.match(str(k)):
                found.append(path)
            found += coord_keys(v, path)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            found += coord_keys(v, f"{prefix}[{i}]")
    return found


def strip_coords(obj):
    """A copy of `obj` without coordinate-like keys (recursively)."""
    if isinstance(obj, dict):
        return {k: strip_coords(v) for k, v in obj.items() if not COORD_KEY.match(str(k))}
    if isinstance(obj, list):
        return [strip_coords(v) for v in obj]
    return obj


def valid_evidence(obj) -> str | None:
    """None when `obj` is a usable evidence line, else the reason it is not."""
    if not isinstance(obj, dict):
        return "not an object"
    if obj.get("schema") != SCHEMA:
        return "wrong schema"
    if not isinstance(obj.get("label_id"), str) or not LABEL_ID.match(obj["label_id"]):
        return "bad label_id"
    if obj.get("outcome") not in OUTCOMES:
        return "bad outcome"
    if obj.get("sensor") not in SENSORS:
        return "bad sensor"
    if coord_keys(obj):
        return "has a coordinate"
    return None


def read_jsonl(path: Path) -> list[tuple[int, object | None, str]]:
    """(line number, parsed object or None, raw line) for every non-empty line."""
    out = []
    with path.open(encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                out.append((n, json.loads(raw), raw))
            except json.JSONDecodeError:
                out.append((n, None, raw))
    return out


def dumps(obj) -> str:
    """One canonical JSON line (sorted keys, no spaces) so outputs are byte-stable."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def export(evidence_paths: list[Path], log_paths: list[Path], out: Path) -> dict:
    """Writes the three outputs and returns the report."""
    report = {"evidence_in": 0, "evidence_kept": 0, "evidence_duplicates": 0, "evidence_rejected": {},
              "records_in": 0, "records_kept": 0, "record_keys_removed": 0, "unparsable_lines": 0}
    seen: set[str] = set()
    evidence_lines: list[str] = []
    for path in evidence_paths:
        for _, obj, _ in read_jsonl(path):
            report["evidence_in"] += 1
            if obj is None:
                report["unparsable_lines"] += 1
                continue
            reason = valid_evidence(obj)
            if reason:
                report["evidence_rejected"][reason] = report["evidence_rejected"].get(reason, 0) + 1
                continue
            line = dumps(obj)
            if line in seen:
                report["evidence_duplicates"] += 1
                continue
            seen.add(line)
            evidence_lines.append(line)
    record_lines: list[str] = []
    for path in log_paths:
        for _, obj, _ in read_jsonl(path):
            if obj is None:
                report["unparsable_lines"] += 1
                continue
            if not isinstance(obj, dict) or obj.get("kind") not in RECORD_KINDS:
                continue
            report["records_in"] += 1
            removed = coord_keys(obj)
            report["record_keys_removed"] += len(removed)
            record_lines.append(dumps(strip_coords(obj)))
    report["evidence_kept"] = len(evidence_lines)
    report["records_kept"] = len(record_lines)
    out.mkdir(parents=True, exist_ok=True)
    (out / "evidence.jsonl").write_text("".join(l + "\n" for l in evidence_lines), encoding="utf-8")
    (out / "waymark_records.jsonl").write_text("".join(l + "\n" for l in record_lines), encoding="utf-8")
    (out / "export_report.json").write_text(dumps(report) + "\n", encoding="utf-8")
    return report


def verify_no_coordinates(out: Path) -> list[str]:
    """Re-reads the outputs; returns every coordinate-like key found (must be empty)."""
    bad = []
    for name in ("evidence.jsonl", "waymark_records.jsonl", "export_report.json"):
        for n, obj, _ in read_jsonl(out / name):
            bad += [f"{name}:{n}:{k}" for k in coord_keys(obj)]
    return bad


SAMPLE_LOG = [
    {"t": 0.0, "kind": "start", "launch": "normal"},
    {"t": 1.0, "kind": "gps", "lat": 47.658324, "lon": -122.313219, "acc": 5},
    {"t": 1.2, "kind": "waymark_load", "labels": 3405, "load_ms": 141.2, "source": "Project Sidewalk"},
    {"t": 9.0, "kind": "waymark_cue", "label_id": "ps:13292089", "label_type": "obstacle", "p": "0.75",
     "tau": "0.166667", "dist_m": "21.0", "line": "Reported obstacle ahead.", "lookup_ms": 0.4, "latency_ms": 38.0},
    {"t": 9.1, "kind": "speech", "text": "Reported obstacle ahead.", "priority": "scene", "source": "waymark"},
    {"t": 15.0, "kind": "waymark_evidence", "label_id": "ps:13292089", "outcome": "confirmed",
     "sensor": "lidar_torso", "dist_m": 1.6, "along_m": 1.2, "latitude": 47.6, "longitude": -122.3},
    {"t": 20.0, "kind": "waymark_spotter", "action": "tap", "label_id": "ps:13292089", "outcome": "confirmed"},
]
SAMPLE_EVIDENCE = [
    {"schema": SCHEMA, "label_id": "ps:13292089", "outcome": "confirmed", "sensor": "lidar_torso", "dist_m": 1.6,
     "along_m": 1.2, "gps_acc_m": 5.0, "speed_mps": 1.3, "tilt_deg": 5.0, "torso_cover": True,
     "head_cover": False, "build": "waymark 1.0 (1)", "ts": "2026-10-17T23:00:00Z"},
    {"schema": SCHEMA, "label_id": "ps:13292089", "outcome": "confirmed", "sensor": "lidar_torso", "dist_m": 1.6,
     "along_m": 1.2, "gps_acc_m": 5.0, "speed_mps": 1.3, "tilt_deg": 5.0, "torso_cover": True,
     "head_cover": False, "build": "waymark 1.0 (1)", "ts": "2026-10-17T23:00:00Z"},
    {"schema": SCHEMA, "label_id": "ps:1", "outcome": "contradicted", "sensor": "spotter", "dist_m": 4.0,
     "along_m": None, "gps_acc_m": 6.0, "speed_mps": 1.1, "tilt_deg": None, "torso_cover": None,
     "head_cover": None, "build": "waymark 1.0 (1)", "ts": "2026-10-17T23:01:00Z", "lat": 47.6},
    {"schema": "something.else", "label_id": "ps:2"},
]


def selftest() -> int:
    """Dry run on the built-in sample; asserts the D-14 rules. Exit 0 on success."""
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        log = tmpdir / "canekit-sample.jsonl"
        ev = tmpdir / "evidence.jsonl"
        log.write_text("".join(json.dumps(r) + "\n" for r in SAMPLE_LOG) + "not json\n", encoding="utf-8")
        ev.write_text("".join(json.dumps(r) + "\n" for r in SAMPLE_EVIDENCE), encoding="utf-8")
        out = tmpdir / "out"
        report = export([ev], [log], out)
        first = [(out / n).read_bytes() for n in ("evidence.jsonl", "waymark_records.jsonl", "export_report.json")]
        export([ev], [log], out)
        second = [(out / n).read_bytes() for n in ("evidence.jsonl", "waymark_records.jsonl", "export_report.json")]
        checks = {
            "one valid evidence line kept (duplicate dropped)": report["evidence_kept"] == 1 and report["evidence_duplicates"] == 1,
            "a line with a coordinate is rejected": report["evidence_rejected"].get("has a coordinate") == 1,
            "a wrong-schema line is rejected": report["evidence_rejected"].get("wrong schema") == 1,
            "only waymark_* records kept (gps, speech, start dropped)": report["records_kept"] == 4,
            "coordinate keys removed from records": report["record_keys_removed"] == 2,
            "no coordinate in any output": verify_no_coordinates(out) == [],
            "deterministic": first == second,
            "unparsable line counted": report["unparsable_lines"] == 1,
        }
        for name, ok in checks.items():
            print(("ok   " if ok else "FAIL ") + name)
        return 0 if all(checks.values()) else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--evidence", type=Path, nargs="*", default=[], help="evidence.jsonl file(s) from the phone")
    ap.add_argument("--log", type=Path, nargs="*", default=[], help="trip log(s) canekit-*.jsonl from the phone")
    ap.add_argument("--out", type=Path, help="output folder (created)")
    ap.add_argument("--selftest", action="store_true", help="dry run on a built-in sample")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if not a.out or not (a.evidence or a.log):
        ap.error("give --out and at least one --evidence or --log")
    for p in a.evidence + a.log:
        if not p.is_file():
            print(f"not a file: {p}", file=sys.stderr)
            return 1
    report = export(a.evidence, a.log, a.out)
    bad = verify_no_coordinates(a.out)
    print(dumps(report))
    if bad:
        print("COORDINATES FOUND (outputs must not be committed): " + ", ".join(bad), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
