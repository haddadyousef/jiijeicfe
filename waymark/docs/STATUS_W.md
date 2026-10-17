# Windows session status (single writer: Windows session). Newest entry on top.

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
