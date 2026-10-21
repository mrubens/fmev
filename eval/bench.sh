#!/bin/zsh
# Benchmarks one fmev configuration on jevbench's public items (231 decisions).
#
# Usage: eval/bench.sh <name> [VAR=value ...]
#   eval/bench.sh verbal
#   eval/bench.sh verbal-c8 FMEV_CONCURRENCY=8
# Results go to bench/runs/<name>/{original,easy,hard}. Builds fmev first; run eval/setup.sh once.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
NAME=$1; shift
PORT=${FMEV_BENCH_PORT:-8797}
OUT="$REPO/bench/runs/$NAME"
[ -e "$OUT" ] && { echo "$OUT exists; jevbench never overwrites a run. Pick another name." >&2; exit 1; }

swift build -c release --package-path "$REPO" >/dev/null
env "$@" FMEV_PORT=$PORT "$REPO/.build/release/fmev" > "$REPO/bench/fmev-$NAME.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
for i in $(seq 1 60); do curl -s "localhost:$PORT/health" >/dev/null && break; perl -e 'select undef,undef,undef,0.5'; done
head -1 "$REPO/bench/fmev-$NAME.log"

cd "$REPO/bench/jevbench"
for s in original easy hard; do
  python3 -m jevbench.cli run --tasks datasets/public/$s.jsonl --adapter typesafe \
    --endpoint "http://127.0.0.1:$PORT" --key-env '' --model fmev \
    --cost-basis on_device_local_no_billing --reserve-usd 0 \
    --results "$OUT/$s/results.jsonl" --raw-dir "$OUT/$s/raw" --ledger "$OUT/ledger.jsonl" \
    --manifest "$OUT/$s/manifest.json" --run-label "fmev-$NAME" 2>&1 | tail -1
  python3 -m jevbench.cli summarize --tasks datasets/public/$s.jsonl --results "$OUT/$s/results.jsonl" \
    --public-export "$OUT/$s/summary.json" >/dev/null
done
python3 "$REPO/eval/compare.py" "$OUT"
