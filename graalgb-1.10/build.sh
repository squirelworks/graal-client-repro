#!/bin/sh
# Build the Graal Game Boy Color rebuild.
#   graalgb-1.10/build.sh
# Needs GBDK-2020 (GBDK_HOME, or lcc on PATH) and Python 3.
# Output: build/graalgb-1.10/GraalGB.gbc, a ROM with this project's own
# stand-in assets. tools/import_assets.py makes one with the original's.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
# Paths handed to the tools are relative to this folder: the native Windows
# lcc and Python misread MSYS (/d/a/...) absolute paths.
OUT=../build/graalgb-1.10
if [ -n "${GBDK_HOME:-}" ]; then LCC="$GBDK_HOME/bin/lcc"; else LCC=lcc; fi
PY=${PYTHON:-python3}
cd "$HERE"
mkdir -p "$OUT/obj"
"$PY" -I tools/make_builtin.py tools ../scripts/builtin/font5x7.py "$OUT/builtin.gpak"
# Bank 0 holds pak.c, which maps the pack's banks at $4000 and maps bank 1
# back, and the parts of the game that fit beside it; the rest is in bank 1.
for F in pak main room draw ui sfx; do
  "$LCC" -Wa-l -c -o "$OUT/obj/$F.o" "src/$F.c"
done
for F in ent obj; do
  "$LCC" -Wa-l -Wf-bo1 -c -o "$OUT/obj/$F.o" "src/$F.c"
done
"$LCC" -Wl-m -Wl-j -Wl-yt0x02 -Wl-yo16 -Wm-yc -Wm-yn"GRAAL" \
  -o "$OUT/engine.gbc" "$OUT/obj/pak.o" "$OUT/obj/main.o" "$OUT/obj/room.o" \
  "$OUT/obj/ent.o" "$OUT/obj/obj.o" "$OUT/obj/draw.o" "$OUT/obj/ui.o" "$OUT/obj/sfx.o"
"$PY" -I tools/gpak.py patch "$OUT/engine.gbc" "$OUT/builtin.gpak" "$OUT/GraalGB.gbc"
# the symbol list goes next to the ROM (emulator debuggers, tests/smoke.py)
cp "$OUT/engine.noi" "$OUT/GraalGB.noi" 2>/dev/null || true
cp "$OUT/engine.map" "$OUT/GraalGB.map" 2>/dev/null || true
echo "built $OUT/GraalGB.gbc"
