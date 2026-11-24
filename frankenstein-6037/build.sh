#!/bin/sh
# Scaffold build for the Frankenstein 6.037 client.
# TODO: replace this script with the real v6.037 + v5.120 Graal3D compile.
# macOS is the first playable target; Linux and Windows follow the same sources.
# No modern Torque3D base. The later engine is the older Quattro program.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
OUT="$ROOT/build/frankenstein-6037"
mkdir -p "$OUT"

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux) OS=linux ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=unknown ;;
esac

cat > "$OUT/MANIFEST.txt" <<EOF
name: frankenstein-6037
status: scaffold
base: v6.037
graal3d: v5.120
udp: enabled
os: $OS
server: <server>
port: <port>
md5: <md5>
EOF

cp "$HERE/src/frankenstein.sh" "$OUT/frankenstein.sh"
echo "scaffold built for $OS -> $OUT"
