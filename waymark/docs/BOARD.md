# Waymark board (single writer: Windows session / leader)

Last checked: Sat 2026-10-17 22:02 PT. **Repo: `github.com/haddadyousef/jiijeicfe`** (old `Waymark` repo is frozen, see PROVENANCE.md).
Windows confirmed `d2898e0` + this commit on `main`. Mac last status entry: 14:30 (old repo, `5b9227f`).
If this is more than an hour old, it is stale. Say "check mac" to the Windows chat.

**Phase:** build lane OPEN (hold released by Yousef at 14:52, D-28). Mac and Windows may write feature code.
**Base project:** OpenCane `fe86e10`, pre-existing, disclosed (D-18, D-10, PROVENANCE.md). Repo is public (D-03).

## Tasks

| ID | Owner | Task | Status | Updated |
|---|---|---|---|---|
| W0, W1, O1 | W | Plan, seed docs, drafts, provenance | done | 14:45 |
| C0a | W | Schemas and golden fixtures | done (2ec1887), Mac ack pending | 14:50 |
| C0b | W | Belief and threshold vectors, reference Python | done (2ec1887), Mac ack pending | 14:50 |
| P0 | W | API discovery, raw samples | done | 15:45 |
| M0 | W | Baseline and docs on GitHub | done (old repo), superseded by the move (D-24) | 14:42 |
| Repo move | Yousef, Akash | Collaborator access and plan 3.7 | done (Mac moved at 15:15) | 15:40 |
| G0 | Mac | Fork builds, patch verified, phone run | app installed on Akash's iPhone 17 Pro (LiDAR). Left: trust the profile on the phone, uitest | 15:05 |
| M1 | Mac | Seattle simulator location, sim17 runtime | in the repo (merged in PR #1), uitest pending | 14:30 |
| L1 to L3 | Mac | Logic layer | done: merged, Mac `make test` 1007 passed exit 0, uitest green | 15:52 |
| A1 | Mac | WaymarkEngine, session, switch | merged (4dbfa2c) with the Mac's own review fixes; speaks at `.scene`, only into silence | 16:25 |
| D-35 items 1 to 3 | Mac | Seattle route bundled, simulator point, X-e2e | done, merged (#5, #6); `make e2e-waymark` PASS | 17:30 |
| X-e2e | Mac | Replay with synthetic priors | done (see above) | 17:30 |
| E1, E2 | Mac | Evidence from LiDAR / curb events / spotter taps; export script | merged (#6, cd3e1a8), `make test` 1044 passed; D-36 curb-ramp ruling | 17:30 |
| A2, A3, F1, T1 | Mac | Card and map, field walk, tuning | phone install done (Akash's phone); F1 waits for a spotter, daylight and a clean `make test` / `make uitest` on `main` | 17:30 |
| UI rework | Mac (Akash request) | Palette, simpler pages, UI v3 Graphite | passes 1, 2 and v3 merged (#4, #5, #7); `make uitest` not re-run on v3 | 17:58 |
| P1 to P4, P6 | W | Pipeline and real bundle | done: 3,405 labels in `ios/CaneKit/Resources/waymark_priors.json` (e1d466e) | 15:12 |
| V1 | W | Eval harness (metrics 1, 2, 7) | done (c583e5f), 20 tests | 15:35 |
| V2 | W | Calibration, sweep, staleness, positional error | built on synthetic data (8ab798b); real numbers need F1 | 16:05 |
| P5 | W | Route ranking and demo files | done: route chosen by Yousef (D-34), files in `waymark/demo/`, needs a walk (H7) | 15:45 |
| S1, D1 | W | Server and dashboard (stretch) | not started | 16:05 |
| H2 | Yousef | DubHacks rules and schedule | hold released; rules text and schedule still not on file | |
| H3 | Yousef | GitHub link, collaborator, push access | done | 14:30 |
| H4 | Yousef | Windows `Waymark` folder | done (C:\Users\youse\Waymark), fetch run | 15:06 |
| H5 | Akash | Hardware facts (iPhone, LiDAR, team ID, watch, mount) | partly: Mac facts in, phone facts missing | |
| H7 | both | Spotter and go/no-go | todo | |

## Blockers

- Akash: trust the developer profile on the phone (Settings, General, VPN and Device Management).
- Device run: needs `ios/local.mk` (TEAM, DEVICE, BUNDLE_PREFIX) and the phone facts (H5).
- Mac disk: 11 GiB free. Free space or `make clean` if builds fail.

## Next three actions

- **Windows:** V1 eval harness, then P5 route ranking.
- **Mac:** do the repo move (3.7), then uitest and the device run.
- **Humans:** Yousef H2 (rules text). Akash H5 and free disk space.
