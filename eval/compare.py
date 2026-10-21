"""Prints headline metrics for fmev jevbench runs: compare.py bench/runs/<name> [...]

AUROC: how well top-option confidence separates right answers from wrong ones (0.5 = chance).
"""
import json
import os
import statistics
import sys


def auroc(rows):
    """P(a correct answer has higher top probability than a wrong one); ties count half."""
    pos = [max(r["probs"].values()) for r in rows if r["ok"] and r["correct"]]
    neg = [max(r["probs"].values()) for r in rows if r["ok"] and not r["correct"]]
    if not pos or not neg:
        return None
    wins = sum((p > q) + 0.5 * (p == q) for p in pos for q in neg)
    return wins / (len(pos) * len(neg))

for root in sys.argv[1:]:
    for s in ["original", "easy", "hard"]:
        try:
            m = json.load(open(f"{root}/{s}/summary.json"))
            rows = [json.loads(l) for l in open(f"{root}/{s}/results.jsonl")]
        except FileNotFoundError:
            continue
        lat = sorted(r["latency_s"] for r in rows if r["latency_s"] is not None)
        ece = m["ece"]["ece"] if isinstance(m.get("ece"), dict) else m.get("ece")
        p95 = lat[int(0.95 * (len(lat) - 1))]
        print(f"{os.path.basename(root.rstrip('/')):<24} {s:<9} n={len(rows):<4} acc={m['accuracy']:.3f} brier={m['brier_mean']:.3f} "
              f"ece={ece if ece is None else round(ece, 3)} p50={statistics.median(lat):.2f}s p95={p95:.2f}s "
              f"auroc={auroc(rows) if auroc(rows) is None else round(auroc(rows), 3)} fail={sum(not r['ok'] for r in rows)}")
