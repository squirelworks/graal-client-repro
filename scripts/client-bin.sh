# Sourced by the loopback and stress scripts. client_bin prints the client
# program of folder $B: the build named after its src/Graal*.dpr. Picking
# the first build/$B/Graal* file instead can give a unit object, such as
# GraalClient.o in graal-x-GNW23021, which sorts ahead of GraalX.
client_bin() {
  for D in "$ROOT/$B"/src/Graal*.dpr; do
    F="$ROOT/build/$B/$(basename "$D" .dpr)"
    if [ -x "$F" ]; then echo "$F"; return 0; fi
  done
  echo "$B: no built Graal*.dpr program in build/$B" >&2
  return 1
}
