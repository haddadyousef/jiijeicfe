# Waymark board (single writer: Windows session / leader)

Last checked: Sat 2026-10-17 15:45 PT. **Repo: `github.com/haddadyousef/jiijeicfe`** (old `Waymark` repo is frozen, see PROVENANCE.md).
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
| Repo move | Yousef, Akash | Add `azphalt` as collaborator on `jiijeicfe` (Mac was refused), then plan 3.7 | BLOCKED on Yousef (asked 15:20) | 15:35 |
| G0 | Mac | Fork builds, patch verified, phone run | app installed on Akash's iPhone 17 Pro (LiDAR). Left: trust the profile on the phone, uitest | 15:05 |
| M1 | Mac | Seattle simulator location, sim17 runtime | in the repo (merged in PR #1), uitest pending | 14:30 |
| L1 to L3 | Mac | Logic layer | written test-first, 77 new tests, branch `waymark/l1-l3` (old repo); `make test` on the Mac pending; W review R1 partly done | 15:35 |
| A1 to A3, E1, E2, F1, T1 | Mac | App layer, evidence, export, field walk | next, after L1 to L3 merges | 15:35 |
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

- Mac cannot reach `jiijeicfe` until Yousef adds `azphalt` as a collaborator. Bridge copies go to the old repo meanwhile (D-33).
- Akash: trust the developer profile on the phone (Settings, General, VPN and Device Management).
- Device run: needs `ios/local.mk` (TEAM, DEVICE, BUNDLE_PREFIX) and the phone facts (H5).
- Mac disk: 11 GiB free. Free space or `make clean` if builds fail.

## Next three actions

- **Windows:** V1 eval harness, then P5 route ranking.
- **Mac:** do the repo move (3.7), then uitest and the device run.
- **Humans:** Yousef H2 (rules text). Akash H5 and free disk space.
