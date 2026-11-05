#!/bin/bash
# Stamp a release version into a build's Windows resources.
#   scripts/release/stamp.sh graal-2.05r2-GNW03081 v0.0.3
# v0.0.3 -> FILEVERSION 0,0,3,0 and "0.0.3" in each src/*.rc. The .rc
# files keep 0,0,0,0 and "0.0.0-dev" in git; only release runs stamp them.
set -eu
BUILD=$1 VERSION=$2
N="${VERSION#v}"; IFS=. read -r A B C _ <<< "$N"
for R in "$BUILD"/src/*.rc; do
  [ -f "$R" ] || continue
  sed -i -e "s/^\(FILEVERSION\|PRODUCTVERSION\) 0,0,0,0/\1 ${A:-0},${B:-0},${C:-0},0/" \
         -e "s/\"0\.0\.0-dev\"/\"$N\"/" "$R"
  grep -E 'VERSION |Version"' "$R"
done
