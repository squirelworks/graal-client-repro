#!/bin/bash
# CI-only: use actual player/resource/stamp/pack code, no network or window.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
Q="$ROOT/common/cpp/quattro"
B=graal-6.00beta-20110627-G3D28090
BASE=$(cygpath -u "${RUNNER_TEMP:-${TMPDIR:-/tmp}}")
WORK=$(mktemp -d "$BASE/quattro-package.XXXXXX")
# Runner-temp files are deliberately left for CI diagnostics, outside the tree.
mkdir -p "$WORK/common/cpp/quattro/win" "$WORK/common/win" "$WORK/$B/src" "$WORK/build/$B"
cp "$Q/win/quattro-play.rc" "$WORK/common/cpp/quattro/win/"
cp "$ROOT/common/win/graal-delphi.manifest" "$WORK/common/win/"
cp "$ROOT/$B/README.md" "$ROOT/$B/RELEASE_NOTES.md" "$WORK/$B/"
# Preserve the actual manifest entries but force Windows line separators so
# this path remains covered even if runner checkout defaults change.
while IFS= read -r entry || [ -n "$entry" ]; do
  printf '%s\r\n' "${entry%$'\r'}"
done < "$ROOT/$B/release-files" > "$WORK/$B/release-files"
# Leave the final Windows player entry without LF: both CR separation and
# the final nonempty-line path must work for the actual ZIP assertion below.
truncate -s -1 "$WORK/$B/release-files"
printf 'program Probe; begin end.\n' > "$WORK/$B/src/Probe.dpr"
printf 'not shipped\n' > "$WORK/build/$B/TestEngine600b.exe"
RC="$WORK/common/cpp/quattro/win/quattro-play.rc"
RES="$WORK/quattro-play.res.o"
PLAYER="$WORK/build/$B/quattro-play.exe"
check_player() {
  local extra=()
  if [ "$#" -eq 3 ]; then extra=(-ReferencePlayer "$(cygpath -w "$3")"); fi
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$Q/tests/package_test.ps1")" \
    -Player "$(cygpath -w "$1")" -Version "$2" "${extra[@]}"
}
env -u OS make -C "$Q" OS=Windows_NT "PLAYER=$PLAYER" "PLAYER_RC=$RC" "PLAYER_RESOURCE=$RES"
check_player "$PLAYER" 0.0.0-dev
# Rebuild the SAME target after stamping: proves the RC dependency relinks,
# not merely that a one-off compiler invocation embeds hardcoded metadata.
sleep 2
(cd "$WORK" && bash "$ROOT/scripts/release/stamp.sh" "$B" v1.2.3)
env -u OS make -C "$Q" OS=Windows_NT "PLAYER=$PLAYER" "PLAYER_RC=$RC" "PLAYER_RESOURCE=$RES"
check_player "$PLAYER" 1.2.3
if ! command -v 7z >/dev/null 2>&1; then
  export PATH="/c/Program Files/7-Zip:$PATH"
fi
command -v 7z >/dev/null
(cd "$WORK" && bash "$ROOT/scripts/release/pack.sh" "$B" v1.2.3 windows)
ZIP="$WORK/dist/$B-v1.2.3-windows.zip"
7z x "$ZIP" "-o$WORK/unpacked" >/dev/null
PACK="$WORK/unpacked/$B-v1.2.3-windows"
test -f "$PACK/quattro-play.exe"
test ! -e "$PACK/TestEngine600b.exe"
# Use the existing Windows runtime for exact bytes; MSYS2 need not have cmp.
check_player "$PACK/quattro-play.exe" 1.2.3 "$PLAYER"
echo 'Actual pack.zip includes the byte-identical versioned player and excludes test binaries'
