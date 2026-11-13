#!/bin/sh
# The windowed program end to end: graal304-torque opens its window (X11,
# Win32 or Cocoa), boots the smoke install, starts offline mode and walks
# right for one second, then writes its trace and the last window image.
# Needs build/graal304-torque, make lib and a desktop (Xvfb on Linux CI).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/../build"
LIB=""
for L in libGame304Lib.so Game304Lib.dll libGame304Lib.dylib; do
  [ -f "$BUILD/lib/$L" ] && LIB="$BUILD/lib/$L" && break
done
[ -n "$LIB" ] || { echo "window: no game library in $BUILD/lib (make lib)"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/install/levels/tutorial" "$WORK/prefs"
cp "$HERE/smoke/main.cs" "$WORK/install/main.cs"
python3 - "$WORK/install/levels/tutorial/offlinetutorial_b-2.graal" <<'PY'
import sys
rows = ["GLEVNW01"] + ["BOARD 0 %d 64 0 %s" % (y, "AA" * 64) for y in range(64)]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
PY
"$BUILD/graal304-torque" --root "$WORK/install" --prefs "$WORK/prefs" --game "$LIB" \
  --steps "$HERE/smoke/steps.txt" --seconds 3 --trace "$WORK/trace.txt" --shot "$WORK/frame.bmp" \
  > "$WORK/console.txt"
cat "$WORK/console.txt"
grep -v '^host stub' "$WORK/trace.txt"
fail() { echo "window: $1"; exit 1; }
grep -q 'Graal activated!' "$WORK/console.txt" || fail "no Graal activated! line"
grep -q '^canvas content AdventureGui' "$WORK/trace.txt" || fail "AdventureGui was not shown"
# about 20 frames at 0.5 tiles from x = 30; the window paces to the clock,
# so allow a frame either way
grep -Eq '^player offlinetutorial_b-2.graal (39|40|41)\.[0-9]+ 30\.00 3, state 8' "$WORK/trace.txt" ||
  fail "the player did not walk about 10 tiles"
[ "$(wc -c < "$WORK/frame.bmp")" -eq 1440054 ] || fail "the window image is not 800 x 600"
echo "window: passed"
