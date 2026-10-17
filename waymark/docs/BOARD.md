# Waymark board (single writer: Windows session / leader)

Last checked: Sat 2026-10-17 14:45 PT. **Repo: `github.com/haddadyousef/jiijeicfe`** (old `Waymark` repo is frozen, see PROVENANCE.md).
Windows confirmed `d2898e0` + this commit on `main`. Mac last status entry: 14:30 (old repo, `5b9227f`).
If this is more than an hour old, it is stale. Say "check mac" to the Windows chat.

**Phase:** prep lane. **Build lane:** HOLD until Yousef records the DubHacks rules outcome (D-04).
**Base project:** OpenCane `fe86e10`, pre-existing, disclosed (D-18, D-10, PROVENANCE.md). Repo is public (D-03).

## Tasks

| ID | Owner | Task | Status | Updated |
|---|---|---|---|---|
| W0, W1, O1 | W | Plan, seed docs, drafts, provenance | done | 14:45 |
| C0a | W | Schemas and golden fixtures | todo (prep lane), next | |
| C0b | W | Belief and threshold vectors, reference Python | todo (prep lane), next | |
| P0 | W | API discovery, raw samples | doing, waits on folder (H4) | |
| M0 | W | Baseline and docs on GitHub | done (old repo), superseded by the move (D-24) | 14:42 |
| Repo move | Mac/Akash | Re-point clone to `jiijeicfe` (plan 3.7), re-add newer Mac files | todo | |
| G0 | Mac | Fork builds, patch verified, phone run | simulator half green: `make test` 919/919, `make sim` exit 0. Left: uitest at 2 locations, device run | 14:30 |
| M1 | Mac | Seattle simulator location, sim17 runtime | in the repo (merged in PR #1), uitest pending | 14:30 |
| L1 to L3, A1 to A3, E1, E2, F1, T1 | Mac | Waymark Swift code | hold | |
| P1 to P6, V1, V2, S1, D1 | W | Pipeline, eval, server, dashboard | hold | |
| H2 | Yousef | DubHacks rules and schedule | todo, **the one thing holding the build lane** | |
| H3 | Yousef | GitHub link, collaborator, push access | done | 14:30 |
| H4 | Yousef | Windows `Waymark` folder | todo | |
| H5 | Akash | Hardware facts (iPhone, LiDAR, team ID, watch, mount) | partly: Mac facts in, phone facts missing | |
| H7 | both | Spotter and go/no-go | todo | |

## Blockers

- Build lane: DubHacks rules unread (H2).
- Device run: needs `ios/local.mk` (TEAM, DEVICE, BUNDLE_PREFIX) and the phone facts (H5).
- Mac disk: 11 GiB free. Free space or `make clean` if builds fail.

## Next three actions

- **Windows:** C0a and C0b; P0 once the folder is granted.
- **Mac:** do the repo move (3.7), then uitest and the device run.
- **Humans:** Yousef H2 and H4. Akash H5 and free disk space.
