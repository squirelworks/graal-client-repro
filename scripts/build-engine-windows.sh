#!/bin/sh
# Build the two engine DLLs with the Windows architecture used by FPC.
# Called from build.sh's Windows branch; no host library is copied on mismatch.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$1
TARGET=$2
case "$TARGET" in
  i386/win32) SYSTEM=MINGW32; PREFIX=mingw32; TRIPLE=i686-w64-mingw32 ;;
  x86_64/win64) SYSTEM=UCRT64; PREFIX=ucrt64; TRIPLE=x86_64-w64-mingw32 ;;
  *) echo "unsupported engine DLL target: $TARGET" >&2; exit 1 ;;
esac
test -x "/c/msys64/$PREFIX/bin/g++"
test -x /c/msys64/usr/bin/make
RW=$(cygpath -m "$ROOT")
OW=$(cygpath -m "$OUT")
# Positional arguments preserve paths containing spaces. The login shell sets
# the matching compiler AND compression-library search paths, unlike -m32 on
# an unrelated default compiler. MSYS make avoids FPC's make.exe path handling.
MSYSTEM=$SYSTEM /c/msys64/usr/bin/bash.exe -lc '
  set -eu
  root=$1; out=$2; expected=$3
  cxx=${CXX:-g++}
  actual=$("$cxx" -dumpmachine)
  if [ "$actual" != "$expected" ]; then
    echo "engine compiler target $actual does not match $expected" >&2
    exit 1
  fi
  cd "$root"
  engine=common/cpp/graalengine
  three=common/cpp/graal3dengine
  signature="$(command -v "$cxx")|$actual|$("$cxx" -dumpfullversion)"
  old=$(cat "$engine/build/.windows-target" 2>/dev/null || true)
  if [ "$old" != "$signature" ]; then
    /usr/bin/make -C "$three" clean OS=Windows_NT
    /usr/bin/make -C "$engine" clean OS=Windows_NT
  fi
  /usr/bin/make -C "$engine" all OS=Windows_NT CXX="$cxx"
  /usr/bin/make -C "$three" all OS=Windows_NT CXX="$cxx"
  test -f "$engine/build/GraalEngineRepro.dll"
  test -f "$three/build/Graal3DEngineRepro.dll"
  printf "%s\n" "$signature" > "$engine/build/.windows-target"
  /usr/bin/cp "$engine/build/GraalEngineRepro.dll" "$three/build/Graal3DEngineRepro.dll" "$out/"
  echo "engine DLLs built/copied for $actual"
' build-engine-windows "$RW" "$OW" "$TRIPLE"
