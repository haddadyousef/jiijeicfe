# Waymark decisions and verified facts

Owner: Windows session (single writer). Mac proposes changes in `STATUS_M.md`. Newest entries at the bottom. Format: `date time PT | id | text | source`.

## Verified facts

- 2026-10-17 13:00 | F-01 | Seattle Project Sidewalk server is `https://sidewalk-sea.cs.washington.edu`; `GET /v3/api/labelClusters` works with no API key. | Mac session, web fetch
- 2026-10-17 13:00 | F-02 | `bbox` order is `minLng,minLat,maxLng,maxLat`. | Mac session
- 2026-10-17 13:00 | F-03 | `median_severity` ranges 1 to 3. | Mac session
- 2026-10-17 13:55 | F-04 | `bbox=-122.3080,47.6520,-122.3020,47.6560&inline=true` returned 66 clusters: CurbRamp 37, SurfaceProblem 10, NoCurbRamp 9, Obstacle 8, Crosswalk 1, Other 1. Mac and Windows saw identical counts. | Mac 13:00, Windows 13:55
- 2026-10-17 13:55 | F-05 | Cluster properties (17): label_cluster_id, label_type, street_edge_id, intersection_id, osm_way_id, region_id, region_name, avg_image_capture_date, avg_label_date, median_severity, agree_count, disagree_count, unsure_count, cluster_size, label_ids, users, tag_counts. | Mac, Windows
- 2026-10-17 13:00 | F-06 | `users` holds labeler UUIDs. Dropped in normalization. Never in a bundle, fixture or doc. | Mac session
- 2026-10-17 13:00 | F-07 | Sample imagery dates are from 2019. | Mac session
- 2026-10-17 13:00 | F-08 | Label types seen: CurbRamp, NoCurbRamp, Crosswalk, SurfaceProblem, Obstacle, Signal, NoSidewalk, Other. | Mac session (docs page)
- 2026-10-17 13:45 | F-10 | Mac: Xcode 27.1 (27A9275), `xcode-select` fixed, working tree `~/Developer/Waymark` at OpenCane `fe86e10`, clean. Rename and signing patch applies cleanly; Logic tests 912 passed on Linux Swift 6.0.3. Not yet run on the Mac: `make test`, `make gen`, `make sim`, `make uitest`. | Mac handoff
- 2026-10-17 13:55 | F-11 | From the Windows session shell, the Seattle host is blocked by the proxy (403 on CONNECT). WebFetch can read it but returns summaries. `haddadyousef/Waymark` is empty and public (ls-remote returns no refs). GitHub is not linked to the Windows session (`add_repo` failed). | Windows session
- 2026-10-17 13:52 | F-12 | Yousef's computer: Windows arm64 Surface, desktop app connected, no folder granted yet. | Windows session
- 2026-10-17 14:10 | F-09 | Open and unverified: byte-exact raw samples on disk, non-empty `tag_counts`, rate limits, `streets` and `regions` on Seattle, device-shell reachability, iPhone model and LiDAR, Apple ID and team, watch, AirPods, mount, DubHacks rules and schedule, aritroBh's permission. | leader
- (details of the above) byte-exact raw samples on disk, non-empty `tag_counts`, rate limits, `streets` and `regions` endpoints on Seattle, whether a device shell can reach the host, iPhone model and LiDAR, Apple ID and team, watch, AirPods, mount, DubHacks rules and schedule, aritroBh's permission.
- 2026-10-17 14:12 | F-13 | `add_repo` attached `haddadyousef/waymark` to the Windows session but `push_check` was `refused` (GitHub linked, Claude GitHub App not yet installed on the repo). Akash's GitHub username is `azphalt`. | Windows session, Yousef
- 2026-10-17 14:30 | F-14 | The Mac session's GitHub identity is `akeeshcodes` and it already has push access to the repo (its first commit af0bfb5 landed on main at 14:19). Yousef named Akash as `azphalt`; which is Akash's is unconfirmed. Mac branch `waymark/g0-rename` holds the rename commit (dbf548e) and M1 (e05ce58), not yet verified on the Mac. | Windows check-in
- 2026-10-17 14:25 | F-15 | Akash: both GitHub accounts are his; he uses `azphalt` (F-14 resolved). OpenCane is a project Akash developed with a team, and Waymark is his new project on top of it, so the base is the team's own prior work. The base still predates DubHacks, so it is disclosed as pre-existing work (H2). | Mac status, Akash
- 2026-10-17 14:30 | F-16 | Mac, G0 simulator half: Xcode 27.1, XcodeGen 2.46.0, macOS 26.6.2; baseline `make test` 919/919 exit 0; rename branch `make test` 919/919 exit 0 and `make sim` BUILD SUCCEEDED exit 0 (phone-only generation). Not done: uitest at both locations, device run. Mac disk has 11 GiB free. | Mac status

## Decisions

- 2026-10-17 14:10 | D-01 | Accept the rename and signing patch (85 files) as the base of our history. Applied after the docs commit; pushed only after `make test` exit 0 and `make sim` success. | leader
- 2026-10-17 14:10 | D-02 | Display name is Waymark. Closes v1.0 decision 7 and task X2. Code names stay (CaneKit, `opencane_*`, `OpenCane*`). | Akash 13:29, leader agrees
- 2026-10-17 14:10 | D-03 | Repo stays public (Yousef, 14:03). No keys, Secrets.plist, local.mk, logs or real traces ever. | Yousef
- 2026-10-17 14:10 | D-04 | Prep lane / build lane split. Build lane is on HOLD until Yousef records the outcome of H2 below. | leader
- 2026-10-17 14:10 | D-05 | Contracts amended in place (WAYMARK_PLAN 5.2). Mac may stub decode tests from the example there. | leader
- 2026-10-17 14:10 | D-06 | Bundle path `ios/CaneKit/Resources/waymark_priors.json`, at most 3 MB and 20,000 labels. | leader
- 2026-10-17 14:10 | D-07 | Interim simulator location 47.6540, -122.3050 (centre of the verified sample box), as Makefile variables. | leader
- 2026-10-17 14:10 | D-08 | Leave UIUC content untouched in Tier 0. Do not show the Profile page. Propose a neutral replacement by freeze minus 6 h. Add an About credit row. | leader
- 2026-10-17 14:10 | D-09 | Phone-only (`WATCH=0`) by default; at most 20 minutes on watch or HealthKit signing. | leader
- 2026-10-17 14:20 | D-10 | In-app credit is optional (OpenCane authors said credit is not required, relayed by Yousef 14:10). README, Devpost and pitch still disclose that Waymark is built on OpenCane. | leader, Yousef
- 2026-10-17 14:10 | D-11 | Single-writer files and relay protocol (WAYMARK_PLAN section 3). | leader
- 2026-10-17 14:10 | D-12 | Portability rule and Plan B triggers: G0 not green after 3 hours, or the DubHacks rules forbid building on a pre-existing project. | leader
- 2026-10-17 14:10 | D-13 | Severity 1 to 3; bundle `bbox_lnglat`, longitude first. | leader
- 2026-10-17 14:10 | D-14 | Raw trip logs never enter git. Mac writes the export filter (E2). | leader
- 2026-10-17 14:10 | D-15 | Keep `crosswalk` in the bundle (never spoken); `Signal` maps to `other`; unknown types map to `other`. | leader
- 2026-10-17 14:10 | D-16 | Belief and threshold math is normative (WAYMARK_PLAN 5.3 and 5.4). | leader
- 2026-10-17 14:10 | D-17 | Standing authority for the Windows session: act freely inside the granted folder and project; ask before making a repo public, messaging anyone as Yousef, contacting aritroBh or DubHacks, spending money, or touching other accounts or folders. | Yousef's instruction, leader's limits

- 2026-10-17 14:03 | D-18 | Yousef confirmed building on OpenCane is allowed, and at 14:10 that the OpenCane authors said credit is not required. Recorded as his statement; the verbatim message is to be pasted. Disclosure to judges stays (D-10). | Yousef
- 2026-10-17 14:30 | D-19 | `severity` is a number in [1,3] stored as the API gives it (at most 2 decimals, no rounding), or null. Answers the Mac's median question; amends WAYMARK_PLAN 5.2. | leader
- 2026-10-17 14:30 | D-20 | `n_eff` is display-only in v1. `WaymarkAlertPolicy` does not require a minimum `n_eff`. | leader
- 2026-10-17 14:30 | D-21 | Ack the D-08 proposal: delete `AritroProfile.imageset`, use the fallback symbol. Check no UI test references the photo. | leader
- 2026-10-17 14:30 | D-22 | `make uitest` runs twice: at the UIUC location (`SIM_LAT=40.1140 SIM_LON=-88.2249`) as the like-for-like gate, and at Seattle for information only. | leader
- 2026-10-17 14:35 | D-23 | Windows-session commits are authored as Yousef with the GitHub noreply address, no Claude co-author trailer, so they show as `haddadyousef`. Commits before this one (ce106c1, 95480f3) keep their old author fields. | Yousef
- 2026-10-17 14:42 | D-24 | Team repo moved to `github.com/haddadyousef/jiijeicfe` (Yousef, 14:37 initial commit; tree equals old `Waymark` main at 622ba38 except an older STATUS_M.md). Old `haddadyousef/Waymark` is frozen and kept as the full-history record. See PROVENANCE.md. | Yousef
- 2026-10-17 14:42 | D-25 | Mac-session commits follow D-23: authored as Akash (`azphalt`) noreply, no Claude co-author trailer, unless Akash says otherwise. | leader, pending Akash
- 2026-10-17 14:49 | D-26 | Evidence lines are compared as parsed JSON (float tolerance 1e-9) in Swift tests, not byte for byte. Relaxes v1.0 8.1 (`WaymarkRecord` row). | leader
- 2026-10-17 14:49 | D-27 | Bundle labels sorted ascending by numeric `source_cluster_id`. Clarifies WAYMARK_PLAN 5.2 determinism row. | leader
- 2026-10-17 14:53 | D-28 | **Build lane hold RELEASED** by Yousef (14:52, message: "hold released"). H2 answers (rules text, schedule) are still not on file; Yousef is responsible for the rules. Plan 1.3 right-hand column starts now. | Yousef
- 2026-10-17 15:30 | D-29 | **Rulings on the Mac's L3 questions (STATUS_M 15:05).** (1) `curb_ramp` has no tau; at Detailed it speaks only if `p >= 0.5` (a ramp the evidence has mostly contradicted is not announced). Needs a test. (2) Any LiDAR cue in the last 5 s silences Waymark: accepted, it only makes it quieter. (3) Position uncertainty is added to the trigger distance (speak earlier), capped at the 35 m look-ahead: accepted. The v1.0 8.3 wording "reduced by" is an error (it would put the line at the label), overridden. (4) Standard follows plan 5.2 (obstacle, missing curb ramp, no sidewalk); plan beats the v1.0 design doc. | leader
- 2026-10-17 15:30 | D-30 | Build-lane release is recorded as D-28 (this resolves the Mac's request to record it as D-04). D-04 stays as written. | leader
- 2026-10-17 15:30 | D-31 | **Finding, real data.** With the real bundle, no label of a speakable type has `p < tau` from priors alone (minimum p is 0.5, because clusters with more disagrees than agrees are dropped). So thresholds never silence a prior until field evidence arrives. Consequence for the demo: a stale label stops being announced only if it has few validations. Obstacle (tau 1/6) needs about ten spotter contradictions; a `surface_problem` with `n_agree = 0` drops below 1/3 after one spotter tap (1 / 4 = 0.25). P5 must choose a demo candidate like that, and the pitch must not claim the app "learns" after one walk for obstacles. | leader
- 2026-10-17 15:30 | D-32 | **Finding, staleness.** 1,543 of 1,752 labels of speakable types (88%) have imagery from 2019 or earlier (2007 at the oldest). Prior age is not modelled in `p`, only our own evidence decays. Not changed for v1; V2 reports confirm rate against imagery age (metric 5) so the data can say whether it matters. | leader
- 2026-10-17 15:30 | D-33 | The Mac may keep pushing to the old `Waymark` repo until it has write access to `jiijeicfe` (Yousef was asked at 15:20 to add `azphalt` as a collaborator). After that, move per plan 3.7. Work done in the meantime is kept by cherry-pick, not rewritten. | leader
- 2026-10-17 15:50 | D-34 | **Demo route chosen (Yousef, 15:32): `The Ave and NE 42nd to The Ave and NE 50th`**, 727 m, straight north on University Way NE, real U District streets (street data has no campus footpaths). Rank 1 (C-shaped detour to hit stale labels) and rank 2 (unverifiable long segment) were rejected. The real route has only 1 obstacle and 2 surface problems, so the stale-label story is shown in the replay with SYNTHETIC `test_priors.json`, labelled as simulated. A person still walks it before the demo (H7). | Yousef
- 2026-10-17 15:55 | D-35 | **The Seattle Ave route replaces the UIUC route for the Waymark demo.** D-07's interim point is superseded: `SIM_LAT=47.658324`, `SIM_LON=-122.313219` (route start). The phone demo bundles the route (`route_ave_seattle.json`, a copy of `waymark/demo/route.json`); the UIUC route and every test that uses it stay. X-e2e replays `demo/route_trace.json` with SYNTHETIC `demo/test_priors.json`. Orders to the Mac: `handoffs/2026-10-17-1555-W-to-M.md`. | leader
- 2026-10-17 17:30 | D-36 | **Ruling on the Mac's §9.1 row 2 question (STATUS_M 17:15): the narrow reading is accepted.** A gated curb event (drop or step) confirms only the nearest `missing_curb_ramp` label. A `curb_ramp` label gets no ground verdict: a ramp up to about 10 percent grade is silent to the ground detector, so a drop at a ramp label would say the ramp is missing, not present. Contradicting a `curb_ramp` stays spotter-only. Amends DESIGN 9.1 row 2. Consequence: curb-ramp ground truth comes from spotter taps and the paper Walk 1 only, so V1 reports ramp labels as spotter-evaluated. | leader |
- 2026-10-17 23:55 | D-37 | **Recorded at the Mac's request (STATUS_M 23:40, c).** (1) The report map corridor (25 m) and the confidence bands (70 / 40 %) are display-only `[H]`; alerts still use tau. (2) `CampusGate`: University of Illinois content is reachable only with `WAYMARK_DEMO_ROUTE=isr_cif` (UI tests and e2e); the default build is UW / U District only. (3) `Settings.bool` reads launch-arg strings (`-key NO`). Pending Akash's review of branch `waymark/judge-demo` (merged to `main` as #8). | leader |
- 2026-10-17 23:55 | D-38 | **Root README is Waymark's; OpenCane's README is kept as `docs/OPENCANE_README.md`** (links rewritten, content unchanged). The OpenCane disclosure paragraph (D-18, D-10) is in the README and uses the Mac's text; diff stat recomputed against `fe86e10` at 23:55: 233 files, +22,804 / −1,125, 89 commits, 82 `waymark:`. Code names (CaneKit, targets, bundle ids), `AGENTS.md`, `CLAUDE.md`, `ios/**` and the OpenCane docs are not renamed; the app's visible name was already Waymark. | leader |
- 2026-10-18 00:15 | D-39 | **Yousef edited the README directly (23:53, 23:55): removed the "Built on OpenCane" section, the OpenCane credit and deleted `docs/OPENCANE_README.md`.** Supersedes the README part of D-38. The README no longer carries the OpenCane disclosure that D-10 and D-18 say stays; the disclosure currently lives only in `PROVENANCE.md` and the Devpost draft. Leader flagged this to Yousef at 00:15 and did not revert his edit. Links to the deleted file were removed from `docs/README.md`. | leader

## Pending human inputs (fill in when answered)

- H1 paste the OpenCane authors' reply for the record: pending
- H2 DubHacks rules answers and schedule: not on file. Hold status: RELEASED (D-28)
- H3 done: GitHub linked, Claude can push to the new repo, Akash is pushing (account `azphalt`).
- H5 hardware facts: pending
