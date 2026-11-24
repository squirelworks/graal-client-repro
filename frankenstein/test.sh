#!/bin/sh
# Checks the scaffold manifest. TODO: drive the real client at <server>:<port>.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
"$HERE/build.sh"
M="$ROOT/build/frankenstein/MANIFEST.txt"
test -s "$M"
grep -q '^name: frankenstein$' "$M"
grep -q '^status: scaffold$' "$M"
grep -q '^base: v6.113$' "$M"
grep -q '^graal3d: v5.120$' "$M"
grep -q '^udp: enabled$' "$M"
grep -q '^server: <server>$' "$M"
grep -q '^port: <port>$' "$M"
grep -q '^md5: <md5>$' "$M"
grep -E -q '^os: (macos|linux|windows)$' "$M"
OUT=$(sh "$ROOT/build/frankenstein/frankenstein.sh")
printf '%s\n' "$OUT" | grep -q 'v6.113'
printf '%s\n' "$OUT" | grep -q 'v5.120'
printf '%s\n' "$OUT" | grep -q 'UDP enabled'
echo "scaffold tests passed"
