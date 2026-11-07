#!/bin/sh
# Run every build's test program. scripts/build.sh first.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
for T in "$ROOT"/build/*/Test*; do
  [ -x "$T" ] || continue
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
  HEAPTRC="log=$LOG" "$T" || FAIL=1
  if [ -f "$HEAPLOG" ]; then
    cat "$HEAPLOG" >&2
  fi
  if [ ! -f "$HEAPLOG" ] || ! grep -q "^0 unfreed memory blocks" "$HEAPLOG"; then
    echo "leak: $T left memory unfreed"; FAIL=1
  fi
done
for HOST in "$ROOT/build/graal-6.114-worlds/worlds-host" \
            "$ROOT/build/graal-6.114-worlds/worlds-host.exe"; do
  if [ -x "$HOST" ]; then
    echo "== $HOST --self-check"
    "$HOST" --self-check || FAIL=1
  fi
done
exit $FAIL
