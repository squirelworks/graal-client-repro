#!/bin/sh
# tq-play from the menu to a game server, all on loopback: the stand-in
# install's menu functions ask a fake listserver for the list, pick the
# Classic server and log in to a fake gserver, which records the first
# frame. Needs build/tq-play, make lib and python3. GAME_LIB and
# GAME_TOKEN pick the library and its login token (3.153:
# GAME_LIB=libGame3153Lib.so GAME_TOKEN=G3D28015). LIST_FALLBACK=1 puts a
# listserver that never answers first (on 127.0.0.2: Linux, or macOS with
# `ifconfig lo0 alias 127.0.0.2`): the
# client gives up on it after 8 seconds and asks the license.graal host.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/../build"
# GAME_LIB names the library file; by default 3.04's under this system's name
if [ -n "${GAME_LIB:-}" ]; then LIB="$BUILD/lib/$GAME_LIB"; else
  LIB="$BUILD/lib/libGame304Lib.so"
  [ -f "$LIB" ] || LIB="$BUILD/lib/Game304Lib.dll"
  [ -f "$LIB" ] || LIB="$BUILD/lib/libGame304Lib.dylib"
fi
WORK=$(mktemp -d)
trap 'kill $SERVERS 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/install" "$WORK/prefs"
cp "$HERE/online/main.cs" "$WORK/install/main.cs"
STEPS="$HERE/online/steps.txt"
SECONDS_RUN=4
if [ "${LIST_FALLBACK:-}" = 1 ]; then
  python3 "$HERE/online/fake_servers.py" "$WORK/seen.json" "$WORK/install/listserver.txt" fallback &
  # the steps after the list request 9 seconds later, past the first
  # host's 8 second wait
  awk '/^[0-9]/ && $1 > 0 { $1 = $1 + 9000 } { print }' "$STEPS" > "$WORK/steps.txt"
  STEPS="$WORK/steps.txt"
  SECONDS_RUN=13
else
  python3 "$HERE/online/fake_servers.py" "$WORK/seen.json" "$WORK/install/listserver.txt" &
fi
SERVERS=$!
for i in $(seq 50); do [ -s "$WORK/install/listserver.txt" ] && break; sleep 0.1; done
if [ "${LIST_FALLBACK:-}" = 1 ]; then
  mkdir -p "$WORK/install/license"
  printf '127.0.0.1\r\n14922\r\n\r\n\r\n\r\n\r\n\r\n' > "$WORK/install/license/license.graal"
fi
"$BUILD/tq-play" --root "$WORK/install" --prefs "$WORK/prefs" --game "$LIB" \
  --steps "$STEPS" --seconds "$SECONDS_RUN" --log "$WORK/console.txt" --trace "$WORK/trace.txt" >/dev/null
wait $SERVERS || true
cat "$WORK/console.txt"
grep -v '^host stub' "$WORK/trace.txt" | grep -v '^exec ' || true
cat "$WORK/seen.json"; echo
python3 - "$WORK/seen.json" "${GAME_TOKEN:-G3D03014}" <<'PY'
import json, os, sys
s = json.load(open(sys.argv[1]))
TOKEN = sys.argv[2]
def need(ok, what):
    if not ok: sys.exit("online: " + what)
need(s.get('list_token') == 'G3D30123newmain', "the list request token")
if os.environ.get('LIST_FALLBACK') == '1':
    need(s.get('silent_host_asked'), "the silent first listserver was asked first")
need(s.get('list_account') == 'labacct', "the account typed into AccountEdit reached the listserver")
f = s.get('game_first_frame', '')
need(TOKEN in f, "the gserver got the game login " + TOKEN)
need('labacct' in f and 'labpass' in f, "with the account and password")
print("online: passed")
PY
