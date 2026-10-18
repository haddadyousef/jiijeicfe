# Waymark: a sidewalk memory for a smart cane

**A white cane knows what's under its tip. Waymark knows what's 30 metres up the block.**

Waymark clips an iPhone to a white cane and gives it a memory of the sidewalk. Walk down The Ave and it
quietly tells you "Reported obstacle ahead" or "Reported missing curb ramp ahead" before the cane — or
the phone's LiDAR — could possibly reach it. It starts out knowing 3,405 hazards that volunteers mapped
across Seattle's U District, and it gets sharper every time someone walks the route, because it keeps
score of which reports turned out to be true.

Built at DubHacks '26 by **Yousef Haddad** (UW CS; data, evaluation, plan) and **Akash Tadikonda**
(iOS app). 

## The problem

A white cane finds what is at foot level. An iPhone clipped to the cane can see further with LiDAR, but
only a few metres, and it cannot tell that a curb ramp is missing or a slab is lifted. Other people
have already looked at these sidewalks: the University of Washington's **Project Sidewalk** has volunteers
label curb ramps, missing ramps, obstacles, surface problems and missing sidewalks from street-level
imagery. Waymark turns that public map into spoken warnings that arrive early, and then checks the map
against what the walker actually meets.

## The cool parts

- **Sidewalk memory, offline.** 3,405 Project Sidewalk reports ship inside the app. No signal under the
  trees on The Ave? Doesn't matter.
- **Warns ahead.** Walking the demo route, the app says things like "Reported obstacle ahead" or
  "Reported curb ramp" before you get there. It always says "reported": it is a report, not a
  measurement.
- **Never gets in the way.** Waymark speaks at the lowest priority and only into silence. It never
  speaks over, or delays, the cane's own safety cues (head height, close obstacle, navigation).
- **Shows its confidence.** Every report has a likelihood. A map of reports along the route shows each
  one by colour and shape (colour-blind safe), with its source, imagery date and votes.
- **Learns.** A LiDAR pass that finds the obstacle confirms it. A clean pass that finds nothing
  contradicts it. A sighted spotter walking alongside can tap **Confirm** or **Not there**. The
  confidence moves and is remembered on the phone ("Not there · 50 % → 43 % · spotter"). A report that
  can no longer be trusted stops being announced. If the phone cannot tell, it changes nothing.
- **Sees the whole block.** A map of reports draws every hazard along the route: amber circles for "almost
  certainly there", lemon diamonds for "maybe", sky-blue rings for "probably gone". Tap one for when the
  street imagery was taken and how many volunteers agreed.
- **Stays out of the way on the Guide.** One chip turns it on. While you walk, one card under Stop says
  what's next: "Reported curb ramp · 1 m · 92 % likely". The cane's own controls never move.
- **Lives on the cane.** LiDAR obstacle lanes, ground drop-off detection, haptic taps on the handle, a
  spatial audio beacon in AirPods, Siri and the Action button, a Live Activity on the lock screen, and a
  "Where am I" scene description — all still there, with Waymark layered on top.
- **Is measured.** An evaluation tool turns the recorded walks into hit rates with error bars, how well
  the stated likelihoods match what happens, how sensor and spotter agree, and how old imagery affects
  accuracy.

## The demo route

**The Ave (University Way NE), from NE 42nd St to NE 50th St**: about 730 m, nine waypoints, three
crossings, straight north through the U District. On the real map this stretch has 47 curb ramps,
1 obstacle and 2 surface problems. The "memory learned" moment in the replay uses **clearly labelled
synthetic** labels, because the real stretch has few hazards. Details and caveats:
[`waymark/demo/README.md`](waymark/demo/README.md).

## How it works

```
Project Sidewalk labels (CC0) ──► pipeline ──► priors bundle (3,405 labels, in the app, works offline)
                                                       │
walker's position ─► labels ahead ─► belief (Beta, ages with time) ─► cost-weighted threshold ─► spoken report
                                                       ▲
         LiDAR passes + curb events + spotter taps ────┘ (evidence: confirmed / contradicted / unverifiable)
                                                       │
                                     export (no coordinates) ─► evaluation tool ─► numbers
```

- **Priors.** `waymark/pipeline/` fetches Project Sidewalk label clusters and street geometry for the
  U District and builds one small bundle (`ios/CaneKit/Resources/waymark_priors.json`: 1,489 curb ramps,
  531 surface problems, 501 missing curb ramps, 398 obstacles, 322 no-sidewalk, 89 crosswalks, 75
  other). The labeler ids are never kept.
- **Belief and thresholds.** Each label becomes a probability that it is still there. Evidence fades
  with time (on a scale of about 60 days for obstacles, 120 for surface problems, a year for the rest). A label is spoken only when the
  probability beats a threshold set from the cost of a false alarm against the cost of a miss.
- **Evidence.** What counts as confirm, contradict or "cannot tell" is conservative and written down
  ([`waymark/docs/WAYMARK_DESIGN.md`](waymark/docs/WAYMARK_DESIGN.md) §9). Most curb and surface evidence
  comes from the spotter, because the phone cannot judge those yet.
- **Evaluation.** `waymark/eval/` reads the exported evidence and reports the metrics.

## Status

- **Built and tested:** the data pipeline (44 tests), the evaluation tool (36 tests), the app logic
  (1,128 tests passing on the Mac), the full UI test suite on the simulator (14 run, 0 failures, 1
  skipped by design, with the island-tour fix), a replay of the whole Ave route through the real app in
  which every one of the 6 planted reports was spoken at the right moment and never over a safety cue,
  the confidence map, and memory that survives quitting the app (a "Not there" stays at 43 % after a
  relaunch).
- **On the phone:** installed and running on an iPhone 17 Pro.
- **Field walk:** _results go here — reports confirmed, reports contradicted, obstacles flagged out of
  obstacles met, and how many the phone could not judge, each with its count._
- **Not yet measured on real sidewalks:** no recorded walk exists yet. Every number in the evaluation
  report on this repo comes from generated test data and is marked **SYNTHETIC**. The first real numbers
  come from a paper checking walk of the route and a live walk with the app and a spotter.
- **Known limits.** Street geometry is the street centreline, not the sidewalk. Crossings are inferred
  from labels. 88 % of the labels use imagery from 2019 or earlier, which is exactly why the app checks
  them.

## Data and credits

- Labels: **UW Project Sidewalk** (CC0), Seattle. No labeler ids are stored.
- Street geometry: **© OpenStreetMap contributors** (ODbL), via Project Sidewalk.


## Repo map

| Path | What |
|---|---|
| [`waymark/docs/`](waymark/docs/) | Plan, design, decisions (`DECISIONS.md`), board, status files, provenance, Project Sidewalk API notes |
| [`waymark/pipeline/`](waymark/pipeline/) | Python: fetch Project Sidewalk, build the priors bundle, rank routes, write the demo route |
| [`waymark/contracts/`](waymark/contracts/) | JSON schemas for priors and evidence, golden fixtures, reference belief code |
| [`waymark/eval/`](waymark/eval/) | Python: the evaluation tool, with a synthetic fixture |
| [`waymark/demo/`](waymark/demo/) | The Ave route in the app's format, replay trace, GPX, synthetic test labels |
| [`waymark/field/`](waymark/field/) | Checklist for the paper checking walk |
| [`ios/CaneKit/Waymark/`](ios/CaneKit/Waymark/), [`ios/Logic/Sources/CaneKitLogic/Waymark/`](ios/Logic/Sources/CaneKitLogic/Waymark/) | Waymark's app code and its tested logic |
| [`ios/`](ios/) | The iPhone app, watch app and widget. See [`ios/README.md`](ios/README.md) |
| [`docs/`](docs/), [`hardware/`](hardware/) | App design notes, cue research, the cane mount |
| [`archive/`](archive/) | Old leftovers kept for the record; not part of the walkthrough |

## Quick start

**Data and evaluation (Windows or Mac; Python 3.10+).**

```sh
cd waymark/pipeline && pip install -r requirements.txt
py -m wm_pipeline.run all          # fetch + build the priors bundle (needs the Project Sidewalk host)
py -m wm_pipeline.run demo --pick 3   # regenerate the Ave demo route files
py -m pytest -q                    # 44 tests

cd ../eval && pip install -r requirements.txt
py -m wm_eval.run --synthetic --out out/synthetic   # report on generated data, marked SYNTHETIC
py -m pytest -q                    # 36 tests
```

Use `python3` instead of `py` on a Mac. After a real walk:
`python3 ios/scripts/waymark_export.py --evidence evidence.jsonl --log canekit-*.jsonl --out <dir>`
strips coordinates from the phone's files, and `py -m wm_eval.run --priors ios/CaneKit/Resources/waymark_priors.json --evidence ... --out out/walk1` reports on them.

**App (Mac with Xcode 27 and `brew install xcodegen`).**

```sh
cd ios
make test            # logic tests; works with the Swift toolchain alone
make gen             # generate the Xcode project (needed after pulling new files)
make sim             # simulator build; the simulator parks at the start of the Ave route
make e2e-waymark     # replay the Ave route through the real app with synthetic labels (~6 min)
make tour-waymark    # screenshots of the Waymark screens
make run             # build, install and launch on the phone (needs ios/local.mk, see ios/README.md)
```

Sidewalk memory is **off by default**. Turn it on from the Guide screen. Automated runs are silent.
API keys, signing and the phone setup are in [`ios/README.md`](ios/README.md); never commit
`ios/CaneKit/Resources/Secrets.plist`.

## Safety

Waymark is a research prototype and an aid, not a replacement for a cane or for the walker's judgment. It
never speaks over the cane's own safety cues, it labels everything it says as a report, and field tests
need a sighted spotter within arm's reach at every crossing.
