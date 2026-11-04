#!/bin/sh
# Loopback check for the Graal3D rebuild: two copies log into the Graal3D
# reference server from graal_analysis (graal3d/reference-server, written
# from the protocol notes). Both must log in, receive and save the level,
# see each other, and swap a chat line over UDP.
#   graal-3d-20000205/loopback3d.sh PATH/TO/g3dserver.py
# Run scripts/build.sh graal-3d-20000205 first.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVER=$1
B=graal-3d-20000205
CLIENT="$ROOT/build/$B/Graal3D"
WORK=$(mktemp -d)
PORT=${LOOPBACK3D_PORT:-14931}
trap 'kill $PID 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/levels" "$WORK/c1" "$WORK/c2"
# a level of this repo's own: one floor quad, not the shipped startlevel.x
cat > "$WORK/levels/startlevel.x" <<'EOF'
xof 0302txt 0064
Mesh floor {
 4;
 -2000.0;0.0;-2000.0;, -2000.0;0.0;2000.0;, 2000.0;0.0;2000.0;, 2000.0;0.0;-2000.0;;
 1;
 4;0,1,2,3;;
 MeshMaterialList { 1; 1; 0;; Material { 0.3;0.6;0.3;1.0;; 1.0; 0.0;0.0;0.0;; 0.0;0.0;0.0;; } }
}
EOF
python3 "$SERVER" --port "$PORT" --levels "$WORK/levels" > "$WORK/server.log" 2>&1 &
PID=$!
sleep 1
set +e
GRAAL_PW=x "$CLIENT" --server 127.0.0.1:$PORT --account alice --nick Alice \
  --data "$WORK/c1" --frames 120 --keys "wait*30,fwd*20,say:hello there,wait*60" \
  > "$WORK/c1.json" 2> "$WORK/c1.log" &
C1=$!
sleep 1
GRAAL_PW=x "$CLIENT" --server 127.0.0.1:$PORT --account bob --nick Bob \
  --data "$WORK/c2" --frames 100 --keys "wait*20,right*10" \
  --dump "$ROOT/build/$B/loopback3d.bmp" > "$WORK/c2.json" 2> "$WORK/c2.log"
RC2=$?
wait $C1
RC1=$?
set -e
echo "--- alice"; cat "$WORK/c1.log" "$WORK/c1.json"
echo "--- bob"; cat "$WORK/c2.log" "$WORK/c2.json"
echo "--- server"; cat "$WORK/server.log"
for C in c1 c2; do
  grep -q '"loggedIn":true' "$WORK/$C.json" || { echo "$C did not log in"; exit 1; }
  grep -q '"level":"startlevel.x"' "$WORK/$C.json" || { echo "$C did not load the level"; exit 1; }
  cmp -s "$WORK/levels/startlevel.x" "$WORK/$C/startlevel.x" || { echo "$C did not save the level as sent"; exit 1; }
done
grep -q "other player .* Bob" "$WORK/c1.log" || { echo "alice did not see bob"; exit 1; }
grep -q "other player .* Alice" "$WORK/c2.log" || { echo "bob did not see alice"; exit 1; }
grep -q '"chatLines":1' "$WORK/c2.json" || { echo "bob did not get alice's chat"; exit 1; }
grep -q '"udpIn":0,' "$WORK/c2.json" && { echo "bob got nothing over UDP"; exit 1; }
[ $RC1 -eq 0 ] || exit $RC1
exit $RC2
