#!/bin/sh
# Loopback acceptance check: log two copies of a rebuilt client into
# seihai-gserver. Both must log in and load the board, and the second must
# see the first in its level. Then one walks through a level link.
# A folder that builds worlds-host is pointed at 127.0.0.1 instead. That
# path sends one login-shaped frame and does not require a finished login.
#   scripts/loopback.sh GSERVER_BIN [BUILD]
# GSERVER_BIN: a built seihai-gserver (https://github.com/squirelworks/seihai-gserver).
# BUILD: folder name, default graal-2.05r2-GNW03081.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GS=$1
B=${2:-graal-2.05r2-GNW03081}
# the 1998 builds (gen 1) talk to a relay, not to a gserver
if grep -qs "ClientGeneration = 1;" "$ROOT/$B"/src/Protocol*.pas; then
  exec "$ROOT/scripts/loopback-relay.sh" "$B"
fi
# worlds-host sends one login-shaped frame to 127.0.0.1. A finished login
# is not required. A scaffold that only names modules still skips below.
HOSTBIN="$ROOT/build/$B/worlds-host"
if [ -x "$HOSTBIN" ]; then
  PORT=${LOOPBACK_PORT:-14862}
  WORK=$(mktemp -d)
  LPID=""
  trap 'if [ -n "$LPID" ]; then kill "$LPID" 2>/dev/null || true; fi; rm -rf "$WORK"' EXIT
  python3 -c '
import socket, sys
port = int(sys.argv[1])
ready = sys.argv[2]
outp = sys.argv[3]
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((__import__("socket").inet_ntoa(b"\x7f\x00\x00\x01"), port))
s.listen(1)
open(ready, "w").close()
s.settimeout(8)
try:
    c, _ = s.accept()
except socket.timeout:
    sys.exit(0)
c.settimeout(2)
data = b""
try:
    while True:
        b = c.recv(65536)
        if not b:
            break
        data += b
except socket.timeout:
    pass
c.close()
s.close()
open(outp, "wb").write(data)
' "$PORT" "$WORK/ready" "$WORK/got.bin" &
  LPID=$!
  i=0
  while [ ! -f "$WORK/ready" ]; do
    i=$((i + 1))
    if [ "$i" -gt 50 ]; then
      echo "listener did not bind loopback:$PORT"
      exit 1
    fi
    sleep 0.1
  done
  set +e
  GRAAL_PW=${GRAAL_PW:-loopbackpw} "$HOSTBIN" --port "$PORT" --account loop1 \
    > "$WORK/host.log" 2>&1
  RC=$?
  set -e
  wait "$LPID" || true
  LPID=""
  echo "--- worlds-host"
  cat "$WORK/host.log"
  if [ "$RC" -ne 0 ]; then
    echo "worlds-host exited $RC"
    exit "$RC"
  fi
  if ! grep -q "login frame" "$WORK/host.log"; then
    echo "worlds-host did not log a login frame"
    exit 1
  fi
  if ! grep -q "GNP1905C" "$WORK/host.log"; then
    echo "worlds-host did not log token GNP1905C"
    exit 1
  fi
  if [ ! -s "$WORK/got.bin" ]; then
    echo "listener got no bytes"
    exit 1
  fi
  echo "loopback attempt received $(wc -c < "$WORK/got.bin") bytes"
  exit 0
fi
if grep -qs "ScaffoldOnly = True;" "$ROOT/$B"/src/*.pas; then
  echo "scaffold only, no loopback: $B"
  exit 0
fi
GSDIR=$(cd "$(dirname "$GS")/../.." && pwd)
WORK=$(mktemp -d)
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT
PORT=${LOOPBACK_PORT:-14862}
cp -r "$GSDIR/world" "$WORK/world"
# a port of its own, so a gserver left running on 14802 does not answer
sed -i "s/14802/$PORT/" "$WORK/world/config/server.txt"
# the build's own token too (the folder name ends with it), for builds
# seihai-core has no profile for
printf '\n%s\n' "${B##*-}" >> "$WORK/world/config/allowedversions.txt"
# two levels joined by a link at x 36 of the start level
mkdir -p "$WORK/world/levels"
printf 'GLEVNW01\nLINK linked.nw 36 0 1 64 2 playery\n' > "$WORK/world/levels/onlinestartlocal.nw"
printf 'GLEVNW01\nLINK onlinestartlocal.nw 0 0 1 64 33 playery\n' > "$WORK/world/levels/linked.nw"
for A in loop1 loop2; do
  GRAAL_PW=loopbackpw "$GS" account $A --password-env GRAAL_PW --world "$WORK/world"
done
"$GS" --world "$WORK/world" --verbose > "$WORK/gserver.log" 2>&1 &
PID=$!
sleep 2
CLIENT=$(ls "$ROOT/build/$B"/Graal* | head -1)
set +e
# loop1 logs in and walks; loop2 joins while loop1 is there and must see it
GRAAL_PW=loopbackpw "$CLIENT" --server 127.0.0.1:$PORT --account loop1 \
  --frames 80 --keys "right*6,down*4,wait*5" --dump "$ROOT/build/$B/loopback.bmp" \
  > "$WORK/loop1.json" 2> "$WORK/loop1.log" &
C1=$!
sleep 1
GRAAL_PW=loopbackpw "$CLIENT" --server 127.0.0.1:$PORT --account loop2 \
  --frames 40 --keys "wait*10,down*2" > "$WORK/loop2.json" 2> "$WORK/loop2.log"
RC2=$?
wait $C1
RC=$?
# loop1 again, walking right into the link
GRAAL_PW=loopbackpw "$CLIENT" --server 127.0.0.1:$PORT --account loop1 \
  --frames 50 --keys "wait*5,right*14,wait*10" > "$WORK/link.json" 2> "$WORK/link.log"
RC3=$?
set -e
# the log (stderr) and the JSON summary (stdout) go to separate files: in
# one file a buffered log line can be cut by the summary
echo "--- loop1"; cat "$WORK/loop1.log" "$WORK/loop1.json"
echo "--- loop2"; cat "$WORK/loop2.log" "$WORK/loop2.json"
echo "--- loop1, link"; cat "$WORK/link.log" "$WORK/link.json"
echo "--- gserver log"
cat "$WORK/gserver.log"
if [ "$(grep -c "logged in as" "$WORK/gserver.log")" -lt 2 ]; then
  echo "gserver did not log both clients in"; exit 1
fi
if ! grep -q "other player .* loop1" "$WORK/loop2.log"; then
  echo "loop2 did not see loop1"; exit 1
fi
for L in loop1 loop2 link; do
  if ! grep -q '"kind":"summary".*"end":"clean"' "$WORK/$L.json"; then
    echo "$L: no clean JSON summary"; exit 1
  fi
done
if ! grep -q "BOARDPACKET linked.nw loaded" "$WORK/link.log"; then
  echo "the link did not take loop1 to linked.nw"; exit 1
fi
[ $RC2 -eq 0 ] || exit $RC2
[ $RC3 -eq 0 ] || exit $RC3
exit $RC
