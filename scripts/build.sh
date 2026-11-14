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
# BUILD_JOBS > 1 builds that many folders at a time, each in its own run
# of this script with its log kept apart and printed in order afterwards.
# The folders that make a shared C++ tree under common/ (torque, cpp)
# build one after another, beside the rest.
JOBS=${BUILD_JOBS:-1}
if [ -z "${GRAAL_BUILD_ONE:-}" ] && [ "$JOBS" -gt 1 ] && [ "$(echo $BUILDS | wc -w)" -gt 1 ]; then
  SERIAL=""
  PAR=""
  for B in $BUILDS; do
    case $B in
      graal-3.04-*|graal-3.153-*|graal-3.0beta-*|graal-3.01-*|graal-3.151-*|graal-4.20r8-*|graal-4.04r2-*|graal-5.12-*)
        SERIAL="$SERIAL $B" ;;
      *) PAR="$PAR $B" ;;
    esac
  done
  LOGS=$(mktemp -d)
  (
    for B in $SERIAL; do
      GRAAL_BUILD_ONE=1 sh "$ROOT/scripts/build.sh" "$B" > "$LOGS/$B.log" 2>&1 || echo "$B" >> "$LOGS/failed"
    done
  ) &
  if [ -n "$PAR" ]; then
    printf '%s\n' $PAR | xargs -P "$JOBS" -I{} sh -c \
      'GRAAL_BUILD_ONE=1 sh "$1" "$2" > "$3/$2.log" 2>&1 || echo "$2" >> "$3/failed"' \
      sh "$ROOT/scripts/build.sh" {} "$LOGS"
  fi
  wait
  for B in $BUILDS; do cat "$LOGS/$B.log"; done
  if [ -f "$LOGS/failed" ]; then
    echo "== build failed:"
    sed 's/^/  /' "$LOGS/failed"
    rm -rf "$LOGS"
    exit 1
  fi
  rm -rf "$LOGS"
  exit 0
fi
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
  # The 3.x player program (3.04, 3.153, and 3.0beta, 3.01 and 3.151 on the
  # same program): graal304-torque (the Torque engine in
  # a window: X11, Win32 or Cocoa) and the build's game library, which it
  # loads from its own folder. 3.153 runs the same program on its own
  # install. The program and the library must target the same system and
  # CPU, so each is built only where the compiler pair matches.
  case "$B" in
    graal-3.04-G3D03014) GAMEBASE=Game304Lib ;;
    graal-3.153-G3D28015) GAMEBASE=Game3153Lib ;;
    graal-3.0beta-G3D16053) GAMEBASE=Game30bLib ;;
    graal-3.01-G3D27063) GAMEBASE=Game301Lib ;;
    graal-3.151-G3D27015) GAMEBASE=Game3151Lib ;;
    *) GAMEBASE= ;;
  esac
  if [ -n "$GAMEBASE" ] && [ -f "$ROOT/common/torque/guigraal/Makefile" ]; then
    G="$ROOT/common/torque/guigraal"
    TARGET_OS=$("$FPC" -iTO 2>/dev/null || true)
    case "$(uname -s)/$TARGET_OS" in
      Linux/linux)
        echo "== common/torque/guigraal (graal304-torque, lib$GAMEBASE.so)"
        make -C "$G" lib build/graal304-torque CXX="${CXX:-g++}" FPC="$FPC"
        cp "$G/build/graal304-torque" "$G/build/lib/lib$GAMEBASE.so" "$OUT/"
        ;;
      Darwin/darwin|Linux/darwin)
        # macOS: graal304-torque.app with the game library inside. On Linux
        # (release-all's macOS job) the C++ side is cross-built with the
        # <cpu>-darwin-clang++ wrapper scripts/release/darwin-cross.sh makes.
        if [ "$(uname -s)" = Darwin ]; then DCXX=${CXX:-c++}
        else DCXX="$("$FPC" -iTP 2>/dev/null)-darwin-clang++"; fi
        if command -v "$DCXX" >/dev/null 2>&1; then
          echo "== common/torque/guigraal (graal304-torque.app, lib$GAMEBASE.dylib)"
          rm -rf "$G/build/graal304-torque" "$G/build/lib"
          make -C "$G" lib app PLATFORM=macos CXX="$DCXX" FPC="$FPC" APP_LIB="lib$GAMEBASE.dylib"
          rm -rf "$OUT/graal304-torque.app"
          cp -R "$G/build/graal304-torque.app" "$OUT/"
        else
          echo "::warning::no $DCXX; graal304-torque.app not built"
        fi
        ;;
      MINGW*/win32|MSYS*/win32|CYGWIN*/win32|MINGW*/win64|MSYS*/win64|CYGWIN*/win64)
        # A 32-bit Free Pascal (i386-win32, the release's) needs a 32-bit
        # MinGW g++: GRAAL_WIN32_CXX, else MSYS2's mingw32 one if installed.
        if [ "$TARGET_OS" = win32 ] && [ -z "${GRAAL_WIN32_CXX:-}" ] &&
           [ -x /c/msys64/mingw32/bin/g++ ] && [ -x /c/msys64/usr/bin/make ]; then
          # The runner's MSYS2 mingw32 toolchain, run in its own MINGW32
          # shell: with Free Pascal's bin folder first in PATH, plain make is
          # Free Pascal's cmd.exe make, which cannot run the recipes.
          echo "== common/torque/guigraal (graal304-torque.exe, $GAMEBASE.dll, win32, MSYS2)"
          # Windows-form paths (D:/a/...), which both MSYS runtimes read; the
          # login shell starts in its home, so it changes folder itself.
          FPCBIN=$(cygpath -m "$(command -v "$FPC")")
          GW=$(cygpath -m "$G")
          # The login shell drops the caller's environment, so FPCFLAGS goes
          # on the make command line (with forward slashes).
          GFLAGS=$(printf '%s' "${FPCFLAGS:-}" | tr '\\' /)
          MSYSTEM=MINGW32 /c/msys64/usr/bin/bash.exe -lc \
            "cd '$GW' && make lib build/graal304-torque.exe PLATFORM=windows FPC='$FPCBIN' FPCFLAGS='$GFLAGS'"
          # FPC's folder, first in PATH, has its own cp.exe, which cannot read
          # MSYS paths.
          /usr/bin/cp "$G/build/graal304-torque.exe" "$G/build/lib/$GAMEBASE.dll" "$OUT/"
          continue_torque=
        else
          continue_torque=1
        fi
        if [ "$TARGET_OS" = win32 ]; then
          WCXX=${GRAAL_WIN32_CXX:-}
        else
          WCXX=${CXX:-g++}
        fi
        if [ -z "$continue_torque" ]; then
          :
        elif [ -n "$WCXX" ] && command -v "$WCXX" >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
          echo "== common/torque/guigraal (graal304-torque.exe, $GAMEBASE.dll, $TARGET_OS)"
          # the compiler's own folder first, for its windres and helpers
          PATH="$(dirname "$(command -v "$WCXX")"):$PATH" \
            make -C "$G" lib build/graal304-torque.exe PLATFORM=windows CXX="$WCXX" FPC="$FPC"
          # FPC's folder, first in PATH, has its own cp.exe, which cannot read
          # MSYS paths.
          /usr/bin/cp "$G/build/graal304-torque.exe" "$G/build/lib/$GAMEBASE.dll" "$OUT/"
        else
          echo "::warning::no MinGW g++ for $TARGET_OS (set GRAAL_WIN32_CXX); graal304-torque.exe not built"
        fi
        ;;
      *) echo "graal304-torque: not built for $(uname -s) with a $TARGET_OS Free Pascal" ;;
    esac
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
      # The 3D library (common/cpp/graal3dengine) sits beside it, as
      # Graal3DEngine.dll does; the launcher loads it for `3 ` servers.
      if [ -f "$ROOT/common/cpp/graal3dengine/Makefile" ]; then
        echo "== common/cpp/graal3dengine"
        case "$(uname -s)" in
          MINGW*|MSYS*|CYGWIN*)
            make -C "$ROOT/common/cpp/graal3dengine" clean all CXX="$CXXBIN" \
              CXXFLAGS="-std=c++17 -Wall -Wextra -Werror -O2 -m32" ||
              echo "::warning::no 32-bit C++ target; 4.x 3D library not built"
            ;;
          *) make -C "$ROOT/common/cpp/graal3dengine" clean all CXX="$CXXBIN" ;;
        esac
        for L in Graal3DEngineRepro.dll libgraal3dengine.so libgraal3dengine.dylib; do
          if [ -f "$ROOT/common/cpp/graal3dengine/build/$L" ]; then cp "$ROOT/common/cpp/graal3dengine/build/$L" "$OUT/"; fi
        done
      fi
    else
      case "$(uname -s)" in
        Linux) echo "g++ and make are required for the 4.x engine library"; exit 1 ;;
        *) echo "no g++ or make; 4.x engine library skipped" ;;
      esac
    fi
  fi
  # The 6.01r1 and 6.03r7 Linux clients are one C++ program (quattro_lib).
  # Its rebuild, common/cpp/quattro's quattro-play, sits beside the start
  # screen, which hands the game to it (common/GQuattroPlay.pas). Linux
  # only: it draws through Xlib, and elsewhere the start screen keeps
  # playing in its own Pascal game.
  if { [ "$B" = "graal-6.03r7-G3D0511C" ] || [ "$B" = "graal-6.01r1-G3D0108A" ]; } && [ -f "$ROOT/common/cpp/quattro/Makefile" ]; then
    case "$(uname -s)" in
      Linux)
        # Without Xlib it would only run headless, so it is left out.
        if [ -f /usr/include/X11/Xlib.h ]; then
          echo "== common/cpp/quattro"
          CXXBIN=${CXX:-g++}
          make -C "$ROOT/common/cpp/quattro" build/quattro-play CXX="$CXXBIN"
          cp "$ROOT/common/cpp/quattro/build/quattro-play" "$OUT/"
        else
          echo "quattro-play: no Xlib headers; the Pascal game plays here"
        fi
        ;;
      *) echo "quattro-play: Linux only (Xlib); the Pascal game plays here" ;;
    esac
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
