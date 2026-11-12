#!/bin/sh
# Build every client rebuild and its tests with Free Pascal in Delphi mode.
#   scripts/build.sh            all builds
#   scripts/build.sh graal-2.05r2-GNW03081
# Output: build/<folder>/
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FPC=${FPC:-fpc}
FLAGS=${FPCFLAGS:--O2}
# Paths given to the compiler are relative to the .dpr's folder
# (<build>/src or <build>/tests): the native Windows compiler misreads
# MSYS (/d/a/...) and mixed (D:/a/...) absolute paths alike.
cd "$ROOT"
if [ $# -gt 0 ]; then BUILDS="$*"; else BUILDS=$(ls -d graal-*/ | tr -d /); fi
. "$ROOT/scripts/v7.sh"
for B in $BUILDS; do
  # A v7 folder builds in its own run, so its failure is reported and the
  # other builds go on (scripts/v7.sh).
  if [ -z "${GRAAL_V7_INNER:-}" ] && [ "${V7_STRICT:-}" != 1 ] && is_v7 "$B"; then
    if ! GRAAL_V7_INNER=1 sh "$ROOT/scripts/build.sh" "$B"; then
      v7_warn "$B" "build failed"
    fi
    continue
  fi
  OUT="$ROOT/build/$B"
  mkdir -p "$OUT"
  mkdir -p "$OUT/checked"
  for P in "$B"/src/*.dpr "$B"/tests/*.dpr; do
    [ -f "$P" ] || continue
    echo "== $P"
    # Tests are built with range and overflow checks and the heap tracer
    # (-gh), into their own unit folder so the client's units stay -O2.
    case "$P" in
      */tests/*) EXTRA="-Cr -Co -gh -gl"; UNITS="../../build/$B/checked" ;;
      *) EXTRA=""; UNITS="../../build/$B" ;;
    esac
    # set -f: FPCFLAGS may hold FPC's own * wildcard, not a shell glob
    (set -f; cd "$(dirname "$P")" && "$FPC" -Mdelphi -Sh -vew $FLAGS $EXTRA \
      -Fu../../common -Fu../src -FE"../../build/$B" -FU"$UNITS" \
      "$(basename "$P")")
  done
  # 3.04's C++ host is common/torque/host304 (its own Makefile).
  # The Pascal units under common/torque stay off the Free Pascal path.
  if [ "$B" = "graal-3.04-G3D03014" ] && [ -f "$ROOT/common/torque/host304/Makefile" ]; then
    echo "== common/torque/host304"
    CXXBIN=${CXX:-g++}
    if command -v "$CXXBIN" >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
      make -C "$ROOT/common/torque/host304" clean all CXX="$CXXBIN"
    else
      case "$(uname -s)" in
        Linux) echo "g++ and make are required for the 3.04 host"; exit 1 ;;
        *) echo "no g++ or make; 3.04 C++ host skipped" ;;
      esac
    fi
  fi
  # The 3.04 and 3.153 player program on Linux: graal304-torque (the Torque
  # engine in an X11 window) and the build's game library, which it loads
  # from its own folder. 3.153 runs the same program on its own install.
  case "$B" in
    graal-3.04-G3D03014) GAMELIB=libGame304Lib.so ;;
    graal-3.153-G3D28015) GAMELIB=libGame3153Lib.so ;;
    *) GAMELIB= ;;
  esac
  if [ -n "$GAMELIB" ] && [ "$(uname -s)" = Linux ] && [ -f "$ROOT/common/torque/guigraal/Makefile" ]; then
    echo "== common/torque/guigraal (graal304-torque, $GAMELIB)"
    make -C "$ROOT/common/torque/guigraal" lib build/graal304-torque CXX="${CXX:-g++}" FPC="$FPC"
    cp "$ROOT/common/torque/guigraal/build/graal304-torque" "$ROOT/common/torque/guigraal/build/lib/$GAMELIB" "$OUT/"
  fi
  # 4.2.0.8's residual engine host is common/torque/host4208.
  # The Delphi shell is Shell420.dpr, compiled above. The Pascal units
  # under common/torque stay off the Free Pascal path.
  if [ "$B" = "graal-4.20r8-G3D20126" ] && [ -f "$ROOT/common/torque/host4208/Makefile" ]; then
    echo "== common/torque/host4208"
    CXXBIN=${CXX:-g++}
    if command -v "$CXXBIN" >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
      make -C "$ROOT/common/torque/host4208" clean all CXX="$CXXBIN"
    else
      case "$(uname -s)" in
        Linux) echo "g++ and make are required for the 4.2.0.8 host"; exit 1 ;;
        *) echo "no g++ or make; 4.2.0.8 C++ host skipped" ;;
      esac
    fi
  fi
  # The 4.x/5.0 engine library (common/cpp/graalengine) sits next to the
  # launcher, as GraalEngine.dll sits next to the original Graal4.exe.
  if { [ "$B" = "graal-4.04r2-G3D17026" ] || [ "$B" = "graal-5.12-G3D14097" ]; } && [ -f "$ROOT/common/cpp/graalengine/Makefile" ]; then
    echo "== common/cpp/graalengine"
    CXXBIN=${CXX:-g++}
    if command -v "$CXXBIN" >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
      case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
          # The Windows launcher is 32-bit (i386-win32), so its DLL must be
          # too. A compiler with no 32-bit target leaves the DLL out and the
          # launcher test skips its library half.
          make -C "$ROOT/common/cpp/graalengine" clean all CXX="$CXXBIN" \
            CXXFLAGS="-std=c++17 -Wall -Wextra -Werror -O2 -m32" ||
            echo "::warning::no 32-bit C++ target; 4.x engine library not built"
          ;;
        *) make -C "$ROOT/common/cpp/graalengine" clean all CXX="$CXXBIN" ;;
      esac
      for L in GraalEngineRepro.dll libgraalengine.so libgraalengine.dylib; do
        if [ -f "$ROOT/common/cpp/graalengine/build/$L" ]; then cp "$ROOT/common/cpp/graalengine/build/$L" "$OUT/"; fi
      done
    else
      case "$(uname -s)" in
        Linux) echo "g++ and make are required for the 4.x engine library"; exit 1 ;;
        *) echo "no g++ or make; 4.x engine library skipped" ;;
      esac
    fi
  fi
  # 6.114's connector is a small C++ program. The playable stand-in is
  # portable C# (mcs or dotnet). Neither is a Unity player.
  if [ -f "$B/src/worlds_host.cpp" ]; then
    echo "== $B/src/worlds_host.cpp"
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*)
        echo "worlds-host: POSIX connector is not built on Windows"
        ;;
      *)
        CXX=""
        if command -v g++ >/dev/null 2>&1; then CXX=g++
        elif command -v c++ >/dev/null 2>&1; then CXX=c++
        fi
        if [ -z "$CXX" ]; then
          echo "worlds-host: no C++ compiler" >&2
          exit 1
        fi
        "$CXX" -std=c++17 -O2 -Wall -Wextra -o "$OUT/worlds-host" "$B/src/worlds_host.cpp"
        ;;
    esac
  fi
  if [ -f "$B/player/PlayerProgram.cs" ]; then
    echo "== $B/player"
    if ! command -v dotnet >/dev/null 2>&1; then
      if [ -x "/c/Program Files/dotnet/dotnet" ]; then
        PATH="/c/Program Files/dotnet:$PATH"
      fi
    fi
    PLAYOUT="$OUT/worlds-player"
    rm -f "$PLAYOUT" "$OUT/worlds-player.exe"
    if command -v dotnet >/dev/null 2>&1 && [ -f "$B/player/WorldsPlayer.csproj" ]; then
      # MSBuild turns environment variables into properties; a release job's
      # VERSION (v0.0.4.1) would become $(Version), which NuGet rejects.
      env -u VERSION dotnet build "$B/player/WorldsPlayer.csproj" -c Release -o "$OUT" --nologo
      if [ ! -x "$PLAYOUT" ] && [ -f "$OUT/worlds-player.exe" ]; then
        cat > "$PLAYOUT" << 'EOF'
#!/bin/sh
DIR=$(cd "$(dirname "$0")" && pwd)
exec "$DIR/worlds-player.exe" "$@"
EOF
        chmod +x "$PLAYOUT"
      fi
      # The macOS app host does not look where the dotnet muxer is
      # installed, so it exits with libhostfxr missing. Launch the dll
      # through the muxer that just built it. Linux keeps the app host.
      case "$(uname -s)" in
        Darwin)
          if [ -f "$OUT/worlds-player.dll" ] && [ -e "$PLAYOUT" ]; then
            mv "$PLAYOUT" "$OUT/worlds-player.apphost"
            cat > "$PLAYOUT" << 'EOF'
#!/bin/sh
DIR=$(cd "$(dirname "$0")" && pwd)
exec dotnet "$DIR/worlds-player.dll" "$@"
EOF
            chmod +x "$PLAYOUT"
          fi
          ;;
      esac
    elif command -v mcs >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      mcs -sdk:4.5 -optimize -out:"$OUT/worlds-player.exe" "$B"/player/*.cs
      cat > "$PLAYOUT" << 'EOF'
#!/bin/sh
DIR=$(cd "$(dirname "$0")" && pwd)
exec mono "$DIR/worlds-player.exe" "$@"
EOF
      chmod +x "$PLAYOUT"
    else
      case "$(uname -s)" in
        Linux)
          echo "worlds-player: no C# compiler (mcs or dotnet)" >&2
          exit 1
          ;;
        *)
          echo "worlds-player: no C# compiler on this runner; Pascal shell still builds"
          ;;
      esac
    fi
  fi
done
