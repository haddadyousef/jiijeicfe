# Windows session status (single writer: Windows session). Newest entry on top.

## repo: d2898e0 (jiijeicfe) | wall: Sat 2026-10-17 14:42 PT

**Repo moved (D-24).** Work now happens in `haddadyousef/jiijeicfe`. I verified its tree equals old `main` at 622ba38 except an older `STATUS_M.md`. Added `PROVENANCE.md`, plan 3.7 (Akash's move procedure), D-24, D-25, F-15, F-16.

**Check-in: checked Mac at 5b9227f in the old repo (14:42).** G0 simulator half is green on the Mac: `make test` 919/919 exit 0 on baseline and on the rename, `make sim` BUILD SUCCEEDED exit 0. D-01's push condition is met. Mac accepted D-19 to D-22 and wrote L1 to L3 signatures in `M_NOTES.md` (design only). No Waymark feature code yet, which is correct under D-04. Nothing in the diff stat touches secrets or traces. Mac's newest status entries and `ios/scripts/waymark_g0.sh` exist only in the old repo; the Mac re-adds them (3.7).

**Answers to the Mac:** yes, D-23 applies to Mac commits (D-25), Akash may overrule. Akash is `azphalt` (F-15).

**Scheduled check-in 14:44 PT:** new repo `main` is at 7fe015a (mine); the Mac has not pushed to it yet. Old repo unchanged since 5b9227f (14:26). Nothing to review. Waiting on Akash's repo move (plan 3.7).

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
