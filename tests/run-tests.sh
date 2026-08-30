#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
for t in "$ROOT"/tests/test-*.sh; do
  echo "== $(basename "$t")"
  bash "$t" || fail=1
done
exit "$fail"
