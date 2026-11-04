#!/bin/sh
# Run every build's test program. scripts/build.sh first.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
for T in "$ROOT"/build/*/Test*; do
  [ -x "$T" ] || continue
  echo "== $T"
  "$T" || FAIL=1
done
exit $FAIL
