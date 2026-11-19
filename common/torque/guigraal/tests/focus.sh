#!/bin/sh
# Linux (X11): a key held when graal304-torque loses focus is released, so
# the player stops (Debian lab check, #303: the player walked on until it
# left the level). Holds Right in the game window, moves the focus to
# another window, lets the key go there, and checks the trace.
# Needs build/graal304-torque, make lib, an X display (xvfb-run), xdotool
# and xmessage (x11-apps).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/../build"
LIB="$BUILD/lib/libGame304Lib.so"
[ -f "$LIB" ] || { echo "focus: no $LIB (make lib)"; exit 1; }
command -v xdotool >/dev/null && command -v xmessage >/dev/null ||
  { echo "focus: needs xdotool and xmessage"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/install/levels/tutorial" "$WORK/prefs"
cp "$HERE/smoke/main.cs" "$WORK/install/main.cs"
cat >> "$WORK/install/main.cs" <<'CS'
new ActionMap(moveMap);
moveMap.bind(keyboard, "right", moveRight);
moveMap.push();
CS
python3 - "$WORK/install/levels/tutorial/offlinetutorial_b-2.graal" <<'PY'
import sys
rows = ["GLEVNW01"] + ["BOARD 0 %d 64 0 %s" % (y, "AA" * 64) for y in range(64)]
open(sys.argv[1], "w").write("\n".join(rows) + "\n")
PY
printf '0 Adventure.startOfflineMode();\n' > "$WORK/steps.txt"
"$BUILD/graal304-torque" --nosound --root "$WORK/install" --prefs "$WORK/prefs" --game "$LIB" \
  --steps "$WORK/steps.txt" --seconds 6 --trace "$WORK/trace.txt" > "$WORK/console.txt" 2>&1 &
GAME=$!
sleep 1.5
WID=$(xdotool search --name "Graal 3.04" | head -1)
xdotool windowfocus --sync "$WID"
xdotool keydown --window "$WID" Right
sleep 0.5
xmessage -geometry +900+0 other &
OTHER=$!
sleep 0.5
xdotool windowfocus --sync "$(xdotool search --name xmessage | head -1)"
xdotool keyup Right
wait "$GAME"
kill "$OTHER" 2>/dev/null || true
grep -E 'right|^player' "$WORK/trace.txt"
grep -q 'right break: moveMap bind moveRight(0)' "$WORK/trace.txt" ||
  { echo "focus: the held key was not released on focus loss"; exit 1; }
# about half a second of walking from x = 30, not the rest of the run
grep -Eq '^player offlinetutorial_b-2.graal (3[0-9]|4[0-9])\.[0-9]+ 30\.00' "$WORK/trace.txt" ||
  { echo "focus: the player kept walking"; exit 1; }
echo "focus: passed"
