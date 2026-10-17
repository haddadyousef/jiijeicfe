"""Read priors, evidence lines and exported trip-log records. Nothing here ever reads walker coordinates:
evidence lines have none (contract), and only `waymark_*` records are accepted from a trip-log export (D-14)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

_REF = Path(__file__).resolve().parents[2] / "contracts" / "ref"
if str(_REF) not in sys.path:
    sys.path.insert(0, str(_REF))
import validate as contract_validate  # noqa: E402


def load_priors(path: Path) -> dict[str, dict]:
    doc = json.loads(Path(path).read_text(encoding="utf-8"))
    errors = contract_validate.validate_priors(doc, allow_unknown_types=True)
    if errors:
        raise ValueError(f"{path}: priors failed contract validation: " + "; ".join(errors[:3]))
    return {lab["id"]: lab for lab in doc["labels"]}


def load_evidence(paths: list[Path]) -> tuple[list[dict], list[dict]]:
    """Return (valid lines sorted deterministically, rejected [{file, line, errors}])."""
    good, bad = [], []
    for p in paths:
        for i, raw in enumerate(Path(p).read_text(encoding="utf-8").splitlines(), 1):
            if not raw.strip():
                continue
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError as e:
                bad.append({"file": Path(p).name, "line": i, "errors": [f"json: {e.msg}"]})
                continue
            errs = contract_validate.validate_evidence_line(obj)
            if errs:
                bad.append({"file": Path(p).name, "line": i, "errors": errs[:3]})
            else:
                good.append(obj)
    good.sort(key=lambda o: (o["ts"], o["label_id"], o["sensor"], o["outcome"], o["build"]))
    return good, bad


def _num(v):
    """Trip-log payloads are string maps; accept numbers or numeric strings."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v)
        except ValueError:
            return None
    return None


def load_records(paths: list[Path]) -> tuple[list[dict], int]:
    """Return (waymark_* records in file order, count of lines skipped as unreadable).
    Records are plain dicts with the numeric fields coerced where present."""
    out, skipped = [], 0
    for p in paths:
        for raw in Path(p).read_text(encoding="utf-8").splitlines():
            if not raw.strip():
                continue
            try:
                r = json.loads(raw)
            except json.JSONDecodeError:
                skipped += 1
                continue
            if not isinstance(r, dict) or not str(r.get("kind", "")).startswith("waymark_"):
                continue
            rec = dict(r)
            for key in ("load_ms", "lookup_ms", "latency_ms", "count", "bytes", "p", "tau", "dist_m", "t"):
                if key in rec:
                    rec[key] = _num(rec[key])
            out.append(rec)
    return out, skipped
