#!/bin/sh
# Run every build's test program. scripts/build.sh first.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
FAILED=""
. "$ROOT/scripts/v7.sh"
# blocks the run, unless FOLDER is a v7 client (scripts/v7.sh)
fail() {
  if [ "${V7_STRICT:-}" != 1 ] && is_v7 "$1"; then v7_warn "$1" "$2"
  else
    FAIL=1
    FAILED="$FAILED
  $1: $2"
    # GitHub shows annotations on the run page, so a failure in a log of
    # tens of thousands of lines can still be found.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error::$1: $2"; fi
  fi
}
# One test program: its output in T.out, the heap report in T.heap and its
# exit code in T.rc. Each runs with a temp folder of its own, because the
# programs of sibling builds write the same file names there (test119.nw)
# and run side by side below.
if [ "${1:-}" = --one ]; then
  T=$2
  HEAPLOG="$T.heap"
  rm -f "$HEAPLOG" "$T.rc"
  # The tests are built with the heap tracer. It writes its report from a
  # unit finalization, which runs after the runtime has already flushed
  # stderr. Redirected stderr is a 256-byte buffer, so the tail of the
  # report never reaches the file: the "0 unfreed memory blocks" line is
  # often the byte that falls on that boundary, and a clean run is then
  # reported as a leak. heaptrc closes a log= file itself, which flushes
  # the whole report. A Windows compiler does not open an MSYS path.
  LOG=$HEAPLOG
  TMPD=$(mktemp -d)
  WTMP=$TMPD
  case $(uname -s) in
    MINGW*|MSYS*|CYGWIN*) LOG=$(cygpath -w "$HEAPLOG"); WTMP=$(cygpath -w "$TMPD") ;;
  esac
  RC=0
  TMPDIR=$TMPD TEMP=$WTMP TMP=$WTMP HEAPTRC="log=$LOG" "$T" > "$T.out" 2>&1 || RC=$?
  rm -rf "$TMPD"
  echo "$RC" > "$T.rc"
  exit 0
fi
# The test programs, run TEST_JOBS at a time (default: one per CPU), then
# reported in order.
TESTS=""
for T in "$ROOT"/build/*/Test*; do
  case $T in *.out|*.heap|*.rc) continue ;; esac
  [ -x "$T" ] || continue
  TESTS="$TESTS $T"
done
JOBS=${TEST_JOBS:-$(nproc 2>/dev/null || echo 2)}
if [ -n "$TESTS" ]; then
  echo "== running$(echo $TESTS | wc -w) test programs, $JOBS at a time"
  printf '%s\n' $TESTS | xargs -P "$JOBS" -I{} sh "$ROOT/scripts/test.sh" --one {}
fi
for T in $TESTS; do
  TB=$(basename "$(dirname "$T")")
  HEAPLOG="$T.heap"
  echo "== $T"
  cat "$T.out" 2>/dev/null || true
  # The program's own FAIL lines go into the summary at the end too.
  if [ "$(cat "$T.rc" 2>/dev/null || echo missing)" != 0 ]; then
    fail "$TB" "$(basename "$T") failed
$(grep '^FAIL' "$T.out" 2>/dev/null | sed 's/^/    /')"
  fi
  if [ -f "$HEAPLOG" ]; then
    cat "$HEAPLOG" >&2
  fi
  if [ ! -f "$HEAPLOG" ] || ! grep -q "^0 unfreed memory blocks" "$HEAPLOG"; then
    echo "leak: $T left memory unfreed"; fail "$TB" "$(basename "$T") left memory unfreed"
  fi
done
for HOST in "$ROOT/build/graal-worlds-614-20240421/worlds-host" \
            "$ROOT/build/graal-worlds-614-20240421/worlds-host.exe"; do
  if [ -x "$HOST" ]; then
    echo "== $HOST --self-check"
    "$HOST" --self-check || fail graal-worlds-614-20240421 "worlds-host --self-check failed"
  fi
done
PLAYER="$ROOT/build/graal-worlds-614-20240421/worlds-player"
WORLD="$ROOT/graal-worlds-614-20240421/worlds/local-yard.txt"
if [ -x "$PLAYER" ]; then
  echo "== $PLAYER --self-check"
  "$PLAYER" --self-check --world "$WORLD" || fail graal-worlds-614-20240421 "worlds-player --self-check failed"
fi
if [ "$FAIL" -ne 0 ]; then
  echo "== failed:$FAILED"
fi
exit $FAIL
