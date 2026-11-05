#!/bin/bash
# Stress check of one rebuilt client, for the release gate (release-all.yml)
# and for trying a build by hand. scripts/build.sh first.
#   scripts/stress.sh GSERVER_BIN BUILD [SECONDS]
# GSERVER_BIN: a built seihai-gserver (not used by the 1998 relay builds or
# by Graal3D, which have servers of their own). SECONDS: soak length,
# default 60 (STRESS_SECONDS overrides too).
#
# Against a local server, with a start level holding 80 scripted NPCs and a
# link to a second level:
#   soak    three clients random-walk for SECONDS, heading for the link
#           every few seconds, so levels load and unload over and over;
#   churn   meanwhile a fourth account connects and disconnects again and
#           again, and every third time is killed outright mid-session;
#   after   the server must still be up and take one more login.
# Every client that was not killed must exit 0 with a clean JSON summary
# and no runtime error in its log, the soak clients must have changed
# level, and no soak client's peak memory may keep growing (end peak at
# most twice the first 5 s peak plus 16 MiB).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GS=$1
B=$2
SOAK=${3:-${STRESS_SECONDS:-60}}
CLIENT=$(ls "$ROOT/build/$B"/Graal* 2>/dev/null | grep -v '\.\(heap\|bmp\|json\)$' | head -1)
[ -n "$CLIENT" ] || { echo "$B: not built (scripts/build.sh $B)"; exit 1; }
WORK=$(mktemp -d)
PIDS=""
trap 'for P in $PIDS; do kill $P 2>/dev/null || true; done; rm -rf "$WORK"' EXIT
FAIL=0
fail() { echo "FAIL $B: $*"; FAIL=1; }

# the client's log may not hold a runtime error or an unhandled exception
check_log() {
  if grep -Eq "Runtime error|unhandled exception|Access violation|EAccessViolation|Heap dump" "$1"; then
    fail "$(basename "$1"): $(grep -Em1 "Runtime error|unhandled exception|Access violation|EAccessViolation|Heap dump" "$1")"
  fi
}
check_clean() {  # NAME RC: exit 0 and a clean summary
  [ "$2" -eq 0 ] || fail "$1 exited $2"
  grep -q '"kind":"summary".*"end":"clean"' "$WORK/$1.json" || fail "$1: no clean JSON summary"
  check_log "$WORK/$1.log"
}
num() { sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
check_memory() {  # NAME: end peak RSS against the first stats line
  local first last
  first=$(grep '"kind":"stats"' "$WORK/$1.json" | head -1 | num rss_peak_kib)
  last=$(grep '"kind":"summary"' "$WORK/$1.json" | num rss_peak_kib)
  if [ -n "$first" ] && [ -n "$last" ]; then
    echo "$1: peak memory $first KiB at 5 s, $last KiB at the end"
    [ "$last" -le $((first * 2 + 16384)) ] || fail "$1: memory grew from $first to $last KiB"
  fi
}

case "$B" in
graal-3d-*)
  # Graal3D has its own protocol and server (graal-3d.yml logs it in);
  # here it plays its stand-in level offline for a long run.
  set +e
  "$CLIENT" --offline --data "$WORK" --frames $((SOAK * 20)) \
    --keys "fwd*40,jump*8,right*10,fwd*40,left*20,jump*8,back*30" \
    > "$WORK/soak.json" 2> "$WORK/soak.log"
  RC=$?
  set -e
  cat "$WORK/soak.log" "$WORK/soak.json" | tail -20
  [ $RC -eq 0 ] || fail "offline run exited $RC"
  grep -q '"onGround":true' "$WORK/soak.json" || fail "offline run did not end on the ground"
  check_log "$WORK/soak.log"
  [ $FAIL = 0 ] && echo "PASS $B (offline, $((SOAK * 20)) frames)"
  exit $FAIL
  ;;
esac

if grep -qs "ClientGeneration = 1;" "$ROOT/$B"/src/Protocol*.pas; then
  # the 1998 builds talk to the lab relay; they have no account or link
  GEN=1
  PORT=${STRESS_RELAY_PORT:-14873}
  python3 "$ROOT/scripts/relay98.py" --port "$PORT" --levels local --log "$WORK/server.log" &
  SPID=$!; PIDS="$SPID"
  sleep 1
  who() { echo "--nick $1"; }
  WALK="--walk random"
else
  GEN=2
  GSDIR=$(cd "$(dirname "$GS")/../.." && pwd)
  PORT=${STRESS_PORT:-14872}
  cp -r "$GSDIR/world" "$WORK/world"
  sed -i "s/14802/$PORT/" "$WORK/world/config/server.txt"
  printf '\n%s\n' "${B##*-}" >> "$WORK/world/config/allowedversions.txt"
  mkdir -p "$WORK/world/levels"
  # the start level: 80 NPCs that move every tenth of a second, and a link
  # east to a second level that links back
  {
    printf 'GLEVNW01\nLINK linked.nw 36 0 1 64 2 playery\n'
    for I in $(seq 0 79); do
      printf 'NPC - %d %d\n' $((2 + I % 30)) $((4 + I / 30 * 8))
      printf 'if (created || timeout) {\n  x = x + 0.5;\n  if (x > 34) x = 2;\n  timeout = 0.1;\n}\n'
      printf 'if (playertouchsme) message hi;\nNPCEND\n'
    done
  } > "$WORK/world/levels/onlinestartlocal.nw"
  printf 'GLEVNW01\nLINK onlinestartlocal.nw 0 0 1 64 33 playery\n' > "$WORK/world/levels/linked.nw"
  # k1..k99: one account per killed session, since the server may still
  # hold a dropped session as online for a while
  for A in s1 s2 s3 s4 s5 $(seq -f 'k%g' 1 99); do
    GRAAL_PW=stresspw "$GS" account $A --password-env GRAAL_PW --world "$WORK/world"
  done
  "$GS" --world "$WORK/world" > "$WORK/server.log" 2>&1 &
  SPID=$!; PIDS="$SPID"
  sleep 2
  export GRAAL_PW=stresspw
  who() { echo "--account $1"; }
  WALK="--walk random --link-every 3"
fi

run() {  # NAME ARGS...: one client, output to $WORK/NAME.{json,log}
  local N=$1; shift
  "$CLIENT" --server 127.0.0.1:$PORT "$@" > "$WORK/$N.json" 2> "$WORK/$N.log"
}

echo "== $B: soak $SOAK s, three clients, plus connect/disconnect churn"
set +e
SOAKERS=""
for I in 1 2 3; do
  run soak$I $(who s$I) $WALK --seed $I --seconds "$SOAK" --stats-every 5 &
  SOAKERS="$SOAKERS $!"; PIDS="$PIDS $!"
  sleep 0.5
done
CYCLE=0; KILLED=0
END=$((SECONDS + SOAK - 4))
while [ $SECONDS -lt $END ] && [ $KILLED -lt 99 ]; do
  CYCLE=$((CYCLE + 1))
  if [ $((CYCLE % 3)) = 0 ]; then
    # dropped without a goodbye, as when a player's connection dies
    run kill$CYCLE $(who k$((KILLED + 1))) $WALK --seed $CYCLE --seconds 30 &
    K=$!; sleep 1.5; kill -9 $K 2>/dev/null; wait $K 2>/dev/null
    KILLED=$((KILLED + 1))
  else
    run churn$CYCLE $(who s4) $WALK --seed $CYCLE --seconds 2
    RC=$?
    check_clean churn$CYCLE $RC
  fi
done
I=0
for P in $SOAKERS; do
  I=$((I + 1)); wait $P; check_clean soak$I $?
done
kill -0 $SPID 2>/dev/null || fail "the server died"
run after $(who s5) --seconds 2
check_clean after $?
set -e
echo "   $CYCLE churn sessions, $KILLED of them killed mid-session"

WARPS=0
for I in 1 2 3; do
  W=$(grep '"kind":"summary"' "$WORK/soak$I.json" | num warps_done)
  WARPS=$((WARPS + ${W:-0}))
  check_memory soak$I
  tail -1 "$WORK/soak$I.json"
done
if [ $GEN = 2 ]; then
  echo "   level changes in the soak: $WARPS"
  [ $WARPS -gt 0 ] || fail "no soak client changed level"
fi
if [ $FAIL != 0 ]; then
  for F in "$WORK"/soak*.log "$WORK/after.log" "$WORK/server.log"; do
    echo "--- $(basename "$F") (last 30 lines)"; tail -30 "$F"
  done
  exit 1
fi
echo "PASS $B"
