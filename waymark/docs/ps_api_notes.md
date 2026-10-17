# Project Sidewalk (Seattle) API notes

Owner: Windows session. Status: partial. Verified by web fetch only; no byte-exact raw responses are saved yet (P0 still open).

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

## Still to verify (P0)

- Byte-exact raw responses saved with SHA-256.
- A cluster with non-empty `tag_counts` (how tags are keyed).
- Rate limits and etiquette; whether large bboxes are accepted.
- `streets` and `regions` on the Seattle server (needed for P5).
- Whether a Linux shell on the Surface can reach the host. From the Windows cloud session the proxy returned 403.
- Data licence text: Project Sidewalk data is CC0; street geometry is OpenStreetMap, ODbL.
