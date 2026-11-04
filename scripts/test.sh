#!/bin/sh
# Run every build's test program. scripts/build.sh first.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
for T in "$ROOT"/build/*/Test*; do
  [ -x "$T" ] || continue
  echo "== $T"
  # the tests are built with the heap tracer; it reports on stderr at exit
  "$T" 2> "$T.heap" || FAIL=1
  cat "$T.heap" >&2
  if ! grep -q "^0 unfreed memory blocks" "$T.heap"; then
    echo "leak: $T left memory unfreed"; FAIL=1
  fi
done
exit $FAIL
