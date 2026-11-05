#!/bin/bash
# Free Pascal 3.2.2 cross compilers for macOS (x86_64-darwin and
# aarch64-darwin) on an Ubuntu 24.04 runner, so release-all can build the
# macOS programs without a macOS runner.
#   scripts/release/darwin-cross.sh       (X=~/xbin by default)
# Then, per architecture:
#   FPC=$X/fpc-darwin-aarch64 scripts/build.sh graal-...   (default FPCFLAGS)
# Each architecture is its own build (no lipo): build one, pack it, then the
# other. The programs are headless on macOS for now (no window back end).
set -eux
X=${X:-$HOME/xbin}; mkdir -p "$X"; export PATH="$X:$PATH"
sudo apt-get update
sudo apt-get install -y fpc fpc-source-3.2.2 lld-18 clang curl xz-utils

# 1. macOS SDK stubs (.tbd). usr/lib is enough for the current headless clients;
#    a Cocoa back end also needs System/Library/Frameworks (add '*/System/Library/Frameworks/*').
SDKDIR=$HOME/sdk; mkdir -p "$SDKDIR"
curl -sSL https://github.com/joseluisq/macosx-sdks/releases/download/14.5/MacOSX14.5.sdk.tar.xz \
  | tar xJ -C "$SDKDIR" --wildcards '*/usr/lib/*' '*SDKSettings*'
SDK=$SDKDIR/MacOSX14.5.sdk

# 2. assembler / linker wrappers (FPC uses clang as assembler for darwin, and <prefix>ld)
for A in x86_64 aarch64; do
  printf '#!/bin/sh\nexec clang -Wno-unused-command-line-argument "$@"\n' > $X/$A-darwin-clang
  printf '#!/bin/sh\nexec ld64.lld-18 -platform_version macos 11.0 14.5 "$@"\n' > $X/$A-darwin-ld
  chmod +x $X/$A-darwin-clang $X/$A-darwin-ld
done

# 3. FPC source with Makefiles. Debian's fpc-source strips makefile.cpu and compiler/msg;
#    add them back (or use the upstream 3.2.2 source tarball instead, which has both).
S=$HOME/fpcsrc; cp -r /usr/share/fpcsrc/3.2.2 "$S"
printf 'CPUNAMES=int64p math set setjump setjumph x86_64 cpuh\nCPUINCNAMES=$(addsuffix .inc,$(CPUNAMES))\n' > $S/rtl/x86_64/makefile.cpu
printf 'CPUNAMES=aarch64 int64p math set setjump setjumph cpuh strings stringss\nCPUINCNAMES=$(addsuffix .inc,$(CPUNAMES))\n' > $S/rtl/aarch64/makefile.cpu
printf '[package]\nname=fpc\nversion=3.2.2\n[target]\ndirs=rtl\n' > $S/Makefile.fpc
(cd $S/rtl && fpcmake -Tall -r)
mkdir -p $S/compiler/msg
curl -sSL -o $S/compiler/msg/errore.msg \
  https://gitlab.com/freepascal.org/fpc/source/-/raw/release_3_2_2/compiler/msg/errore.msg
mkdir -p $HOME/m2i && fpc -FE$HOME/m2i -FU$HOME/m2i $S/compiler/utils/msg2inc.pp
(cd $S/compiler && $HOME/m2i/msg2inc msg/errore.msg msg msg)

# 4. aarch64 cross compiler (x86_64 uses the stock ppcx64 with -Tdarwin)
(cd $S/compiler && mkdir -p a64units && fpc -dRELEASE -dAARCH64 -O2 -Xs -Fuaarch64 -Fusystems -Fu. \
   -Fiaarch64 -Fi. -FUa64units -FE. -oppcrossa64 pp.pas && cp ppcrossa64 $X/)

# 5. RTL for both targets
make -C $S/rtl all OS_TARGET=darwin CPU_TARGET=x86_64  PP=/usr/bin/ppcx64   BINUTILSPREFIX=x86_64-darwin-  OPT="-XR$SDK"
make -C $S/rtl all OS_TARGET=darwin CPU_TARGET=aarch64 PP=$X/ppcrossa64     BINUTILSPREFIX=aarch64-darwin- OPT="-XR$SDK"

# 6. the package units the clients use, compiled in FPC's own mode (not -Mdelphi)
P=$S/packages
INC="-Fu$P/rtl-objpas/src/inc -Fi$P/rtl-objpas/src/inc -Fi$P/rtl-objpas/src/common -Fu$P/rtl-extra/src/inc -Fi$P/rtl-extra/src/inc -Fi$P/rtl-extra/src/unix -Fi$P/rtl-extra/src/bsd -Fi$P/rtl-extra/src/darwin -Fu$P/rtl-extra/src/unix -Fu$P/paszlib/src -Fi$P/paszlib/src -Fu$P/hash/src -Fu$P/pasjpeg/src -Fi$P/pasjpeg/src -Fu$P/fcl-base/src -Fi$P/fcl-base/src/unix -Fu$P/fcl-image/src -Fi$P/fcl-image/src -Fu$P/fcl-net/src -Fi$P/fcl-net/src/unix -Fu$P/fcl-net/src/unix"
for A in x86_64 aarch64; do
  PC=/usr/bin/ppcx64; [ $A = aarch64 ] && PC=$X/ppcrossa64
  OUT=$HOME/pkgunits/$A-darwin; mkdir -p $OUT
  for u in rtl-objpas/src/inc/strutils.pp rtl-extra/src/unix/sockets.pp fcl-net/src/netdb.pp paszlib/src/zstream.pp \
           paszlib/src/gzio.pas fcl-image/src/fpimage.pp fcl-image/src/fpreadbmp.pp fcl-image/src/fpreadgif.pas \
           fcl-image/src/fpreadjpeg.pas fcl-image/src/fpreadpng.pp fcl-image/src/fpwritepng.pp fcl-image/src/fpwritebmp.pp; do
    $PC -n -Tdarwin -XP$A-darwin- -XR$SDK -O2 -Fu$S/rtl/units/$A-darwin $INC -FU$OUT $P/$u
  done
  # 7. the fpc wrapper handed to scripts/build.sh as FPC=
  cat > $X/fpc-darwin-$A <<EOW
#!/bin/sh
case "\$1" in -i*) exec $PC -Tdarwin "\$@";; esac
exec $PC -n -Tdarwin -XP$A-darwin- -XR$SDK -Fu$S/rtl/units/$A-darwin -Fu$HOME/pkgunits/$A-darwin -Fl$SDK/usr/lib "\$@"
EOW
  chmod +x $X/fpc-darwin-$A
done
# For frameworks (Cocoa back end) add to the wrapper: -k-F$SDK/System/Library/Frameworks
# and link with {$linkframework Cocoa} etc. (not tested here).
# arm64 outputs carry lld's ad-hoc LC_CODE_SIGNATURE, so they start on Apple Silicon unsigned otherwise.
