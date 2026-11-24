#!/bin/sh
# Builds the Frankenstein 6.037 client (make) and stages it with its
# manifest under build/frankenstein-6037/ at the repo root, which the
# workflow uploads and the release job zips.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
OUT="$ROOT/build/frankenstein-6037"
mkdir -p "$OUT"

case "$(uname -s)" in
  Darwin) OS=macos; EXE= ;;
  Linux) OS=linux; EXE= ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows; EXE=.exe ;;
  *) OS=unknown; EXE= ;;
esac

JOBS=$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 2)
make -C "$HERE" -j"$JOBS" all
cp "$HERE/build/frankenstein-6037$EXE" "$OUT/"

cat > "$OUT/MANIFEST.txt" <<MANIFEST
name: frankenstein-6037
status: experimental
base: v6.037
graal3d: v5.120
graal3d-repro: graal-5.12-G3D14097
udp: enabled
os: $OS
program: frankenstein-6037$EXE
server: <server>
port: <port>
md5: <md5>
MANIFEST
echo "frankenstein-6037 built for $OS -> $OUT"
