#!/bin/sh
# Loopback acceptance check: log a rebuilt client into seihai-gserver and
# require login + board.
#   scripts/loopback.sh GSERVER_BIN [BUILD]
# GSERVER_BIN: a built seihai-gserver (https://github.com/squirelworks/seihai-gserver).
# BUILD: folder name, default graal-2.05r2-GNW03081.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GS=$1
B=${2:-graal-2.05r2-GNW03081}
GSDIR=$(cd "$(dirname "$GS")/../.." && pwd)
WORK=$(mktemp -d)
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT
cp -r "$GSDIR/world" "$WORK/world"
GRAAL_PW=loopbackpw "$GS" account loop1 --password-env GRAAL_PW --world "$WORK/world"
"$GS" --world "$WORK/world" --verbose > "$WORK/gserver.log" 2>&1 &
PID=$!
sleep 2
CLIENT=$(ls "$ROOT/build/$B"/Graal* | head -1)
set +e
GRAAL_PW=loopbackpw "$CLIENT" --server 127.0.0.1:14802 --account loop1 \
  --frames 40 --dump "$ROOT/build/$B/loopback.bmp"
RC=$?
set -e
echo "--- gserver log"
cat "$WORK/gserver.log"
if ! grep -q "logged in" "$WORK/gserver.log"; then
  echo "gserver did not log the client in"; exit 1
fi
exit $RC
