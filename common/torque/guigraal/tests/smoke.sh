#!/bin/sh
# End-to-end check of tq-play with the Pascal game library: a stand-in
# install (tests/smoke/main.cs and a generated level), offline mode from
# script, one second of walking. Needs build/tq-play and make lib.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/../build"
LIB="$BUILD/lib/libGame304Lib.so"
[ -f "$LIB" ] || LIB="$BUILD/lib/Game304Lib.dll"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/install/levels/tutorial" "$WORK/prefs"
cp "$HERE/smoke/main.cs" "$WORK/install/main.cs"
# a 64 x 64 board of tile 0, which the built-in tile types let one walk on
python3 - "$WORK/install/levels/tutorial/offlinetutorial_b-2.graal" <<'PY'
import sys
rows = ["GLEVNW01"] + ["BOARD 0 %d 64 0 %s" % (y, "AA" * 64) for y in range(64)]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
PY
"$BUILD/tq-play" --root "$WORK/install" --prefs "$WORK/prefs" --game "$LIB" \
  --steps "$HERE/smoke/steps.txt" --fast --trace "$WORK/trace.txt" --log "$WORK/console.txt" \
  --shot "$WORK/frame.bmp"
cat "$WORK/console.txt"
grep -v '^host stub' "$WORK/trace.txt"
fail() { echo "smoke: $1"; exit 1; }
grep -qx 'Graal activated!' "$WORK/console.txt" || fail "no Graal activated! line"
grep -qx 'Player enters local level offlinetutorial_b-2.graal.' "$WORK/console.txt" || fail "no local level line"
grep -q '^canvas content AdventureGui$' "$WORK/trace.txt" || fail "AdventureGui was not shown"
# 20 frames at 0.5 tiles from x = 30
grep -q '^player offlinetutorial_b-2.graal 40.00 30.00 3, state 8$' "$WORK/trace.txt" || fail "the player did not walk 10 tiles"
[ "$(wc -c < "$WORK/frame.bmp")" -eq 1440054 ] || fail "the frame is not 800 x 600"
echo "smoke: passed"
