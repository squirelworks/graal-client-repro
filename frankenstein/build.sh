#!/bin/sh
# Scaffold build for the Frankenstein client.
# TODO: replace this script with the real v6.113 + v5.120 Graal3D compile.
# macOS is the first playable target; Linux and Windows follow the same sources.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
OUT="$ROOT/build/frankenstein"
mkdir -p "$OUT"

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=unknown ;;
esac

cat > "$OUT/MANIFEST.txt" <<EOF
name: frankenstein
status: scaffold
base: v6.113
graal3d: v5.120
graal3d-repro: graal-5.12-G3D14097
udp: enabled
os: $OS
server: <server>
port: <port>
md5: <md5>
EOF

cp "$HERE/src/frankenstein.sh" "$OUT/frankenstein.sh"
echo "scaffold built for $OS -> $OUT"
