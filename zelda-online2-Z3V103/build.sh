#!/bin/sh
# Build Zelda Online 2 and its GServ lobby and its tests with a JDK, then run the tests.
#   zelda-online2-Z3V103/build.sh        build and test
# Output: build/zelda-online2-Z3V103/ZeldaOnline2.jar and GServ.jar
# The classes target Java 8 class files, so any Java 8 or newer runs it.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=$(basename "$HERE")
OUT="$HERE/../build/$NAME"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
SEP=:
# Git Bash on Windows: the JDK wants Windows paths and ';' between them
if command -v cygpath >/dev/null 2>&1; then OUT=$(cygpath -m "$OUT"); SEP=';'; fi
rm -rf "$OUT/classes" "$OUT/test-classes"
mkdir -p "$OUT/classes" "$OUT/test-classes"
cd "$HERE"
javac -encoding UTF-8 --release 8 -Xlint:-options -nowarn -d "$OUT/classes" $(find src -name '*.java')
printf 'Main-Class: zo2.ZeldaOnline2\n' > "$OUT/manifest.txt"
jar cfm "$OUT/ZeldaOnline2.jar" "$OUT/manifest.txt" -C "$OUT/classes" zo2
printf 'Main-Class: gserv.GServ\n' > "$OUT/manifest-gserv.txt"
jar cfm "$OUT/GServ.jar" "$OUT/manifest-gserv.txt" -C "$OUT/classes" gserv
javac -encoding UTF-8 --release 8 -Xlint:-options -nowarn -cp "$OUT/classes" -d "$OUT/test-classes" $(find tests -name '*.java')
java -Djava.awt.headless=true -cp "$OUT/classes$SEP$OUT/test-classes" zo2.TestZO2
# smoke: the jar starts, walks and writes a frame
java -Djava.awt.headless=true -jar "$OUT/ZeldaOnline2.jar" --one-player --keys rrrrrrrrdddd --dump "$OUT/smoke.png"
test -s "$OUT/smoke.png"
