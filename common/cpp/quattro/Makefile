CXX ?= g++
PYTHON ?= python3
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LIBS = -lz -lbz2
# Override only for the isolated release-package regression; normal builds
# continue to produce build/quattro-play beside the Pascal launcher.
PLAYER ?= build/quattro-play
PLAYER_RC ?= win/quattro-play.rc
PLAYER_RESOURCE ?= build/quattro-play.res.o
X11_LIBS =
ifeq ($(OS),Windows_NT)
LIBS += -lws2_32 -ladvapi32
WINDOW_LIBS = -luser32 -lgdi32
# The release zip does not ship a compiler toolchain or third-party DLLs.
# Apply static linkage to the shipped player only, not sanitizer/test tools.
PLAYER_LDFLAGS = -static -static-libgcc -static-libstdc++
PLAYER_RES = $(PLAYER_RESOURCE)
WINDRES ?= $(patsubst %g++,%windres,$(patsubst %c++,%windres,$(notdir $(CXX))))
else ifeq ($(shell uname -s),Darwin)
# macOS: an AppKit window (draw/window_cocoa.mm), not X11.
X11_DEFS = -DQUATTRO_COCOA
WINDOW_LIBS = -framework Cocoa
COCOA = draw/window_cocoa.mm
else
# X11 is optional: with no Xlib headers the program runs headless only.
ifneq ($(wildcard /usr/include/X11/Xlib.h),)
X11_DEFS = -DQUATTRO_X11
X11_LIBS = -lX11
endif
endif

NET = net/gtypes.cpp net/gen5.cpp net/profile.cpp net/socket.cpp net/connection.cpp net/seccrypto.cpp net/seclogin.cpp
CACHE = cache/des.cpp cache/grescr.cpp
# The software canvas and PNG reader are shared with the Torque GUI layer.
TGUI = ../../torque/gui/image.cpp ../../torque/gui/canvas.cpp ../../torque/gui/gft.cpp ../../torque/gui/bitmap_array.cpp
FILES = files/level.cpp files/gani.cpp files/gmap.cpp
DRAW = draw/world.cpp draw/assets.cpp draw/body_colors.cpp draw/hud.cpp draw/ui_font.cpp draw/ui_font_data.cpp $(TGUI)
GS2 = ../gs2/loader.cpp ../gs2/machine.cpp ../gs2/var.cpp ../gs2/startscripts.cpp ../gs2/engine_commands.cpp ../gs2/delivery.cpp ../gs2/gui.cpp ../gs2/gui_draw.cpp ../gs2/emitter.cpp
SHELL_SRC = shell/program.cpp shell/npcs.cpp shell/server_text.cpp world/npcs.cpp shell/weapon_api.cpp shell/scripts.cpp shell/gui_host.cpp world/player.cpp world/walk.cpp world/actions.cpp world/effects.cpp world/floor_items.cpp world/weapons.cpp world/health.cpp world/item_list.cpp $(GS2) $(CACHE)
HDRS = $(wildcard net/*.hpp cache/*.hpp files/*.hpp draw/*.hpp shell/*.hpp world/*.hpp tests/*.hpp ../../torque/gui/*.hpp ../gs2/*.hpp)
WINDOW = draw/window_x11.cpp draw/window_native.cpp $(COCOA)

.PHONY: all test clean
all: build/quattro-session $(PLAYER)

build:
	mkdir -p build

build/codec-test: $(NET) $(HDRS) tests/codec_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tests/codec_test.cpp -o $@ $(LIBS)

build/seclogin-test: $(NET) $(HDRS) tests/seclogin_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tests/seclogin_test.cpp -o $@ $(LIBS) -pthread

build/cache-test: $(CACHE) $(HDRS) tests/cache_test.cpp | build
	$(CXX) $(CXXFLAGS) $(CACHE) tests/cache_test.cpp -o $@

build/session-test: $(NET) $(HDRS) tests/session_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tests/session_test.cpp -o $@ $(LIBS) -pthread

build/level-test: $(FILES) $(DRAW) $(HDRS) tests/level_test.cpp | build
	$(CXX) $(CXXFLAGS) $(FILES) $(DRAW) tests/level_test.cpp -o $@ $(LIBS)

build/program-test: $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(HDRS) draw/window_x11.cpp tests/program_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) $(FILES) $(DRAW) $(SHELL_SRC) draw/window_x11.cpp tests/program_test.cpp -o $@ $(LIBS) -pthread

build/props-test: $(NET) world/player.cpp world/walk.cpp world/actions.cpp world/effects.cpp world/floor_items.cpp world/weapons.cpp world/health.cpp world/item_list.cpp world/npcs.cpp $(FILES) $(HDRS) tests/props_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) world/player.cpp world/walk.cpp world/actions.cpp world/effects.cpp world/floor_items.cpp world/weapons.cpp world/health.cpp world/item_list.cpp world/npcs.cpp $(FILES) tests/props_test.cpp -o $@ $(LIBS)

build/scripts-test: $(NET) $(SHELL_SRC) $(HDRS) tests/scripts_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) shell/scripts.cpp $(GS2) $(CACHE) tests/scripts_test.cpp -o $@ $(LIBS)

build/gui-test: $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(HDRS) draw/window_x11.cpp tests/gui_host_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) $(FILES) $(DRAW) $(SHELL_SRC) draw/window_x11.cpp tests/gui_host_test.cpp -o $@ $(LIBS) -pthread

build/quattro-session: $(NET) $(HDRS) tools/quattro_session.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tools/quattro_session.cpp -o $@ $(LIBS)

ifeq ($(OS),Windows_NT)
$(PLAYER_RESOURCE): $(PLAYER_RC) ../../win/graal-delphi.manifest | build
	mkdir -p $(dir $@)
	cd $(dir $(abspath $(PLAYER_RC))) && $(WINDRES) -O coff $(notdir $(PLAYER_RC)) -o $(abspath $@)
endif

$(PLAYER): $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(HDRS) $(WINDOW) tools/quattro_play.cpp $(PLAYER_RES) | build
	mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(X11_DEFS) $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(WINDOW) tools/quattro_play.cpp $(PLAYER_RES) -o $@ $(PLAYER_LDFLAGS) $(LIBS) $(X11_LIBS) $(WINDOW_LIBS)

build/window-test: $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(HDRS) $(WINDOW) tests/window_test.cpp | build
	$(CXX) $(CXXFLAGS) $(X11_DEFS) $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(WINDOW) tests/window_test.cpp -o $@ $(LIBS) $(X11_LIBS) $(WINDOW_LIBS) -pthread

test: build/codec-test build/seclogin-test build/cache-test build/session-test build/level-test build/props-test build/scripts-test build/program-test build/gui-test build/quattro-session build/quattro-play
	./build/codec-test
	./build/seclogin-test
	./build/cache-test
	./build/session-test
	./build/level-test
	./build/props-test
	./build/scripts-test
	./build/program-test
	./build/gui-test
	./build/quattro-session --list | grep -q 'G3D0511C'
	$(PYTHON) tests/cli_numeric_test.py ./build/quattro-play

clean:
	rm -rf build
