#!/bin/sh
# tq-play from the menu to a game server, all on loopback: the stand-in
# install's menu functions ask a fake listserver for the list, pick the
# Classic server and log in to a fake gserver, which records the first
# frame. Needs build/tq-play, make lib and python3.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/../build"
WORK=$(mktemp -d)
trap 'kill $SERVERS 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/install" "$WORK/prefs"
cp "$HERE/online/main.cs" "$WORK/install/main.cs"
python3 "$HERE/online/fake_servers.py" "$WORK/seen.json" "$WORK/install/listserver.txt" &
SERVERS=$!
for i in $(seq 50); do [ -s "$WORK/install/listserver.txt" ] && break; sleep 0.1; done
"$BUILD/tq-play" --root "$WORK/install" --prefs "$WORK/prefs" --game "$BUILD/lib/libGame304Lib.so" \
  --steps "$HERE/online/steps.txt" --seconds 4 --log "$WORK/console.txt" --trace "$WORK/trace.txt" >/dev/null
wait $SERVERS || true
cat "$WORK/console.txt"
grep -v '^host stub' "$WORK/trace.txt" | grep -v '^exec ' || true
cat "$WORK/seen.json"; echo
python3 - "$WORK/seen.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
def need(ok, what):
    if not ok: sys.exit("online: " + what)
need(s.get('list_token') == 'G3D30123newmain', "the list request token")
need(s.get('list_account') == 'labacct', "the account typed into AccountEdit reached the listserver")
f = s.get('game_first_frame', '')
need('G3D03014' in f, "the gserver got the 3.04 login")
need('labacct' in f and 'labpass' in f, "with the account and password")
print("online: passed")
PY
