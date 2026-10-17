# STATUS_M — Mac session status (newest entry on top)

Owner: Mac session (Akash's account). Format per plan v1.1 §3.3.

---

## repo: f9e3981 (jiijeicfe; branch `waymark/l1-l3` at 6b145dc) | wall: Sat 15:21 PT

**Moved to `jiijeicfe`** (this session got write access at 15:15). Read W's entries through c583e5f / 0f47848 and DECISIONS through D-33.

**Done (evidence):**
- Plan 3.7 re-add, commit 9ca4cf5: `STATUS_M.md` and `ios/scripts/waymark_g0.sh` from the old repo (they were newer there).
- **Found and fixed: the move dropped the executable bit** on `ios/scripts/gen.sh`, `test.sh`, `e2e.py`, `cue_audit.py`, `waymark_g0.sh` (100755 in the old repo, 100644 here). `make gen` / `make test` / `make e2e` run them directly, so a fresh Mac clone would fail with "permission denied". Restored in 9ca4cf5. @W `waymark/tools/sync.sh` lost its bit too (your file; `sh waymark/tools/sync.sh` works meanwhile).
- L1 to L3 cherry-picked from the old repo (D-33): bcab58e, 0db8e2a, 7ac181d (content unchanged).
- R1 + C0 follow-ups, 6b145dc (tests first; red: `curbRampMinP` missing and the golden cases):
  - **D-29 (1)** curb ramps at Detailed need `p ≥ 0.5` (`WaymarkAlertPolicy.curbRampMinP`), with a test.
  - **R1 clock finding** fixed: spacing uses `|now − last| < 20 s`, test `aBackwardsClockDoesNotSilenceWaymarkForever`.
  - **C0 parity** `WaymarkGoldenTests`: `priors_sample.json` (7 labels, real label 1 field for field), `priors_unknown_type.json` (→ `.other`), all 12 `priors_invalid_cases.json` (every `decoder_must_reject: true` rejected; this decoder is stricter on bad_month / bbox_wrong_order / id_mismatch and accepts unsorted_labels), `belief_vectors.json` replayed per the README's ordering rule, every a / b / p / n_eff within 1e-9, `threshold_vectors.json` within 1e-12, `evidence_sample.jsonl` re-encoded and compared as parsed JSON (D-26).
  - **Real bundle** `ios/CaneKit/Resources/waymark_priors.json` decodes with the strict decoder, sorted by cluster id (D-27), every label inside `bbox_lnglat`, labels within 150 m of the D-07 point.
  - **Contract alignment:** every label key of `priors_v1.schema.json` is now required (golden `missing_required_field` must be rejected); nullable ones must be explicit `null`. My earlier 0 / 1 / [] defaults are removed.
  - `swift test` on Linux Swift 6.0.3: **1000 tests passed, exit 0** (HeadNodDetectorTests set aside on Linux only). **Not yet run on the Mac.**
- **Acks:** C0 as landed (2ec1887); D-26 and D-27 (both are honoured by the tests above); D-29 to D-33 read and applied.
- G0 device result (old repo, 14:50): signed and installed as `com.akashtadikonda.waymark` on Akash's iPhone 17 Pro; launch waits on the one-time "trust developer" step. `make sim17` cannot create a 17 Pro Max on Xcode 27.1's iOS 27.1 runtime; `waymark_g0.sh uitest` now falls back to an available iPhone Pro simulator. UI tests not run yet.

**Noted for A1 / E2:** `eval/README.md` input fields `load_ms`, `lookup_ms`, `latency_ms`, `suppressed_reason` will be emitted by `WaymarkEngine` in `waymark_load` / `waymark_cue`.

**Blocked:** nothing on W. Mac-side gates are Akash's: trust the developer profile on the phone, `make test` on `waymark/l1-l3`, `waymark_g0.sh uitest`. @H

**Next:** after the Mac `make test` passes, merge `waymark/l1-l3` to `main`; then A1 (`WaymarkEngine`, `WaymarkStore`, `waymarkEnabled` default off, AppModel wiring per `M_NOTES.md` §8).

---

## repo: 5b9227f (L1-L3 on branch `waymark/l1-l3` at 1846d24) | wall: Sat 15:05 PT

**Done (evidence):**
- **G0 device build signed and installed.** `make build install launch` (14:50, main 5b9227f, `WATCH=0` gen): `** BUILD SUCCEEDED **`; `devicectl` "App installed: bundleID com.akashtadikonda.waymark" on Akash's **iPhone 17 Pro (iPhone18,1), physical — LiDAR model**. Launch refused (exit 2): "profile has not been explicitly trusted by the user" (CoreDevice 10002). That is the one-time free-team step (Settings → General → VPN & Device Management → trust the developer), not a code problem. @H
- **L1 to L3 written test-first** (build lane released by Yousef, relayed by Akash at 14:29; @W please record it in `DECISIONS.md` D-04). All in `ios/Logic/Sources/CaneKitLogic/Waymark/`, Foundation only, base-repo types used: `Coordinate`, `GeoMath` (plan 1.4):
  - L1 2bb5d83 `WaymarkLabelType`, `WaymarkPrior`, `WaymarkPriorSet.decode` (strict 5.2), `WaymarkIndex` (grid, equals brute force).
  - L2 59a9836 `WaymarkBelief` (5.3), `WaymarkThreshold` (5.4), `WaymarkAhead` (route legs or heading).
  - L3 1846d24 `WaymarkLines` (Appendix A, appended to `SpokenPhrases.warningLines`: budget 1,856 / 2,000, `SpokenPhrasesTests` updated 1,718 → 1,856 and 74 → 79), `WaymarkAlertPolicy`, `WaymarkRecord` (evidence line equals the design doc 7.2 example byte for byte).
  - Red first each time ("cannot find type … in scope"), then `swift test` on Linux Swift 6.0.3: **989 passed, exit 0** (912 base + 77 new; HeadNodDetectorTests set aside for the Linux run only). **Not yet run on the Mac** (`make test`); the branch merges to `main` only after it is.
- Every row of the plan 5.3 worked table and the four 5.4 values are tests (tolerance 1e-9 / 1e-12). `belief_vectors.json` / golden priors will be added as test inputs as soon as `waymark/contracts/` exists.

**Failed / fixed:**
- `make sim17` (14:28): Xcode 27.1 refused "iPhone 17 Pro Max" on the iOS 27.1 runtime ("Incompatible device", code 403), so both `make uitest` runs stopped at `sim-grant` ("Invalid device"). Not a test failure. Fix in this commit: `waymark_g0.sh uitest` falls back to the first available iPhone Pro simulator (Akash has an "iPhone 18 Pro" one). UI tests not run yet.

**Design choices in L3 that need a W ack (plan 7.3 says the doc decides; the doc was not explicit):** @W
1. `curb_ramp` has no tau (5.4), so at Detailed it speaks without a p gate. Alternative: require p ≥ 0.5.
2. "LiDAR already warned about the same obstacle within 5 s" (8.3): the app cannot match identities, so **any** LiDAR cue in the last 5 s silences Waymark. Only makes it quieter.
3. "Trigger distance reduced by position uncertainty" (8.3) read as: speak **earlier** by √(gps² + 8²) m, capped at the 35 m look-ahead. Earlier is the safe direction; tell me if you meant later.
4. Design doc 8.1 says Standard = "high-severity only"; plan 5.2 says Standard = obstacle / missing curb ramp / no sidewalk. I followed plan 5.2 (precedence).

**Blocked:** I cannot reach `haddadyousef/jiijeicfe` (Akash says both sessions should use it). `add_repo` refuses ("no access") and `list_repos` does not show it. Until access works, the Mac keeps using `haddadyousef/Waymark`. @H @W

**Next:** Akash trusts the profile and opens Waymark on the phone (screenshot = G0 done); `make test` on `waymark/l1-l3`; `waymark_g0.sh uitest`. Then A1 (WaymarkEngine + store + setting, AppModel wiring per `M_NOTES.md` §8).

---

## repo: 622ba38 | wall: Sat 14:30 PT

**G0 simulator half is green** (logs in Akash's `waymark/logs/mac/`, git-ignored, read over the file bridge):

| Stage | Tree | Command | Result |
|---|---|---|---|
| check | 230ebf7 main | toolchain | Xcode 27.1 (27A9275), XcodeGen 2.46.0, macOS 26.6.2; iOS sim runtimes 27.0 and 27.1 both installed; remotes `origin` = haddadyousef/Waymark, `upstream` = aritroBh/OpenCane. exit=0 |
| baseline | 230ebf7 main (no rename) | `make test` | 919 tests in 23 suites passed, **exit=0** |
| rename | a5ce3c9 `waymark/g0-rename` | `make test` | 919 tests in 23 suites passed, **exit=0** |
| rename | a5ce3c9 | `WATCH=0 scripts/gen.sh` | generated from `.project.phone-only.yml`, **exit=0** |
| rename | a5ce3c9 | `make sim` | `** BUILD SUCCEEDED **`, 0 `error:` lines, 0 `warning:` lines, `BUNDLE_ID_PREFIX=com.example.waymark-dev` passed through. **exit=0** |

So D-01's push condition (`make test` exit 0 and `make sim` success on the Mac) is met. Yousef merged the branch as PR #1 (622ba38) at 14:25; nothing more to merge.

Note: the Mac runs 919 tests, my Linux loop 912. The 7-test difference is `HeadNodDetectorTests.swift` (set aside on Linux only).

**Correction:** my previous entry is stamped "14:40". The real time was about 14:20 (I wrote a wrong wall time). Times from here are read from a clock.

**Human facts from Akash (14:25), for `DECISIONS.md`:** @W
- Both GitHub accounts are his; he will use **`azphalt`**. Mac-session commits from now on are authored `azphalt <azphalt@users.noreply.github.com>` (plus the Claude co-author trailer my tooling requires; tell me if you want D-23's no-trailer rule to apply to the Mac too).
- **OpenCane is a project Akash developed with a team**, and Waymark is his new, more advanced project on top of it. That changes the framing of D-18 / the Devpost disclosure (it is our own prior work, not a third party's). Disclosure that the base existed before DubHacks still matters for the H2 rules.

**Not done in G0 yet:** `uitest` (both locations) and the device run (needs `ios/local.mk` with TEAM / DEVICE / `BUNDLE_PREFIX`, the phone, and the H5 hardware facts).

**Risk:** the Mac has **11 GiB free** (228 GiB disk, 95 % used, from the check log). Simulator runtimes, DerivedData (`ios/build`) and a phone build can eat that. @H Akash: free some space if you can; `make clean` removes `ios/build` if we run short.

**Blocked:** build lane on HOLD (D-04, H2 pending).

**Next:** `ios/scripts/waymark_g0.sh uitest`, then `device` once `local.mk` is filled in.

---

## repo: 95480f3 (branch `waymark/g0-rename` at a5ce3c9) | wall: Sat 14:40 PT

**Read:** W check-in 14:30, D-19 to D-22. All four accepted; nothing to object to.

**Done (evidence):**
- D-21 applied: `git rm -r ios/CaneKit/Resources/Assets.xcassets/AritroProfile.imageset` as commit a5ce3c9 on `waymark/g0-rename`. `ProfilePage.swift:80` already falls back to `person.crop.circle.fill` when the image is missing, so there is no code change. Verified only by reading the code; `make sim` on the Mac will confirm.
- Branch `waymark/g0-rename` rebased onto `main` 95480f3: rename c4b8efc, M1 ef9ff76, photo a5ce3c9. (Hashes changed from dbf548e / e05ce58 because of the rebase; content unchanged.)
- `M_NOTES.md` §10 added: L1 to L3 type signatures (design note only, no code), so L1 starts at K+0 without design time.
- GitHub: my identity is `akeeshcodes` (F-14). @H Akash to confirm `azphalt` vs `akeeshcodes`.

**In progress:** G0. Akash has not run the batch yet (his tree is still at fe86e10 with `origin` = aritroBh, checked 14:38 over the file bridge).

**Blocked:** build lane on HOLD (D-04, H2 pending). No Waymark Swift code written or pushed.

**Questions:** none new.

**Next:** read G0 logs as soon as Akash runs `ios/scripts/waymark_g0.sh check`, `baseline`, `rename`; merge the branch into `main` only if `make test` and `make sim` both exit 0.

---

## repo: ce106c1 | wall: Sat 14:25 PT

**Plan v1.1 read.** Also re-read `WAYMARK_DESIGN.md` §0–4, 8, 9, 13, 14, 18.

**Acks (contracts, plan §5):**
- **ack 5.2** `waymark.priors.v1` as amended (`bbox_lnglat`, 7 types incl. `crosswalk`, severity 1–3, `n_unsure`, `cluster_size`, `label_date`). Swift decode tests will target the 5.2 example verbatim until `contracts/golden/` lands.
- **ack 5.3** belief model. I re-computed every row of the worked table independently (Python, double): 0.75 / 0.5 / 0.6 / 0.666667 / 0.5 / 0.6 / 0.714286 — all match.
- **ack 5.4** thresholds: 1/6, 0.2, 0.2, 1/3 — match.
- Question, not an objection, on 5.2 `severity`: the API field is `median_severity`. If a cluster has an even number of labels, can the median be fractional (e.g. 1.5)? The verified samples were integers. Please state the rounding rule (round half up? floor?) or keep `severity` as a number 1–3 in the schema. @W
- Question on 5.3: `n_eff` is defined but nothing reads it yet. Do you want `WaymarkAlertPolicy` to require a minimum `n_eff`, or is it display-only? Display-only is my default. @W

**Done (evidence):**
- **Push works from this session** (14:18). `add_repo haddadyousef/waymark` with push access succeeded; this session's GitHub identity is **`akeeshcodes`**. Pulled `ce106c1` (W's seed on top of `fe86e10`). This entry is the first Mac commit. ⚠ DECISIONS F-13 / H3 name Akash's username as `azphalt`; the account linked to this Mac session is `akeeshcodes`. @H please confirm which one is Akash's, and that whichever was invited has Write access. @W
- 7.1.2 + 7.1.3: `M_NOTES.md` written (route format, polyline answer, signatures, resources, budgets, D-10 list, D-08 proposal, A1/E1 integration sketch).
- 7.1.4: Linux test loop confirmed. `swift test` in `ios/Logic`, baseline `fe86e10` → 912 passed, exit 0; with the rename commit → 912 passed, exit 0 (HeadNodDetectorTests set aside for Linux runs only).
- D-10 (now: in-app credit optional): independent of that, the rename commit restores the external routine name "OpenCane cane events" in 5 comments. No in-app credit text existed to restore (details `M_NOTES.md` §6). The commit is 84 files (was 85: `GrokBotEventTests.swift` is back to unchanged).
- M1 prepared as its own commit: `SIM_LAT` / `SIM_LON` (default 47.6540, −122.3050, D-07) used by `sim-grant`; `SIM_RUNTIME` auto-detects the newest installed iOS simulator runtime for `make sim17` (Xcode 27.1 may not have `iOS-27-0`).
- D-06 checked: XcodeGen already bundles everything in `ios/CaneKit/Resources/`; adding `waymark_priors.json` needs only `make gen` (`M_NOTES.md` §4).

**In progress:** G0 command batch handed to Akash (`waymark/logs/mac/g0.sh`, git-ignored, not committed).

**Blocked:**
- Build lane: on hold per D-04 until "hold released" is in `DECISIONS.md`.

**Questions:**
- @W the two above (severity rounding, `n_eff`).
- @W ack for the D-08 proposal: delete `AritroProfile.imageset` (fallback symbol already exists) — `M_NOTES.md` §7.
- @W UI tests (`make uitest`) start the bundled UIUC route ("Start route to CIF"). With the simulator parked in Seattle they may fail for distance reasons that have nothing to do with us. Plan: run `make uitest` once at the UIUC location (`SIM_LAT=40.1140 SIM_LON=-88.2249`) as the like-for-like gate, and once at Seattle as information. OK?
- @H (Akash) hardware facts (plan 9.2), GitHub username for the invite.

**Next:** G0 (Akash runs `g0.sh`), then report. When the hold lifts: L1 (`WaymarkLabelType`, `WaymarkPrior`, `WaymarkPriorSet`, `WaymarkIndex`), test-first on Linux.
