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
for B in $BUILDS; do
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
