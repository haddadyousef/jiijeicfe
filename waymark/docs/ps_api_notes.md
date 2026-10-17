# Project Sidewalk (Seattle) API notes

Owner: Windows session. Status: P0 mostly done (2026-10-17 15:05 PT). Real tiles fetched natively by Yousef; byte-exact files are local and git-ignored, their SHA-256 is in `pipeline/out/manifest.json`. Still open: `streets`/`regions` (needed for P5).

## Server and endpoint

- Server: `https://sidewalk-sea.cs.washington.edu`
- Endpoint used: `GET /v3/api/labelClusters` (no API key needed)
- Sample request: `?bbox=-122.3080,47.6520,-122.3020,47.6560&inline=true`
- `bbox` order is longitude first: `minLng,minLat,maxLng,maxLat`
- Other documented parameters: `regionId`, `regionName`, `labelType` (comma list), `includeRawLabels`, `clusterSize`, `avgImageCaptureDate`, `avgLabelDate`, `minSeverity`, `maxSeverity` (1 to 3), `filetype` (`geojson`, `csv`, `shapefile`, `geopackage`), `inline`
- v3 API is described by Project Sidewalk as a preview, so shapes can change. The app never depends on the live API; it ships a bundle.

## Response shape (GeoJSON `Point` features)

Properties (17 without `includeRawLabels`): `label_cluster_id, label_type, street_edge_id, intersection_id, osm_way_id, region_id, region_name, avg_image_capture_date, avg_label_date, median_severity, agree_count, disagree_count, unsure_count, cluster_size, label_ids, users, tag_counts`. With `includeRawLabels=true` a `labels` array is added.

`users` contains labeler UUIDs. Drop it. It never enters the bundle, fixtures or docs.

## Label types seen

`CurbRamp, NoCurbRamp, Crosswalk, SurfaceProblem, Obstacle, Signal, NoSidewalk, Other`. Mapping to our open enum: see WAYMARK_PLAN 5.2.

## Sample statistics (sample box above)

66 clusters: CurbRamp 37, SurfaceProblem 10, NoCurbRamp 9, Obstacle 8, Crosswalk 1, Other 1. Imagery dates in the first features are 2019-05, label dates 2019-07. Roughly 330 clusters per square kilometre in this box.

## One real feature (CC0; labeler id removed)

```json
{"type":"Feature","geometry":{"type":"Point","coordinates":[-122.306388855,47.6522331238]},"properties":{"label_cluster_id":13290420,"label_type":"CurbRamp","street_edge_id":20109,"intersection_id":null,"osm_way_id":283038445,"region_id":16,"region_name":"University District","avg_image_capture_date":"2019-05-01T00:00Z","avg_label_date":"2019-07-24T18:34:41.145Z","median_severity":1,"agree_count":2,"disagree_count":0,"unsure_count":0,"cluster_size":1,"label_ids":[77288],"tag_counts":{}}}
```

## Real fetch, 2026-10-17 (P0 results)

Bbox `[-122.32, 47.64, -122.29, 47.67]` (UW campus plus University District, about 7.5 km²), 9 tiles of 0.01°, one request per second, User-Agent naming the project. All 9 answered HTTP 200 with a GeoJSON `FeatureCollection`; no throttling or errors at that pace. 3,415 features total.

| raw file (local, git-ignored) | features | bytes | sha256 (first 16) |
|---|---|---|---|
| `labelClusters_050154ebb6a6f8a1.json` | 433 | 246316 | `3746a8a4f6ec4041…` |
| `labelClusters_1b93aa291b0147a4.json` | 12 | 6955 | `1fd910d1f75d3532…` |
| `labelClusters_393ff0125007575e.json` | 651 | 392564 | `f9da957c721d0535…` |
| `labelClusters_54e4c8f344d8e8e2.json` | 71 | 41699 | `fcf1b0ff6b43594a…` |
| `labelClusters_57084313473a38a9.json` | 421 | 248088 | `e9e4bc1f0d50cad3…` |
| `labelClusters_6fdbf3a24db1cfdc.json` | 279 | 160129 | `82bc1bb0cda90033…` |
| `labelClusters_b47537cdfe1d330f.json` | 578 | 343867 | `fb85a5e9651183fa…` |
| `labelClusters_c31a387ee717bded.json` | 249 | 142617 | `395bc816ecead450…` |
| `labelClusters_dbb06005977b4d5f.json` | 721 | 426871 | `83c939ac167cabf5…` |

Full hashes: `pipeline/out/manifest.json`.

Source label types in the pull: CurbRamp 1492, SurfaceProblem 535, NoCurbRamp 502, Obstacle 399, NoSidewalk 323, Crosswalk 89, Signal 34, Occlusion 23, Other 18. **`Occlusion` is a ninth type not listed in the API docs.** The pipeline maps unknown types to `other` (plan 5.2), so these 23 land in `other` and are counted in `report.json` under `unknown_source_types`. `other` has no alert threshold, so this is harmless; revisit if the app ever speaks `other`.

Tags: `tag_counts` is a JSON object mapping tag text to a count (not a list). 2,051 of 3,405 kept labels have at least one tag. The most common are `missing tactile warning` (413), `no alternate route` (280), `cracks` (260), `bumpy` (207), `uneven/slanted` (205), `points into traffic` (178). Tags are free text with spaces and slashes, so treat them as opaque strings.

Severity: `median_severity` is null on 419 of 3,405 kept labels (mostly curb ramps and crosswalks, which are rarely rated). Obstacle severity: 3 → 168, 2 → 120, 1 → 97, null → 13. The pipeline keeps null as null.

Dates: imagery from 2007-10 to 2025-09; label dates from 2019-04 to 2026-10. Imagery age varies a lot, which is what the staleness model is for.

Quality filter: no cluster had `disagree_count > agree_count`, so `drop_majority_disagree` dropped nothing. 5 features fell just outside the bbox and 5 duplicate clusters appeared in two overlapping tiles and were merged.

Density: 453 kept labels per km² (the earlier 330 figure was for one residential box). 720 street edges carry labels; the busiest edge has 36.

Overlap and ids: `label_cluster_id` is unique across the server, so it is safe as `ps:<id>`.

One real tagged feature (CC0; `users` and `label_ids` removed):

```json
{"type":"Feature","geometry":{"type":"Point","coordinates":[-122.2928581238,47.6614322662]},"properties":{"label_cluster_id":13244609,"label_type":"Obstacle","street_edge_id":22477,"intersection_id":null,"osm_way_id":394229211,"region_id":10,"region_name":"Ravenna","avg_image_capture_date":"2018-10-01T00:00Z","avg_label_date":"2019-05-25T11:59:04.392500Z","median_severity":2,"agree_count":7,"disagree_count":0,"unsure_count":2,"cluster_size":2,"tag_counts":{"pole":2,"narrow":1}}}
```

## Rate limits and etiquette

No limits are documented. We made 9 requests in about 30 seconds with a 1 s gap and saw no errors. Keep it sequential, keep the 1 s gap, and cache; do not refetch for demos (the app ships the bundle). A tile of 0.01° × 0.01° is 7 to 430 KB, so larger boxes are fine on size; we did not test a very large single box.

## Streets endpoint, 2026-10-17 (P0 complete)

`GET /v3/api/streets?bbox=minLng,minLat,maxLng,maxLat&inline=true`, same 9 tiles and etiquette as labelClusters. All 9 answered HTTP 200 with a GeoJSON `FeatureCollection` of `LineString` street edges (coordinates `[lng, lat]`). Properties: `street_edge_id, osm_way_id, region_id, region_name, way_type, max_speed, status, label_count, audit_count, outdated, user_ids, user_count, first_label_date, last_label_date`. **`user_ids` are labeler ids: never read, never stored in any derived file.** `street_edge_id` matches the `street_edge_id` on label clusters.

In the bbox: 904 distinct walkable edges (residential 361, secondary 271, tertiary 185, primary 87). **There are no footpaths or campus paths**, only roads, so routes can only follow street sidewalks (campus interior landmarks do not snap). Raw files hash: see `pipeline/data/raw/fetch_manifest_streets.json` (local, git-ignored; sha256 per file, 9 files).

## Still to verify

- `regions` endpoint (not needed: `region_name` is on every label and street).
- Data licence text: Project Sidewalk data is CC0; street geometry is OpenStreetMap, ODbL.
