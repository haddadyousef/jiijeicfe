# Demo route ranking (P5)

Shortest street path between every pair of landmarks (300 to 1400 m), scored by what the real priors say within 15 m of the street centreline. Score rule: `routes.score_route`. This is a shortlist; a human walks and picks (street geometry is the centreline, not the sidewalk, and crossings are not checked).

| # | route | length m | score | hazard labels | hazard types | crosswalks | stale candidates (D-31) |
|---|---|---|---|---|---|---|---|
| 1 | The Ave and NE 42nd via ps:13292089 to The Ave and NE 50th | 1060 | 23.15 | 25 | missing_curb_ramp, obstacle, surface_problem | 3 | 2 |
| 2 | The Ave and NE 42nd to UW Medical Center | 1170 | 21.3 | 24 | missing_curb_ramp, no_sidewalk, obstacle, surface_problem | 5 | 0 |
| 3 | The Ave and NE 42nd to The Ave and NE 50th | 727 | 9.0 | 3 | obstacle, surface_problem | 0 | 0 |
| 4 | The Ave and NE 50th to U District station | 457 | 4.57 | 2 | surface_problem | 0 | 0 |
| 5 | The Ave and NE 45th to The Ave and NE 50th | 400 | 4.0 | 2 | surface_problem | 0 | 0 |
| 6 | The Ave and NE 42nd to U District station | 383 | 2.83 | 1 | obstacle | 0 | 0 |
| 7 | The Ave and NE 42nd to The Ave and NE 45th | 327 | 2.27 | 1 | obstacle | 0 | 0 |
