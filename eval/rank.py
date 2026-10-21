"""Ranks fmev runs against the systems jevbench v1.2 published per-item outcomes for.

Uses the same 231 public items and jevbench's v1.3 chance-corrected Intelligence
(easy, standard and hard tiers; the held-out judge tier is unavailable), so it is
not the official JevBench score.

Usage: python3 eval/rank.py bench/runs/<name> [...]
"""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JEVBENCH = os.path.join(REPO, "bench", "jevbench")
sys.path.insert(0, JEVBENCH)
from jevbench.composite_v13 import intelligence  # noqa: E402

published = json.load(open(os.path.join(JEVBENCH, "results/v1.2/jevbench-v1.2-per-task.json")))
tier_of = {t["id"]: t["tier"] for t in published["tasks"]}
TIERS = ["easy", "standard", "hard"]


def row(name, outcomes, partial=False):
    acc = {}
    for tier in TIERS:
        ids = [i for i, t in tier_of.items() if t == tier]
        acc[tier] = sum(outcomes.get(i) == "c" for i in ids) / len(ids)
    missing = any(outcomes.get(i, "n") == "n" for i in tier_of)
    return dict(name=name, **acc, intel=intelligence(acc), partial=partial or missing)


rows = [row(v["display"], {k: o[0] for k, o in v["public_tasks"].items()}, v.get("partial"))
        for v in published["systems"].values()]
for root in sys.argv[1:]:
    outcomes = {}
    for s in ["original", "easy", "hard"]:
        for line in open(os.path.join(root, s, "results.jsonl")):
            r = json.loads(line)
            outcomes[r["task_id"]] = "c" if r["correct"] else "w"
    rows.append(row("▶ fmev " + os.path.basename(root.rstrip("/")), outcomes))

rows.sort(key=lambda r: -r["intel"])
print(f"{'#':>3} {'system':<58} {'easy':>6} {'std':>6} {'hard':>6} {'intel':>6}")
for i, r in enumerate(rows, 1):
    name = r["name"] + (" (partial)" if r["partial"] else "")
    print(f"{i:>3} {name[:58]:<58} {r['easy']:>6.1%} {r['standard']:>6.1%} {r['hard']:>6.1%} {r['intel']:>6.1f}")
