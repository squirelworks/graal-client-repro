#!/bin/sh
# Build every client rebuild and its tests with Free Pascal in Delphi mode.
#   scripts/build.sh            all builds
#   scripts/build.sh graal-2.05r2-GNW03081
# Output: build/<folder>/
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=${FPC:-fpc}
FLAGS=${FPCFLAGS:--O2}
# Paths given to the compiler are relative to the .dpr's folder
# (<build>/src or <build>/tests): the native Windows compiler misreads
# MSYS (/d/a/...) and mixed (D:/a/...) absolute paths alike.
cd "$ROOT"
if [ $# -gt 0 ]; then BUILDS="$*"; else BUILDS=$(ls -d graal-*/ | tr -d /); fi
for B in $BUILDS; do
  OUT="$ROOT/build/$B"
  mkdir -p "$OUT"
  mkdir -p "$OUT/checked"
  for P in "$B"/src/*.dpr "$B"/tests/*.dpr; do
    [ -f "$P" ] || continue
    echo "== $P"
    # Tests are built with range and overflow checks and the heap tracer
    # (-gh), into their own unit folder so the client's units stay -O2.
    case "$P" in
      */tests/*) EXTRA="-Cr -Co -gh -gl"; UNITS="../../build/$B/checked" ;;
      *) EXTRA=""; UNITS="../../build/$B" ;;
    esac
    # set -f: FPCFLAGS may hold FPC's own * wildcard, not a shell glob
    (set -f; cd "$(dirname "$P")" && "$FPC" -Mdelphi -Sh -vew $FLAGS $EXTRA \
      -Fu../../common -Fu../src -FE"../../build/$B" -FU"$UNITS" \
      "$(basename "$P")")
  done
done
