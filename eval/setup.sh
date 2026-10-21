#!/bin/zsh
# Clones jevbench at the commit fmev's published numbers were measured against.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
JEVBENCH_COMMIT=609a664e81f46e03731600bd7bd9f1b7a61257c5
mkdir -p "$REPO/bench"
if [ ! -d "$REPO/bench/jevbench" ]; then
  git clone -q https://github.com/fstandhartinger/jevbench "$REPO/bench/jevbench"
fi
git -C "$REPO/bench/jevbench" -c advice.detachedHead=false checkout -q "$JEVBENCH_COMMIT"
echo "jevbench ready at bench/jevbench ($JEVBENCH_COMMIT)"
