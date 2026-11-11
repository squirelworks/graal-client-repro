#!/bin/sh
# Run every build's test program. scripts/build.sh first.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
. "$ROOT/scripts/v7.sh"
# blocks the run, unless FOLDER is a v7 client (scripts/v7.sh)
fail() {
  if [ "${V7_STRICT:-}" != 1 ] && is_v7 "$1"; then v7_warn "$1" "$2"
  else FAIL=1
  fi
}
for T in "$ROOT"/build/*/Test*; do
  [ -x "$T" ] || continue
  TB=$(basename "$(dirname "$T")")
  echo "== $T"
  # The tests are built with the heap tracer. It writes its report from a
  # unit finalization, which runs after the runtime has already flushed
  # stderr. Redirected stderr is a 256-byte buffer, so the tail of the
  # report never reaches the file: the "0 unfreed memory blocks" line is
  # often the byte that falls on that boundary, and a clean run is then
  # reported as a leak. heaptrc closes a log= file itself, which flushes
  # the whole report. A Windows compiler does not open an MSYS path.
  HEAPLOG="$T.heap"
  rm -f "$HEAPLOG"
  LOG=$HEAPLOG
  case $(uname -s) in
    MINGW*|MSYS*|CYGWIN*) LOG=$(cygpath -w "$HEAPLOG") ;;
  esac
  HEAPTRC="log=$LOG" "$T" || fail "$TB" "$(basename "$T") failed"
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
exit $FAIL
