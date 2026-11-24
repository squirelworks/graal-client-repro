#!/bin/sh
# Builds the client, runs its tests (the view, and Login -> 178 to a "3 "
# server -> the 6.03r7 TCP login and the 5.12 UDP link to login step 6 over
# loopback), then checks the staged manifest.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
JOBS=$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 2)
make -C "$HERE" -j"$JOBS" test
"$HERE/build.sh"
M="$ROOT/build/frankenstein-6037/MANIFEST.txt"
test -s "$M"
grep -q '^name: frankenstein-6037$' "$M"
grep -q '^status: experimental$' "$M"
grep -q '^base: v6.037$' "$M"
grep -q '^graal3d: v5.120$' "$M"
grep -q '^graal3d-repro: graal-5.12-G3D14097$' "$M"
grep -q '^udp: enabled$' "$M"
grep -q '^server: <server>$' "$M"
grep -q '^port: <port>$' "$M"
grep -q '^md5: <md5>$' "$M"
grep -E -q '^os: (macos|linux|windows)$' "$M"
P=$(sed -n 's/^program: //p' "$M")
test -s "$ROOT/build/frankenstein-6037/$P"
echo "frankenstein-6037 tests passed"
