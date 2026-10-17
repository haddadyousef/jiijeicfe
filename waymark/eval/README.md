# Waymark eval harness (V1)

Turns walk data into numbers we can defend. Python, no network. Owner: Windows.

```
pip install -r requirements.txt
py -m pytest -q                                       # 35 tests
py -m wm_eval.run --synthetic --out out/synthetic     # seeded fake walks, watermarked SYNTHETIC
py -m wm_eval.run --priors ..\..\ios\CaneKit\Resources\waymark_priors.json ^
                  --evidence evidence.jsonl --records waymark_records.jsonl --out out\walk1 [--holdout]
```

Outputs in `--out`: `summary.json` (sorted keys, byte-identical for identical inputs), `by_type.csv`, `report.md`, `outcome_rates.png`, `calibration.png`, `threshold_sweep.png`, `threshold_sweep.csv` (the plots and the csv appear when there is data for them).
The exit code is 1 if any evidence line fails the `waymark.evidence.v1` contract (use `--allow-rejected` to override).

## What V1 computes (design 10.2)

1. **Outcome rates per label type**: confirmed / contradicted / unverifiable with Wilson 95% intervals, plus the confirm rate among decisive lines. A cell with n under 5 prints "insufficient data".
2. **Sensor vs spotter**: per sensor group (lidar = torso + head, ground, vision) a 2x2 matrix with the spotter as reference, agreement and Cohen's kappa. Needs 5 paired labels. Several lines per label are reduced to one verdict by majority; a tie is left out and counted.
7. **Load and latency** from exported `waymark_load` / `waymark_cue` records.

3. **Calibration** (V2): predicted p, read from the reference belief just before each decisive spotter tap, against what the tap said. Brier score and a reliability plot. Fewer than 30 passes: raw counts only.
4. **Threshold sweep** (V2): tau 0.05 to 0.95 in steps of 0.01 per hazard type, cost = C_miss x misses + C_fa x false alarms, minimizer (ties to the smaller tau), cost at the default tau, and the minimizer at half and double C_miss. Needs 10 passes per type. With `--holdout` the minimizer comes from the tuning labels and the cost is reported on the hold-out labels.
5. **Staleness** (V2): confirm rate of spotter taps by imagery age, with a plain-words trend statement ("no clear trend" when the intervals overlap).
6. **Positional error** (V2): along-track offset of confirming sensor events; suggests `label_error` (90th percentile of the absolute offset) only with 20 or more events.

Calibration, sweep and the rest are built and tested on synthetic data; real numbers need the F1 walk. Expect the sweep to be flat until real contradicting evidence exists (see D-31).

## Input contract for metric 7 (asks of the Mac, E2 / A1)

Trip-log payloads are string maps, so numbers may arrive as strings; the loader coerces them. Fields, all milliseconds:

| record kind | field | meaning |
|---|---|---|
| `waymark_load` | `load_ms` | time to load and index the priors |
| `waymark_cue` | `lookup_ms` | time for the candidate lookup |
| `waymark_cue` | `latency_ms` | GPS fix to speech dispatch |
| `waymark_cue` | `suppressed_reason` | present when the cue was not spoken |

A field that no record carries is reported as "absent", never as zero. Records of other kinds are ignored.

## Rules this harness follows (design 10.3)

- Synthetic data lives in `fixtures/synthetic/`, comes from `wm_eval/synth.py` with a fixed seed (26), and a test fails if the committed files drift from the generator. Anything computed from a `waymark-synthetic*` build is watermarked in `summary.json`, `report.md` and the plot.
- Everything is deterministic. No clock, no randomness without a seed.
- `--holdout` reports only a seeded 30% of labels (split by label) so tuning can use the rest. Do not tune tau on the labels you report.
- Wilson intervals assume independent observations; several lines from one label are not independent, so intervals are optimistic. The report says so.
- Only evidence lines and `waymark_*` records are read. Never raw trip logs, never walker coordinates (D-14).
