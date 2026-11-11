#!/bin/sh
# Local smoke for the portable 6.114 player. Not a Unity player build.
#   graal-6.114-worlds/smoke.sh [port]
# Builds the folder if worlds-player is not already executable.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLAYER="$ROOT/build/graal-6.114-worlds/worlds-player"
WORLD="$ROOT/graal-6.114-worlds/worlds/local-yard.txt"
PORT=${1:-14923}
RASTER="$ROOT/build/graal-6.114-worlds/local-yard.ppm"
if [ ! -x "$PLAYER" ]; then
  "$ROOT/scripts/build.sh" graal-6.114-worlds
fi
exec "$PLAYER" --smoke --port "$PORT" --account loop1 \
  --world "$WORLD" --raster "$RASTER" --moves e,e,e,s,e
