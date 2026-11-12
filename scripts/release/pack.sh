#!/bin/bash
# Pack one built client into its release zip.
#   scripts/release/pack.sh graal-2.05r2-GNW03081 v0.0.3 windows
# Makes dist/<build>-<version>-<os>.zip from build/<build>/ (scripts/build.sh
# first). Only the programs in src/ ship. The test programs stay out:
# players do not run them, and every extra unsigned exe in the zip is one
# more file for SmartScreen and antivirus to judge.
set -eu
BUILD=$1 VERSION=$2 OS=$3
OUT="$BUILD-$VERSION-$OS"
rm -rf "dist/$OUT" "dist/$OUT.zip"
mkdir -p "dist/$OUT"
for P in "$BUILD"/src/*.dpr; do
  N=$(basename "$P" .dpr)
  for F in "build/$BUILD/$N" "build/$BUILD/$N.exe"; do
    [ -f "$F" ] && cp "$F" "dist/$OUT/"
  done
done
# Programs built outside src/*.dpr (the 3.04 Torque program and its game
# library) are named in <build>/release-files, one per line.
if [ -f "$BUILD/release-files" ]; then
  while read -r F; do
    [ -n "$F" ] && [ -f "build/$BUILD/$F" ] && cp "build/$BUILD/$F" "dist/$OUT/"
  done < "$BUILD/release-files"
fi
if [ -z "$(ls "dist/$OUT")" ]; then echo "$BUILD: no program was built" >&2; exit 1; fi
cp "$BUILD/README.md" "$BUILD/RELEASE_NOTES.md" "dist/$OUT/"
(cd dist && 7z a "$OUT.zip" "$OUT" > /dev/null)
echo "dist/$OUT.zip"
