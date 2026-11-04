#!/bin/sh
# Build every client rebuild and its tests with Free Pascal in Delphi mode.
#   scripts/build.sh            all builds
#   scripts/build.sh graal-2.05r2-GNW03081
# Output: build/<folder>/
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=${FPC:-fpc}
FLAGS=${FPCFLAGS:--O2}
cd "$ROOT"
if [ $# -gt 0 ]; then BUILDS="$*"; else BUILDS=$(ls -d graal-*/ | tr -d /); fi
for B in $BUILDS; do
  OUT="$ROOT/build/$B"
  mkdir -p "$OUT"
  for P in "$B"/src/*.dpr "$B"/tests/*.dpr; do
    [ -f "$P" ] || continue
    echo "== $P"
    (cd "$(dirname "$P")" && "$FPC" -Mdelphi -Sh -vew $FLAGS \
      -Fu"$ROOT/common" -Fu"$ROOT/$B/src" -FE"$OUT" -FU"$OUT" "$(basename "$P")")
  done
done
