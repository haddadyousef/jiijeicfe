# Waymark contracts (C0)

Owner: Windows session. Mac reviews; any change needs an `ack` line in `docs/STATUS_M.md`.
Normative text: `docs/WAYMARK_PLAN.md` sections 5.2 (priors), 5.3 (belief), 5.4 (threshold). These files are the executable form.

## Files

| File | What | Who consumes |
|---|---|---|
| `priors_v1.schema.json` | Producer contract for the priors bundle (strict) | pipeline (P2 to P4), Python tests |
| `evidence_v1.schema.json` | One evidence line (JSONL) | Swift writer (E1), eval harness (V1) |
| `golden/priors_sample.json` | Valid bundle: label 1 is **real** Project Sidewalk data, labels 2 to 7 are **synthetic** (ids from 9000000001) | Swift decode tests (L1), Python tests |
| `golden/priors_unknown_type.json` | Same plus a label of type `future_type`: decoder must map it to `other` | Swift L1 |
| `golden/priors_invalid_cases.json` | 12 broken bundles with `decoder_must_reject` flags | Swift L1 |
| `golden/evidence_sample.jsonl` | 8 synthetic evidence lines, all outcomes and sensors | Swift E1 encode tests, harness |
| `golden/belief_vectors.json` | Belief replays with expected `a`, `b`, `p`, `n_eff` | Swift L2 (tolerance 1e-9) |
| `golden/threshold_vectors.json` | `tau` values and alert decisions | Swift L2 (tolerance 1e-12) |
| `ref/belief.py` | Reference belief and threshold (plan 5.3, 5.4) | tests, eval harness, server |
| `ref/validate.py` | Schema plus semantic validation | pipeline, tests |
| `ref/make_golden.py` | Deterministic generator for everything in `golden/` | tests |

## Rules

- Golden files are generated. Change `ref/make_golden.py`, run it, commit both. A test fails if the files differ from the generator output.
- If a golden file changes, the Swift tests change in the same pull request.
- Priors: `type` is an open enum. The producer emits only the seven known types; decoders map anything else to `other`. `severity` is a number in [1, 3] or null. Labels are sorted ascending by `source_cluster_id` (numeric). Coordinates have at most 6 decimals. The `users` field of the Project Sidewalk API is never copied.
- Evidence: Swift tests compare an encoded line with the golden line as **parsed JSON** (same keys, same values, floats within 1e-9), not byte for byte. Float formatting differs between Swift and Python. Never emit a field named `t` or `kind`.
- Belief events replay in time order; ties keep the listed order. A read earlier than an event is taken before it.
- Synthetic data is labeled: ids from 9000000001 and `build: "waymark-synthetic-golden"`. Never present it as field data.

## Run

```
cd waymark/contracts
python -m venv .venv && . .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python ref/make_golden.py     # regenerate golden/ (only when you changed the generator)
python -m pytest -q
```
