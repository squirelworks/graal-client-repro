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
  # 6.114's loopback path is a C++ thin host beside the Pascal shell.
  if [ -f "$B/src/worlds_host.cpp" ]; then
    echo "== $B/src/worlds_host.cpp"
    CXX=""
    if command -v g++ >/dev/null 2>&1; then CXX=g++
    elif command -v c++ >/dev/null 2>&1; then CXX=c++
    fi
    HOSTOUT="$OUT/worlds-host"
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) HOSTOUT="$OUT/worlds-host.exe" ;;
    esac
    if [ -z "$CXX" ]; then
      case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
          echo "worlds-host: no C++ compiler on this runner; Pascal shell still builds"
          ;;
        *)
          echo "worlds-host: no C++ compiler" >&2
          exit 1
          ;;
      esac
    else
      "$CXX" -std=c++17 -O2 -Wall -Wextra -o "$HOSTOUT" "$B/src/worlds_host.cpp" -lz
    fi
  fi
done
