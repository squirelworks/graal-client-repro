#!/bin/sh
# Loopback acceptance check for the 1998 relay builds (gen 1): start the lab
# relay (scripts/relay98.py) and join two copies of the rebuilt client. Both
# must get their ids, pair and see each other's nickname, and the first
# must drop the second when it quits.
#   scripts/loopback-relay.sh BUILD
# BUILD: a gen-1 folder, e.g. graal-1.1.9-19990211.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=$1
. "$ROOT/scripts/client-bin.sh"
WORK=$(mktemp -d)
PORT=${LOOPBACK_RELAY_PORT:-14863}
python3 "$ROOT/scripts/relay98.py" --port "$PORT" --levels local \
  --log "$WORK/relay.log" &
PID=$!
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT
sleep 1
CLIENT=$(client_bin)
set +e
"$CLIENT" --server 127.0.0.1:$PORT --nick loop1 --frames 100 \
  --keys "wait*30,right*6,down*4,wait*5" --dump "$ROOT/build/$B/loopback.bmp" \
  > "$WORK/loop1.out" 2> "$WORK/loop1.log" &
C1=$!
sleep 1
"$CLIENT" --server 127.0.0.1:$PORT --nick loop2 --frames 60 --keys "wait*10,down*2" \
  > "$WORK/loop2.out" 2> "$WORK/loop2.log"
RC2=$?
wait $C1
RC=$?
set -e
for L in loop1 loop2; do echo "--- $L"; cat "$WORK/$L.log" "$WORK/$L.out"; done
echo "--- relay log"; cat "$WORK/relay.log"
for L in loop1 loop2; do
  if ! grep -q "^joined " "$WORK/$L.log"; then echo "$L did not join"; exit 1; fi
  if ! grep -q '"kind":"summary".*"end":"clean"' "$WORK/$L.out"; then
    echo "$L: no clean JSON summary"; exit 1
  fi
done
# each must see the other's nickname arrive while both are on: the
# "other player <id> <nick>" line HandleData logs on an N, not the list
# printed at exit
for P in "loop2 loop1" "loop1 loop2"; do
  set -- $P
  if ! grep -Eq "^other player [0-9a-f]{8} $2\$" "$WORK/$1.log"; then
    echo "$1 did not see $2"; exit 1
  fi
done
# loop2 quits first: loop1 must drop it and not still list it at exit
ID2=$(sed -n 's/^other player \([0-9a-f]\{8\}\) loop2$/\1/p' "$WORK/loop1.log" | head -1)
if ! grep -q "^player $ID2 left" "$WORK/loop1.log"; then
  echo "loop1 did not see loop2 leave"; exit 1
fi
if grep -q "^other player .* loop2 at " "$WORK/loop1.log"; then
  echo "loop1 still lists loop2 after it left"; exit 1
fi
[ $RC2 -eq 0 ] || exit $RC2
exit $RC
