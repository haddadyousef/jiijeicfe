# Windows session status (single writer: Windows session). Newest entry on top.

## repo: 122d689 | wall: Sat 2026-10-17 18:30 PT

**Scheduled check-in 18:25: checked Mac at `122d689` (`main`).** No new Mac commits since UI v3 (#7); no new `STATUS_M` entry, no branches beyond the merged ones. My request for `make test` and `make uitest` exit codes on `main` is still open.
**Windows work done:** `wm_eval` now reports why evidence was unverifiable (`metrics.unverifiable_reasons`, `unverifiable_reasons` in `summary.json` and a section in the report). It reads the `reason` code the app writes on `waymark_evidence` trip-log records (lateral, left, reversed, gps_jump, unclean, few_frames, short_pass, between, route_end). The key is added only when reasons exist, so older summaries keep their bytes. 36 eval tests pass (35 plus 1 new).
**Walk 1:** no results pasted yet. **F1:** needs daylight, a spotter, Akash with the phone; not tonight (sunset about 18:10).

---
## repo: 28a3ae5 | wall: Sat 2026-10-17 17:58 PT

**Scheduled check-in 17:54: checked Mac at `28a3ae5` (`main`).** New since 17:23: **UI v3 "Graphite" merged (#7, ba51f67)**, Akash's request ("reimagine the app, same functionality"). I read the diff against the Waymark files: it touches only `ios/CaneKit/UI/**`, a doc comment in `RouteSource.swift`, two lines in `AppModel+Waymark.swift` (read-only helpers for the route card: demo route and its length), and the Sidewalk memory card's icon. No Logic, evidence, speech-priority or contract change. R1: accepted as UI only.
**Two flags, neither blocking:**
1. **`make uitest` was not re-run on UI v3** (Xcode GUI cannot sign the UITest target, so it needs Terminal). The Mac says no test-contract label changed; that is a claim, not a result. @M: please run `make test` and `make uitest` on `main` and report exit codes before the live walk.
2. **Route length differs by a few metres:** the app card now says 731 m (haversine along the waypoints); my pipeline said 727 m (local flat projection). Same route, different formula. For the pitch we say "about 730 m". No action.
**The app is running on Akash's iPhone ("akeesh").** So the phone-install blocker is cleared. F1 now needs: Akash with the phone, a spotter, daylight (sunset about 18:10 today, so not tonight), and the trusted-profile step if the build was via Xcode (it ran, so presumably done).
**Walk 1:** Yousef has not pasted results yet. Nothing to convert.
**Windows:** no pending code. Waiting on Walk 1 results and the F1 window.

---
## repo: 3562218 | wall: Sat 2026-10-17 17:30 PT

**Scheduled check-in 17:23: checked Mac at `3562218` (`main`).** Merged since 16:51: #5 UI v2 + Ave default route (24d2209), #6 E1 + E2 + X-e2e (cd3e1a8). D-35 items 1 to 3 are done. `waymark/e1`, `ui-v2`, `next`, `xe2e` branches are merged and can be left.
**Evidence on merged tree e997615 (Mac, iPhone 18 Pro):** `make gen` 0, `make test` 1044 passed exit 0, `make sim` BUILD SUCCEEDED 0 warnings, `make uitest` 12 passed 1 skipped exit 0, `make e2e-waymark` PASS exit 0 (6 SYNTHETIC labels spoken at `.scene`, silences `speech_busy` 6 / `crossing` 1 / `already_announced` 6, no evidence records as expected without LiDAR). I have not rerun any of it (no Xcode here); I take the exit codes as reported and the logs are in `waymark/logs/mac/`.
**R1 on the E1 review fixes (71b9dce), accepted:** Mac's own review found 3 blockers I did not (contradictions written for unfinished passes; labels 10 m to the side judged; `-1` speed / accuracy breaking the schema minimum, which would have made the harness drop spotter taps). Fixes are the right ones: finished passes only (at least 14.4 m walked, no reversal, at least 15 gated frames), 3 m lateral limit, gated confirms, schema-safe numbers, no evidence from simulation. The `reason` codes on `waymark_evidence` records go into V1's unverifiable breakdown. I should add them to the loader (see below).
**D-36 (answers the Mac's decision request):** narrow reading accepted. A curb event confirms only a `missing_curb_ramp`; `curb_ramp` is spotter-only. Design 9.1 row 2 amended.
**Windows next:** teach `wm_eval` loader the `reason` field if it surfaces in the exported records (metric 1 breakdown); keep it optional so old fixtures still load. Walk 1 checklist is with Yousef (page `Ave Checking Walk`, 14 stops).
**Blocked on humans:** phone install (Akash unlocks the iPhone 17 Pro, `make build install launch`), then F1.

---
## repo: 93599df | wall: Sat 2026-10-17 17:05 PT

**Walk 1 (checking walk) checklist built and published as a phone page.** 14 stops on the Ave route (727 m): 10 curb-ramp corners, 1 obstacle (ps:13292406 at about 212 m), 1 rough-surface spot (2 labels, about 468 m), plus the start corner. Source and stop list: `waymark/field/walk1_checklist.html`, `walk1_stops_raw.json`. Yousef is at Paccar Hall (close to the route start) and walks it himself, no Mac code needed. Results come back as `walk1_*` JSON lines (stop id, label ids, answer; no coordinates). I convert them to spotter-type evidence with a distinct build id, so they feed V1 and V2 and are reported as "paper walk", never as app output.

---
## repo: f1404da + branches (jiijeicfe) | wall: Sat 2026-10-17 16:55 PT

**Scheduled check-in 16:51: checked Mac at `f1404da` (`main`) and branches `waymark/e1` 4ba2cd9, `waymark/ui-v2` 54f753b, `waymark/next` b2a8de7 (e1 + ui-v2 merged together).** `STATUS_M` is now current (16:30 entry with per-merge `make test` / `make sim` / `make uitest` exit codes; thank you).
**D-35 items 1 and 2 are done on `waymark/ui-v2`:** `route_ave_seattle.json` is byte-identical to `waymark/demo/route.json` (I ran `cmp`), `RouteSource.aveSeattle()` added, `WAYMARK_DEMO_ROUTE=isr_cif` keeps the UIUC route for tests and e2e, simulator point = route start. Item 3 (X-e2e with SYNTHETIC priors) is not started. Not on `main` yet: merge needs Akash.
**R1 on E1 (`WaymarkEvidence.swift`), accepted with notes:** matches design 9.1 to 9.3. LiDAR obstacle pass over an 8 m window; confirm below 2.0 m, contradict only on a finished, clean pass of at least 5 trusted frames with torso band covered, GPS at most 20 m, fresh, walking, and nothing under 2.5 m; everything else is unverifiable (a no-op in the belief). Ground curb events confirm the nearest curb-ramp / missing-curb-ramp label ahead. Spotter reach 15 m. Pure logic with tests. Notes, none blocking: (a) a LiDAR "confirm" can be a pedestrian or parked car, which is what the spotter buttons are for, so V1 should report lidar-vs-spotter agreement per label, not trust lidar alone; (b) a contradiction needs a clean pass, so expect many unverifiable on a real walk and report that rate; (c) `decided` is cleared on route start, so one label yields at most one verdict per route, as the contract needs.
**R1 on E2 (`ios/scripts/waymark_export.py`):** strips and then re-verifies absence of lat / lng / lon / coordinate keys, validates schema `waymark.evidence.v1` and label ids `ps:<n>`, writes canonical sorted-key JSON (byte-stable), exits 2 if a coordinate survives. That satisfies the eval input contract. I will run it against a real log file when one exists; no real log exists yet.
**Open:** none of E1 / E2 / UI v2 is on `main` yet and the Mac has not reported `make test` on `waymark/next` (only the earlier trees). @M when you merge, give exit codes for the merged tree. F1 (live walk) can follow once `next` is merged and X-e2e passes, or sooner if Akash accepts a walk without X-e2e.
**Windows:** still waiting on Yousef for Walk 1 go-ahead (where, can walk ~1 km, who spots).

---
## repo: 73a7f8e (jiijeicfe) | wall: Sat 2026-10-17 16:25 PT

**Scheduled check-in 16:20: checked Mac at `73a7f8e`.** On `main` since 98d1314: **A1 merged (#3, 4dbfa2c)** and **UI pass 1 merged (#4, 73a7f8e; colour-blind palette, simpler pages, `ios/CaneKit/UI/**` plus watch and widget theme)**. Branches: `waymark/seattle-route` at ade7ff2 (D-35: bundled `route_ave_seattle.json`, simulator parks at its start, `WaymarkRouteTests`; **not merged**), `waymark/ui-rework`, `waymark/a1` (merged).
**`STATUS_M.md` has not been updated since 15:47** and does not mention the A1 fixes, the A1 and UI merges or the seattle-route branch. @M please add an entry (what `make test` / `make sim` showed on each merged tree, exit codes).
**R1 on the A1 review fixes (1ae605c), accepted:** the Mac ran its own adversarial review and acted on it. Waymark now speaks at `.scene` (below `.obstacle`) and only when the speech queue is idle; a cut Waymark line is dropped, never resumed; ground-hazard lines and "Close." restart the 5 s quiet window; a refused line is not counted or logged as spoken; silences are logged only inside the trigger distance; the indoor and gpsWeak cases are fixed. That is quieter than the plan (plan 7.5 only forbids `.safety` and `.nav`), so it is compatible with "never delay a base-app safety cue". Consequence for the pitch and V1 metric 7: a line may be dropped when the speech queue is busy, so cue counts will be lower than candidate counts; say so honestly.
**Order call:** I asked for E1 and E2 before the UI rework; Akash did the UI rework first, which is his call. Gating items are unchanged: E1 (evidence from LaneReport gates, ground events, Confirm / Not there buttons), E2 (export script), merge `waymark/seattle-route`, X-e2e. The live walk (F1) cannot happen before E1 and E2.
**Windows:** waiting on Yousef for the checking-walk go-ahead (answers to my three questions). Nothing else blocked.

---
## repo: 98d1314 (jiijeicfe) | wall: Sat 2026-10-17 15:52 PT

**Scheduled check-in 15:48: checked Mac at `98d1314`** (`main` now has L1 to L3 plus PR #2, the UI-test location fix; `waymark/a1` at b6e11a6, not merged). Old repo unchanged (`35c6e0d`, mine).
**Gate answered:** `make test` ran on the Mac, 1007 passed, exit 0, and the uitest run is green (11 passed, 1 skipped). Closes my open question. Plan 1.3 gate is met for L1 to L3.
**R1 review of A1 (read-only, `WaymarkEngine.swift`, diff stat 11 files):** accepted so far.
- Speaks only through `onSpeak` at `.obstacle`, ttl 6 s; any LiDAR cue starts the 5 s quiet window; off by default and cleared by `LaunchRecovery`; bundle loads off the main thread on first enable; AppModel edits are one-liners marked `// waymark:`.
- Log fields match the eval contract (`waymark_load.load_ms`, `waymark_cue.lookup_ms` and `latency_ms`, `suppressed_reason`), so V1 metric 7 will read them as is.
- Note, not a defect: `latency_ms` is fix timestamp to dispatch, so it includes the GPS delivery delay; I will say that in the pitch wording.
- Not yet seen: the AppModel diff lines and `WaymarkSession` internals. Merge only after the Mac's `make sim` is green, as the Mac plans.
**Leader call on order (answering the Mac's FYI about Akash's UI rework):** after A1, do D-35 (1) to (3), then **E1 and E2**, before the colour-blind palette and Guide-page rework. E1 and E2 gate the live walk and the evidence numbers (plan 6, "never cut E1"). The rework is worthwhile but does not gate anything. Akash can overrule.
**Windows next:** the checking-walk checklist (Walk 1, needs no Mac code) if Yousef can walk today; Q1 pitch skeleton.

---
## repo: 9d59f69 (jiijeicfe) | wall: Sat 2026-10-17 15:55 PT

**Order to the Mac, D-35 (handoff `2026-10-17-1555-W-to-M.md`):** use the Seattle Ave route, not the UIUC one. Simulator point becomes the route start; bundle `route_ave_seattle.json` for the untethered phone demo (keep the UIUC route and its tests); X-e2e replays `route_trace.json` with SYNTHETIC `test_priors.json`. Earlier I had only listed the files, not given this instruction. Also asked again for the `make test` result on the Mac.

---
## repo: d81026b + 330c2f0 (jiijeicfe) | wall: Sat 2026-10-17 15:40 PT

**Mac is on `jiijeicfe` now** (write access since 15:15). Checked Mac at `d81026b` (merge of PR #1, L1 to L3 into `main`, merged by Akash) and `STATUS_M.md` entry f9e3981 (15:21). **Collaborator step is done; Yousef's pending item is closed.**
**R1 review of the Mac's follow-ups (57b5856): accepted.** D-29(1) curb ramp `p >= 0.5` with a test; spacing clock finding fixed with `|dt|` and a test; `WaymarkGoldenTests` replays `contracts/golden/` (priors, 12 invalid cases, belief vectors to 1e-9, thresholds to 1e-12, evidence as parsed JSON) and decodes the real 3,405-label bundle; every label key now required, matching the schema. Boundaries respected: Mac edited only `ios/**` and `STATUS_M.md`. Executable-bit loss from the repo move: confirmed, thanks. I fixed my own `waymark/tools/sync.sh`. Other 100644 scripts (`hardware/mount/pitch_model.py`, `ios/scripts/streetview_stim.py`, `ios/scripts/stress/*.py`, `scripts/stl_tools.js`) may have been 644 upstream; not touched.
**Open question for the Mac:** the merge to `main` happened, but STATUS_M still says `make test` has not run on the Mac (Linux run: 1000 passed). Please confirm in `STATUS_M.md` whether Akash ran `make test` (exit code) before or after the merge. If not, run it on `main` now; that is the gate (plan 1.3).
**Demo route is final-candidate (D-34, 330c2f0):** direct Ave walk, 727 m, 9 waypoints, 3 inferred crossings. X-e2e can use `demo/route.json`, `demo/route_trace.json`, `demo/test_priors.json`. **Mac: next is A1.**

---
## repo: da130e3 (jiijeicfe) | wall: Sat 2026-10-17 15:45 PT

**P5 done (da130e3).** Yousef's streets fetch worked (9 tiles, 904 edges). `waymark/demo/` has `route.json` (app format, 9 waypoints, 3 inferred crossings), `route_trace.json` (5 m ticks), `route.gpx`, SYNTHETIC `test_priors.json` (6 labels planted along the route, one is the D-31 stale candidate), ranking and top-3 GeoJSON. Yousef chose the direct Ave route (727 m, D-34), not the C-shaped rank 1. The street data has no campus footpaths, so there is no campus route. 43 pipeline tests green. **@M:** X-e2e can use `demo/route.json`, `demo/route_trace.json` and `demo/test_priors.json` now (`demo/README.md` has the caveats).
**For humans:** open `demo/top3.geojson` on a map (geojson.io) and check the route is walkable and safe before it becomes the demo (H7).

---
## repo: 5de88f4 (jiijeicfe) | wall: Sat 2026-10-17 15:18 PT

**Scheduled check-in 15:18: checked Mac at `cc005ab` (old repo main, last Mac commit 15:04) and branch `waymark/l1-l3` at `be18902`.** Nothing new since the 15:05 status entry; `jiijeicfe` has only my commits. Old repo main is `c7ea8cd` (my bridge copy). Nothing to review. Still open: Yousef's streets fetch (P5) and the `azphalt` collaborator invite; Akash's `make test` on `waymark/l1-l3` and the phone trust step.

---
## repo: 8ab798b (jiijeicfe) | wall: Sat 2026-10-17 16:05 PT

**V2 built on synthetic data (8ab798b):** calibration with Brier and reliability plot, threshold sweep (tau 0.05 to 0.95, cost, minimizer, half/double C_miss sensitivity, hold-out discipline), staleness trend, positional error. 35 eval tests green. Real numbers need the F1 walk.
**P5 code done (d570258, 0f47848):** street graph, shortest paths between campus landmarks, corridor label counts, score with a D-31 stale-candidate bonus, writers for `route.json` (app format), `route_trace.json`, `route.gpx` and SYNTHETIC `test_priors.json`. 40 pipeline tests green. **Waiting on Yousef** to run `py -m wm_pipeline.run streets` (street geometry); then I rank and pick.
**Check-in 16:00:** no new Mac commits (old repo `cc005ab`, branch `waymark/l1-l3` at `be18902`). Collaborator invite for `azphalt` still pending on Yousef. Still no answer on `make test` on the Mac for `waymark/l1-l3`.

---
## repo: c583e5f (jiijeicfe) | wall: Sat 2026-10-17 15:35 PT

**V1 eval harness done (c583e5f):** `waymark/eval/` (outcome rates with Wilson intervals, sensor vs spotter with kappa, load and latency), seeded synthetic fixtures watermarked SYNTHETIC, 20 tests green. Input contract for the load and latency fields is in `eval/README.md` (`load_ms`, `lookup_ms`, `latency_ms`, `suppressed_reason`); @M please emit those in A1/E2.

**Check-in 15:25: Mac is at `cc005ab` and branch `waymark/l1-l3` at `be18902` in the OLD repo** (it cannot reach `jiijeicfe`: `add_repo` refused). Asked Yousef (15:20) to add `azphalt` as a collaborator. Until then D-33 applies and I copy contracts, the real bundle and these docs to the old repo as a bridge.

**R1 review of L1 to L3 (read-only, I cannot run Swift here):**
- `WaymarkBelief` matches `contracts/ref/belief.py`: same decay (`0.5^(dt/H)`, half-lives 60/120/365), same weights, same `a`, `b`, `p`, `n_eff`, unverifiable is a full no-op (clock too). Same tau formula and the same four costs.
- `WaymarkPriorSet.decode` is at least as strict as the schema and I checked every rule against the real 3,405-label bundle by hand: nothing in it trips a rule (severity in [1, 3] or null, ids match `ps:` + cluster id, dates `YYYY-MM`, no duplicates).
- `WaymarkAlertPolicy`: rule order is sensible and fails quiet on unknown levels. **Finding (low):** the spacing check `nowUTC - last < 20` stays silent forever if the wall clock moves backwards; use `abs` or reset on a negative delta, with a test. **Finding (medium, needs test):** D-29(1), curb ramp requires `p >= 0.5`.
- `make test` on the Mac is still the gate before merge to `main`; the Linux run (989 passed) is not enough.
- Not yet checked: `WaymarkAhead`, `WaymarkIndex`, `WaymarkRecord` internals. Next review pass.

**Rulings (D-29):** curb ramp p gate 0.5; any LiDAR cue silences for 5 s (accepted); trigger distance margin added, not subtracted (v1.0 text was wrong); Standard per plan 5.2. D-30 records the hold release as D-28.

**Real-data findings the whole team should know (D-31, D-32):** (1) With the real bundle no speakable label has `p < tau` from priors alone, so thresholds only matter after field evidence. A stale demo label must be a `surface_problem` or `missing_curb_ramp` with `n_agree` 0. (2) 88% of speakable labels have imagery from 2019 or earlier.

**Next:** P5 (rank routes, pick a demo label per D-31), then V2 scaffolding.

---
## repo: 716d0d0 (jiijeicfe) | wall: Sat 2026-10-17 15:12 PT

**Real data landed.** Yousef ran the fetch natively (9 tiles, no errors). Built `ios/CaneKit/Resources/waymark_priors.json` in a single-file commit (`e1d466e`): **3,405 labels**, 1.07 MB (budget 3 MB), bbox `[-122.32, 47.64, -122.29, 47.67]`, sha256 `ea322e18…`. Same input gives the same bytes (checked twice). Contract validation passes; no `users` or `label_ids` in the file. By type: curb_ramp 1489, surface_problem 531, missing_curb_ramp 501, obstacle 398, no_sidewalk 322, crosswalk 89, other 75.
**Mac, note:** the source has a type `Occlusion` (23 labels) that the API docs omit. It maps to `other` (unknown rule), which has no threshold. `severity` is null on 419 labels. Tags are free text.
**P0 done** except `streets`/`regions` (for P5): `ps_api_notes.md` has hashes, rate-limit notes and a tagged sample; `pipeline/out/` has the manifest and report.
**Fixes:** `fetch` no longer imports `jsonschema` (5410fb1). Pipeline 25 tests, contracts 19 tests, both pass.
**Check-in 15:12:** `origin/main` has no Mac commits since mine. Mac still has L1 to start; nothing to review.
**Next:** V1 eval harness, then P5 route ranking.

---
## repo: d2898e0 (jiijeicfe) | wall: Sat 2026-10-17 14:42 PT

**Repo moved (D-24).** Work now happens in `haddadyousef/jiijeicfe`. I verified its tree equals old `main` at 622ba38 except an older `STATUS_M.md`. Added `PROVENANCE.md`, plan 3.7 (Akash's move procedure), D-24, D-25, F-15, F-16.

**Check-in: checked Mac at 5b9227f in the old repo (14:42).** G0 simulator half is green on the Mac: `make test` 919/919 exit 0 on baseline and on the rename, `make sim` BUILD SUCCEEDED exit 0. D-01's push condition is met. Mac accepted D-19 to D-22 and wrote L1 to L3 signatures in `M_NOTES.md` (design only). No Waymark feature code yet, which is correct under D-04. Nothing in the diff stat touches secrets or traces. Mac's newest status entries and `ios/scripts/waymark_g0.sh` exist only in the old repo; the Mac re-adds them (3.7).

**Answers to the Mac:** yes, D-23 applies to Mac commits (D-25), Akash may overrule. Akash is `azphalt` (F-15).

**Scheduled check-in 14:44 PT:** new repo `main` is at 7fe015a (mine); the Mac has not pushed to it yet. Old repo unchanged since 5b9227f (14:26). Nothing to review. Waiting on Akash's repo move (plan 3.7).

**Hold released (14:53 PT, D-28).** Yousef released the build lane. Mac: L1 can start now against `contracts/golden/`. Windows: starting P2 to P4 (normalize, filter, bundle, manifest), then V1.

**C0 landed (14:50 PT, 2ec1887):** `waymark/contracts/` with both schemas, golden priors (1 real label, 6 synthetic, plus unknown-type and 12 invalid cases), 8 synthetic evidence lines, belief and threshold vectors, reference Python and 19 passing tests (`python -m pytest -q`, exit 0). Mac: please ack in `STATUS_M.md` (D-26, D-27 clarify two details). Swift L1/L2 tests read `contracts/golden/` once the hold lifts.

**DubHacks rules:** I tried to read them myself (search results were titles only; the 2024 hacker guide is a script-rendered page with no readable text; a fetch of the current site was declined, so I stopped). H2 still needs Yousef to paste the rules text or answers.

**Open:** H2 (DubHacks rules and schedule) is the only thing holding the build lane. H4 (Windows folder) for P0. Mac disk space is 11 GiB free.

**Next:** C0a, C0b.

---
## repo: af0bfb5 | wall: Sat 2026-10-17 14:30 PT

**Check-in (3.6): checked Mac at af0bfb5 (14:30).** Mac acked 5.2 to 5.4 and re-derived every worked number independently (all match). It wrote `M_NOTES.md` (all seven items), pushed a CLAUDE.md pointer, and put the rename commit (dbf548e, 84 files) and M1 (e05ce58) on branch `waymark/g0-rename`. Nothing is on `main` besides docs. The build lane is correctly on hold. Findings: no secrets or traces seen in the diff stat; no edits outside Mac-owned paths. Rename commit is not yet verified on the Mac (G0 batch is with Akash).

**Answers to the Mac (recorded as D-19 to D-22):** severity is a number in [1,3], no rounding; `n_eff` is display-only; yes to deleting `AritroProfile.imageset`; yes to the two-location `make uitest` plan.

**Open for Yousef:** which GitHub account is Akash's, `azphalt` or `akeeshcodes` (the Mac session pushes as `akeeshcodes`); the noreply email so my commits show as haddadyousef.

**Done:** first push (ce106c1). **Next:** C0a and C0b, P0 when the folder is granted.

---
## repo: (not pushed yet) | wall: Sat 2026-10-17 14:15 PT

**Done**
- WAYMARK_PLAN.md v1.1 written (answers the Mac handoff of 13:45).
- DECISIONS.md, this file, STATUS_M.md and M_NOTES.md templates, ps_api_notes.md, sync scripts, `.gitignore`.
- Verified the Seattle API sample independently: same 66 clusters and type counts as the Mac (F-04).

**In progress**
- C0a (schemas, golden priors and evidence) and C0b (belief and threshold vectors, reference Python). Next, in the prep lane.
- P0 finish (needs a connected folder, H4).

**Blocked**
- Pushing to GitHub: this session has no GitHub link yet. Yousef links it (H3) or he or Akash pushes.
- Build lane (P1 to P6, V*, S*, D1): HOLD until D-04 is released.

**Questions**
- @Mac: please ack the contract amendments in WAYMARK_PLAN 5.2 to 5.4, and answer the seven items in 7.1 in `M_NOTES.md`.
- @Yousef: H2 (rules and schedule), H3 (Akash invite, link GitHub), H4 (folder). H1 is optional.
- @Akash: H5 (hardware facts), GitHub username.

**Next**
1. C0a and C0b.
2. P0 once the folder is granted.
3. Review the Mac's first handoff (R1).
