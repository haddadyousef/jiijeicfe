import json
import random
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import make_fixtures as MF  # noqa: E402
from wm_pipeline import bundle as B  # noqa: E402
from wm_pipeline import fetch as F  # noqa: E402
from wm_pipeline import normalize as N  # noqa: E402
from wm_pipeline import run as R  # noqa: E402

FIX = HERE / "fixtures"
CONTRACT_GOLDEN = HERE.parents[1] / "contracts" / "golden"


def docs():
    return [json.loads((FIX / "raw_tile_a.json").read_text()), json.loads((FIX / "raw_tile_b.json").read_text())]


def build(ds=None, **kw):
    return B.build_bundle(ds or docs(), MF.BBOX, MF.GENERATED_AT, **kw)


# ---------- normalize ----------

def test_real_feature_matches_contract_golden_label():
    feature = docs()[0]["features"][0]
    label, info = N.normalize_feature(feature)
    golden = json.loads((CONTRACT_GOLDEN / "priors_sample.json").read_text())["labels"][0]
    assert label == golden and info == {}


def test_type_mapping_and_unknowns():
    cases = {"CurbRamp": "curb_ramp", "NoCurbRamp": "missing_curb_ramp", "SurfaceProblem": "surface_problem",
             "Obstacle": "obstacle", "NoSidewalk": "no_sidewalk", "Crosswalk": "crosswalk", "Signal": "other", "Other": "other",
             "curb_ramp": "curb_ramp", "NO-CURB-RAMP": "missing_curb_ramp"}
    for raw, want in cases.items():
        assert N.map_type(raw) == (want, False), raw
    assert N.map_type("Occlusion") == ("other", True)
    assert N.map_type(None) == ("other", True)


def test_labeler_ids_and_label_ids_never_copied():
    bundle, _ = build()
    text = json.dumps(bundle)
    assert "users" not in text and "label_ids" not in text and MF.ZERO_UUID not in text


def test_severity_rules():
    assert N.severity(2.0) == (2, False)
    assert N.severity(1.5) == (1.5, False)
    assert N.severity(1.234) == (1.23, False)
    assert N.severity(7) == (None, True)
    assert N.severity(None) == (None, False)
    assert N.severity("2") == (None, False)


def test_dates_and_tags_and_nulls():
    assert N.month("2019-05-01T00:00Z") == "2019-05"
    assert N.month("2019-13-01") is None and N.month(None) is None
    label, _ = N.normalize_feature(MF.feat(5, "Obstacle", -122.3, 47.65, None, tags={"b": 1, "a": 2, "": 1}))
    assert label["tags"] == ["a", "b"]
    assert label["street_edge_id"] is None and label["osm_way_id"] is None


@pytest.mark.parametrize("feature,reason", [
    ({"type": "Feature", "geometry": None, "properties": {}}, "no_point_geometry"),
    ({"type": "Feature", "geometry": {"type": "LineString", "coordinates": []}, "properties": {}}, "no_point_geometry"),
    ({"type": "Feature", "geometry": {"type": "Point", "coordinates": ["a", 1]}, "properties": {}}, "bad_coordinates"),
    ({"type": "Feature", "geometry": {"type": "Point", "coordinates": [500, 1]}, "properties": {}}, "coordinates_out_of_range"),
    ({"type": "Feature", "geometry": {"type": "Point", "coordinates": [1, 1]}, "properties": {"label_cluster_id": "x"}}, "bad_cluster_id"),
    ("nonsense", "not_a_feature"),
    ({"type": "Feature", "geometry": {"type": "Point", "coordinates": [1, 1]}}, "no_properties"),
])
def test_bad_features_are_dropped_with_reason(feature, reason):
    label, info = N.normalize_feature(feature)
    assert label is None and info["drop"] == reason


# ---------- build ----------

def test_build_counts_and_contents():
    bundle, stats = build()
    ids = [l["source_cluster_id"] for l in bundle["labels"]]
    assert ids == sorted(ids) and len(ids) == 9
    assert stats["features_seen"] == 13
    assert stats["dropped"] == {"majority_disagree": 1, "no_point_geometry": 1, "outside_bbox": 1}
    assert stats["duplicates_merged"] == 1
    assert stats["unknown_source_types"] == {"Occlusion": 1}
    assert stats["severity_out_of_range"] == 1
    assert stats["kept_by_type"] == {"crosswalk": 1, "curb_ramp": 1, "missing_curb_ramp": 1, "no_sidewalk": 1,
                                     "obstacle": 2, "other": 2, "surface_problem": 1}
    dup = next(l for l in bundle["labels"] if l["id"] == "ps:9100000001")
    assert dup["cluster_size"] == 2 and dup["n_agree"] == 2  # larger cluster wins


def test_golden_raw_in_golden_bundle_out():
    bundle, _ = build()
    assert B.serialize(bundle) == (FIX / "expected_priors.json").read_bytes()


def test_determinism_and_order_independence():
    a, _ = build()
    b, _ = build()
    assert B.serialize(a) == B.serialize(b)
    ds = docs()
    rnd = random.Random(7)
    for d in ds:
        rnd.shuffle(d["features"])
    shuffled, _ = build(ds[::-1])
    assert B.serialize(shuffled) == B.serialize(a)


def test_filters_can_be_relaxed():
    bundle, stats = build(filters=B.Filters(drop_majority_disagree=False))
    assert stats["kept"] == 10 and "majority_disagree" not in stats["dropped"]
    bundle, stats = build(filters=B.Filters(min_cluster_size=2))
    assert all(l["cluster_size"] >= 2 for l in bundle["labels"])


def test_label_budget_enforced():
    feats = [MF.feat(i, "Obstacle", -122.3 + (i % 100) * 1e-6, 47.65 + (i // 100) * 1e-6, 2, 1) for i in range(B.MAX_LABELS + 1)]
    with pytest.raises(B.BudgetError):
        B.build_bundle([{"type": "FeatureCollection", "features": feats}], [-122.31, 47.64, -122.29, 47.66], MF.GENERATED_AT)


def test_byte_budget_enforced(monkeypatch):
    monkeypatch.setattr(B, "MAX_BYTES", 100)
    with pytest.raises(B.BudgetError):
        build()


def test_bundle_passes_contract_validation():
    bundle, _ = build()
    assert B.contract_validate.validate_priors(bundle) == []


# ---------- fetch ----------

def test_tiles_cover_the_bbox_exactly():
    tiles = F.tile_bboxes([-122.32, 47.64, -122.29, 47.67], 0.01)
    assert len(tiles) == 9
    assert min(t[0] for t in tiles) == -122.32 and max(t[2] for t in tiles) == -122.29
    assert min(t[1] for t in tiles) == 47.64 and max(t[3] for t in tiles) == 47.67
    area = sum((t[2] - t[0]) * (t[3] - t[1]) for t in tiles)
    assert abs(area - 0.03 * 0.03) < 1e-9
    assert F.tile_bboxes([0, 0, 0.025, 0.01], 0.01)[-1] == [0.02, 0.0, 0.025, 0.01]
    with pytest.raises(ValueError):
        F.tile_bboxes([0, 0, 1, 1], 0)


def test_url_shape_matches_the_verified_request():
    url = F.tile_url([-122.308, 47.652, -122.302, 47.656])
    assert url == "https://sidewalk-sea.cs.washington.edu/v3/api/labelClusters?bbox=-122.308000,47.652000,-122.302000,47.656000&inline=true"
    assert "waymark" in F.USER_AGENT


def make_fake(calls):
    served = {0: (FIX / "raw_tile_a.json").read_bytes(), 1: (FIX / "raw_tile_b.json").read_bytes()}

    def fake(url):
        calls.append(url)
        return served[len(calls) - 1]
    return fake


def test_fetch_caches_and_records_hashes(tmp_path):
    calls = []
    entries = F.fetch_all(MF.BBOX, tmp_path / "raw", 0.004, 0, make_fake(calls), log=lambda *_: None)
    assert len(entries) == 2 and len(calls) == 2
    again = F.fetch_all(MF.BBOX, tmp_path / "raw", 0.004, 0, make_fake([]), log=lambda *_: None)  # must not call the fetcher
    assert [e["sha256"] for e in again] == [e["sha256"] for e in entries]
    assert all(e["fetched_at"] for e in again)  # original fetch time is kept for cached files
    for e in entries:
        assert (tmp_path / "raw" / e["file"]).read_bytes()  # byte-exact on disk


def test_fetch_rejects_non_geojson(tmp_path):
    with pytest.raises(ValueError):
        F.fetch_all(MF.BBOX, tmp_path / "raw", 0.01, 0, lambda url: b'{"hello": 1}', log=lambda *_: None)
    with pytest.raises(json.JSONDecodeError):
        F.fetch_all(MF.BBOX, tmp_path / "raw2", 0.01, 0, lambda url: b"<html>", log=lambda *_: None)


# ---------- end to end through the CLI ----------

def test_cli_build_is_reproducible_and_manifest_is_honest(tmp_path):
    F.fetch_all(MF.BBOX, tmp_path / "raw", 0.004, 0, make_fake([]), log=lambda *_: None)
    out1, out2 = tmp_path / "o1", tmp_path / "o2"
    ios = tmp_path / "ios" / "waymark_priors.json"
    assert R.main(["build", "--raw", str(tmp_path / "raw"), "--out", str(out1), "--ios-copy", str(ios)]) == 0
    assert R.main(["build", "--raw", str(tmp_path / "raw"), "--out", str(out2)]) == 0
    b1, b2 = (out1 / "waymark_priors.json").read_bytes(), (out2 / "waymark_priors.json").read_bytes()
    assert b1 == b2 == ios.read_bytes()
    manifest = json.loads((out1 / "manifest.json").read_text())
    assert manifest["bundle"]["sha256"] == B.sha256_bytes(b1) and manifest["bundle"]["bytes"] == len(b1)
    assert len(manifest["raw_files"]) == 2 and all(len(f["sha256"]) == 64 for f in manifest["raw_files"])
    assert manifest["counts"]["kept"] == 9 and manifest["filters"]["drop_majority_disagree"] is True
    assert json.loads(b1)["generated_at"] == max(f["fetched_at"] for f in manifest["raw_files"])


def test_cli_refuses_tampered_raw_file(tmp_path):
    F.fetch_all(MF.BBOX, tmp_path / "raw", 0.004, 0, make_fake([]), log=lambda *_: None)
    victim = next((tmp_path / "raw").glob("labelClusters_*.json"))
    victim.write_bytes(victim.read_bytes() + b" ")
    with pytest.raises(SystemExit):
        R.main(["build", "--raw", str(tmp_path / "raw"), "--out", str(tmp_path / "o")])


def test_streets_kind_uses_its_own_url_cache_prefix_and_manifest(tmp_path):
    tile = [-122.308, 47.652, -122.302, 47.656]
    assert "/v3/api/streets?bbox=-122.308000,47.652000,-122.302000,47.656000" in F.tile_url(tile, "streets")
    with pytest.raises(ValueError):
        F.tile_url(tile, "users")
    body = json.dumps({"type": "FeatureCollection", "features": []}).encode()
    F.fetch_all([-122.308, 47.652, -122.302, 47.656], tmp_path, 0.01, 0, lambda url: body, log=lambda *_: None, kind="streets")
    names = sorted(p.name for p in tmp_path.iterdir())
    assert any(n.startswith("streets_") for n in names) and "fetch_manifest_streets.json" in names
    assert "fetch_manifest.json" not in names  # `build` reads only the labelClusters manifest
