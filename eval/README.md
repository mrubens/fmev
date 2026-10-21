# Evaluating fmev

These scripts run [jevbench](https://github.com/fstandhartinger/jevbench)'s public items (231 decisions: 72 standard, 48 easy, 111 hard) against a local fmev server.

```bash
eval/setup.sh                              # clone jevbench at the pinned commit into bench/
eval/bench.sh verbal-anchored              # the default configuration
eval/bench.sh vote FMEV_MODE=vote          # any FMEV_* settings, as VAR=value
python3 eval/compare.py bench/runs/*       # accuracy, Brier, ECE, latency, AUROC per set
python3 eval/rank.py bench/runs/verbal-anchored
```

- `bench.sh` builds fmev, starts it on port 8797 with the given settings, runs all three sets, and writes results to `bench/runs/<name>/`. jevbench refuses to overwrite a run, so each name can only be used once.
- `rank.py` places runs among the systems jevbench v1.2 published per-item outcomes for, using jevbench's v1.3 chance-corrected Intelligence on the public tiers. It is not the official JevBench score, which also uses held-out items and weighs calibration, speed and cost.
- `bench/` is gitignored: it holds the jevbench checkout and run outputs.
- Latency depends on the Mac. The published numbers came from an M4 Max with nothing else running.
