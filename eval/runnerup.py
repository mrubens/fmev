"""Checks a run's runner-ups: python3 eval/runnerup.py bench/runs/<baseline> bench/runs/<run>

On wrong answers with 3+ options, the runner-up is the option with the second-highest probability
(skipped when tied). Reports how often it is the right answer against chance (1/(n-1) per item), and
how many top-1 answers differ from the baseline run.
"""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SETS = ["original", "easy", "hard"]


def load(root):
    rows = {}
    for s in SETS:
        for line in open(os.path.join(root, s, "results.jsonl")):
            r = json.loads(line)
            rows[r["task_id"]] = r
    return rows


expected = {}
for s in SETS:
    for line in open(os.path.join(REPO, "bench/jevbench/datasets/public", f"{s}.jsonl")):
        t = json.loads(line)
        expected[t["id"]] = t["expected"]

baseline, run = load(sys.argv[1]), load(sys.argv[2])
changed = sum(1 for k, r in run.items() if r.get("predicted") != baseline.get(k, {}).get("predicted"))
print(f"top-1 answers differing from {os.path.basename(sys.argv[1])}: {changed}/{len(run)}")

hits = chance = n_items = 0
for k, r in run.items():
    probs = r.get("probs") or {}
    if not r["ok"] or r["correct"] or len(probs) < 3:
        continue
    ranked = sorted(probs.items(), key=lambda kv: -kv[1])
    if ranked[1][1] == ranked[2][1]:
        continue  # no distinct runner-up
    n_items += 1
    hits += ranked[1][0] == str(expected[k])
    chance += 1 / (len(probs) - 1)
if n_items:
    print(f"runner-up right on {hits}/{n_items} misses ({hits / n_items:.0%}); chance {chance / n_items:.0%}")
