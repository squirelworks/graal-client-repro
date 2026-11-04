#!/bin/sh
# Build every client rebuild and its tests with Free Pascal in Delphi mode.
#   scripts/build.sh            all builds
#   scripts/build.sh graal-2.05r2-GNW03081
# Output: build/<folder>/
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=${FPC:-fpc}
FLAGS=${FPCFLAGS:--O2}
# The native Windows compiler cannot read MSYS paths (/d/a/...): give it
# mixed-form paths (D:/a/...) when cygpath is there.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
cd "$ROOT"
if [ $# -gt 0 ]; then BUILDS="$*"; else BUILDS=$(ls -d graal-*/ | tr -d /); fi
for B in $BUILDS; do
  OUT="$ROOT/build/$B"
  mkdir -p "$OUT"
  for P in "$B"/src/*.dpr "$B"/tests/*.dpr; do
    [ -f "$P" ] || continue
    echo "== $P"
    (cd "$(dirname "$P")" && "$FPC" -Mdelphi -Sh -vew $FLAGS \
      -Fu"$(native "$ROOT/common")" -Fu"$(native "$ROOT/$B/src")" \
      -FE"$(native "$OUT")" -FU"$(native "$OUT")" "$(basename "$P")")
  done
done
