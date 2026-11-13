CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
FPC ?= fpc
# Extra Free Pascal flags for make lib (the Windows CI names the unit folders
# here). The shell would eat their backslashes and expand FPC's own *
# wildcard, so the recipe takes them with forward slashes and no globbing.
FPCFLAGS ?=
LIB_FPCFLAGS = $(subst \,/,$(FPCFLAGS))

# The window back end and the program's libraries per system. PLATFORM is
# linux, windows or macos; set it by hand to cross-build (for example
# make PLATFORM=windows CXX=x86_64-w64-mingw32-g++).
ifeq ($(OS),Windows_NT)
PLATFORM ?= windows
else ifeq ($(shell uname -s),Darwin)
PLATFORM ?= macos
else
PLATFORM ?= linux
endif
ifeq ($(PLATFORM),windows)
EXE = .exe
DL_LIBS =
WINDOW_SRC = host/window_win32.cpp
# A GUI program (no console window), linked statically so the exe needs no
# MinGW DLLs beside it; the resources carry the version info and manifest.
WINDOW_LIBS = -mwindows -static -static-libgcc -static-libstdc++ -lgdi32 -luser32
WINDOW_RES = build/graal304-torque.res.o
WINDRES ?= $(patsubst %g++,%windres,$(patsubst %c++,%windres,$(notdir $(CXX))))
else ifeq ($(PLATFORM),macos)
EXE =
DL_LIBS =
WINDOW_SRC = host/window_cocoa.mm
WINDOW_LIBS = -framework Cocoa
WINDOW_RES =
else
EXE =
DL_LIBS = -ldl
WINDOW_SRC = host/window_x11.cpp
WINDOW_LIBS = -lX11
WINDOW_RES =
endif

ENGINE_DIR = ../console/engine
ENGINE = $(ENGINE_DIR)/engine.cpp $(ENGINE_DIR)/interpret.cpp $(ENGINE_DIR)/builtins.cpp \
  $(ENGINE_DIR)/classes304.cpp $(ENGINE_DIR)/prefs304.cpp $(ENGINE_DIR)/input304.cpp \
  $(ENGINE_DIR)/textlist304.cpp \
  ../console/dso.cpp ../console/instructions.cpp
COMPILER = ../console/compiler/parser.cpp ../console/compiler/codegen.cpp
CONTROL = guigraal304.cpp
HEADERS = guigraal304.hpp game304.hpp pascal_game304.hpp game304_abi.h $(ENGINE_DIR)/engine.hpp

# The 3.04 Pascal game as a shared library (make lib; needs Free Pascal).
GAME_SRC = ../../../graal-3.04-G3D03014/src
GAME_SRC_3153 = ../../../graal-3.153-G3D28015/src
# The other 3.x builds on this program, each its own library over its own
# folder's units: 3.0beta and 3.01 (3.04's, on the gen-4 link) and 3.151
# (3.153's, on Linux).
GAME_SRC_30B = ../../../graal-3.0beta-G3D16053/src
GAME_SRC_301 = ../../../graal-3.01-G3D27063/src
GAME_SRC_3151 = ../../../graal-3.151-G3D27015/src
# This folder from GAME_SRC. Paths given to a native Windows compiler stay
# relative: it misreads MSYS (/d/a/...) paths (scripts/build.sh).
FROM_GAME = ../../common/torque/guigraal
LIB_DIR = build/lib

.PHONY: all test lib clean program
all: build/guigraal-test$(EXE) build/frame-test$(EXE) build/tq-play$(EXE) build/graal304-torque$(EXE)

build:
	mkdir -p build

build/guigraal-test$(EXE): $(CONTROL) $(ENGINE) $(COMPILER) $(HEADERS) tests/guigraal_test.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) $(ENGINE) $(COMPILER) tests/guigraal_test.cpp -o $@

HOST = host/boot304.cpp pascal_game304.cpp
HOST_HEADERS = host/boot304.hpp

build/tq-play$(EXE): $(CONTROL) $(HOST) $(ENGINE) $(COMPILER) $(HEADERS) $(HOST_HEADERS) host/tq_play.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) $(HOST) $(ENGINE) $(COMPILER) host/tq_play.cpp -o $@ $(DL_LIBS)

# The windowed 3.04 program: the canvas renderer, mouse and a window (X11 on
# Linux, Win32 on Windows, Cocoa on macOS).
GUI_DIR = ../gui
GUI = $(GUI_DIR)/image.cpp $(GUI_DIR)/gft.cpp $(GUI_DIR)/bitmap_array.cpp $(GUI_DIR)/canvas.cpp \
  $(GUI_DIR)/profile.cpp $(GUI_DIR)/render.cpp $(GUI_DIR)/mouse.cpp $(GUI_DIR)/jpeg.cpp $(GUI_DIR)/system_font.cpp
# stb_image and stb_truetype as system headers (third-party; their own
# warnings do not trip -Werror)
STB_FLAGS = -isystem ../../cpp/third_party/stb
GUI_HEADERS = $(GUI_DIR)/render.hpp $(GUI_DIR)/mouse.hpp $(GUI_DIR)/canvas.hpp host/window.hpp host/frame304.hpp

build/graal304-torque$(EXE): $(CONTROL) $(HOST) $(GUI) $(ENGINE) $(COMPILER) $(HEADERS) $(HOST_HEADERS) $(GUI_HEADERS) \
    host/frame304.cpp $(WINDOW_SRC) host/graal304_torque.cpp $(WINDOW_RES) | build
	$(CXX) $(CXXFLAGS) $(STB_FLAGS) $(if $(filter macos,$(PLATFORM)),-fobjc-arc) $(CONTROL) $(HOST) $(GUI) $(ENGINE) $(COMPILER) \
	  host/frame304.cpp $(WINDOW_SRC) host/graal304_torque.cpp $(WINDOW_RES) -o $@ $(DL_LIBS) -lz $(WINDOW_LIBS)

# Windows: version info and manifest (graal-3.04-G3D03014/src/Graal304Torque.rc,
# which the release workflow stamps with the others).
build/graal304-torque.res.o: $(GAME_SRC)/Graal304Torque.rc ../../../common/win/graal-delphi.manifest | build
	cd $(GAME_SRC) && $(WINDRES) -O coff Graal304Torque.rc -o $(FROM_GAME)/$@

# The frame logic without a window, for tests.
build/frame-test$(EXE): $(CONTROL) $(GUI) $(ENGINE) $(COMPILER) $(HEADERS) $(GUI_HEADERS) host/frame304.cpp \
    tests/frame_test.cpp | build
	$(CXX) $(CXXFLAGS) $(STB_FLAGS) $(CONTROL) $(GUI) $(ENGINE) $(COMPILER) host/frame304.cpp tests/frame_test.cpp -o $@ -lz

program: build/graal304-torque$(EXE)

# macOS: the program as an app bundle with the game library inside it
# (make lib all app; APP_LIB picks the library, 3.153's for its zip). Put
# graal304-torque.app beside main.cs; it finds the install from there.
APP = build/graal304-torque.app
APP_LIB ?= libGame304Lib.dylib
APP_VERSION ?= $(or $(patsubst v%,%,$(VERSION)),0.0.0)
.PHONY: app
app: build/graal304-torque host/Info.plist
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp build/graal304-torque $(LIB_DIR)/$(APP_LIB) $(APP)/Contents/MacOS/
	sed -e 's/@VERSION@/$(APP_VERSION)/g' host/Info.plist > $(APP)/Contents/Info.plist
	printf 'APPL????' > $(APP)/Contents/PkgInfo

lib: | build
	mkdir -p $(LIB_DIR)
	set -f; cd $(GAME_SRC) && $(FPC) -Mdelphi -Sh -vew -O2 $(LIB_FPCFLAGS) -Fu../../common -Fu. \
	  -FE$(FROM_GAME)/$(LIB_DIR) -FU$(FROM_GAME)/$(LIB_DIR) Game304Lib.lpr
	mkdir -p $(LIB_DIR)/units3153
	set -f; cd $(GAME_SRC_3153) && $(FPC) -Mdelphi -Sh -vew -O2 $(LIB_FPCFLAGS) -Fu../../common -Fu. \
	  -FE$(FROM_GAME)/$(LIB_DIR) -FU$(FROM_GAME)/$(LIB_DIR)/units3153 Game3153Lib.lpr
	mkdir -p $(LIB_DIR)/units30b
	set -f; cd $(GAME_SRC_30B) && $(FPC) -Mdelphi -Sh -vew -O2 $(LIB_FPCFLAGS) -Fu../../common -Fu. \
	  -FE$(FROM_GAME)/$(LIB_DIR) -FU$(FROM_GAME)/$(LIB_DIR)/units30b Game30bLib.lpr
	mkdir -p $(LIB_DIR)/units301
	set -f; cd $(GAME_SRC_301) && $(FPC) -Mdelphi -Sh -vew -O2 $(LIB_FPCFLAGS) -Fu../../common -Fu. \
	  -FE$(FROM_GAME)/$(LIB_DIR) -FU$(FROM_GAME)/$(LIB_DIR)/units301 Game301Lib.lpr
	mkdir -p $(LIB_DIR)/units3151
	set -f; cd $(GAME_SRC_3151) && $(FPC) -Mdelphi -Sh -vew -O2 $(LIB_FPCFLAGS) -Fu../../common -Fu. \
	  -FE$(FROM_GAME)/$(LIB_DIR) -FU$(FROM_GAME)/$(LIB_DIR)/units3151 Game3151Lib.lpr

test: build/guigraal-test$(EXE) build/frame-test$(EXE)
	./build/guigraal-test$(EXE)
	./build/frame-test$(EXE)

clean:
	rm -rf build
