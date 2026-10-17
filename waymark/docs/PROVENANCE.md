# Provenance: what is pre-existing and what is new

Owner: Windows session. Keep this accurate; the Devpost, README and pitch quote it.

## Baseline

- Base project: OpenCane, `https://github.com/aritroBh/OpenCane`, commit `fe86e10`.
- OpenCane predates DubHacks '26 (built at an earlier hackathon, with its own history and contributors). Akash worked on it with a team (F-15). It is disclosed as **pre-existing work**; the DubHacks rules on that are checked in H2.
- Everything under `waymark/` and every Swift or Python file whose name or folder contains `Waymark` or `waymark` was written for this event.

## Repos

- **Current team repo:** `https://github.com/haddadyousef/jiijeicfe`. Created Sat 2026-10-17 14:37 PT as one "Initial commit". Its tree equals the old repo's `main` at `622ba38` (OpenCane `fe86e10`, plus the docs, the rename and signing commit, the Seattle simulator location change and the removal of one profile photo), except that `STATUS_M.md` was older.
- **Old repo, frozen:** `https://github.com/haddadyousef/Waymark`. Full commit history, including OpenCane's original commits and our first Waymark commits. Do not push there. Leave it up as the audit trail.

## How to see exactly what we changed

```sh
git remote add upstream https://github.com/aritroBh/OpenCane.git
git fetch upstream
git diff --stat fe86e10 HEAD -- . ':!waymark'     # edits to the base project
git ls-files waymark                                # all new files
git log --oneline <first-commit>..HEAD              # commits after the snapshot
```

Commits after the snapshot are prefixed `waymark:`. Commits before it are in the old repo.

## Claims we make

"Built on OpenCane (pre-existing, first built before DubHacks '26). Waymark, the sidewalk-memory layer, was built at DubHacks '26." Adjust once H2 gives the rule wording.
