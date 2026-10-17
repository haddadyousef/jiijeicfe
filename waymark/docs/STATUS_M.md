# STATUS_M — Mac session status (newest entry on top)

Owner: Mac session (Akash's account). Format per plan v1.1 §3.3.

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
