CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LIBS = -lz -lbz2
X11_LIBS =
ifeq ($(OS),Windows_NT)
LIBS += -lws2_32
else
# X11 is optional: with no Xlib headers the program runs headless only.
ifneq ($(wildcard /usr/include/X11/Xlib.h),)
X11_DEFS = -DQUATTRO_X11
X11_LIBS = -lX11
endif
endif

NET = net/gtypes.cpp net/gen5.cpp net/profile.cpp net/socket.cpp net/connection.cpp
CACHE = cache/des.cpp cache/grescr.cpp
# The software canvas and PNG reader are shared with the Torque GUI layer.
TGUI = ../../torque/gui/image.cpp ../../torque/gui/canvas.cpp ../../torque/gui/gft.cpp ../../torque/gui/bitmap_array.cpp
FILES = files/level.cpp files/gani.cpp files/gmap.cpp
DRAW = draw/world.cpp draw/assets.cpp draw/body_colors.cpp draw/hud.cpp draw/ui_font.cpp draw/ui_font_data.cpp $(TGUI)
GS2 = ../gs2/loader.cpp ../gs2/machine.cpp ../gs2/var.cpp ../gs2/startscripts.cpp ../gs2/engine_commands.cpp ../gs2/delivery.cpp ../gs2/gui.cpp ../gs2/gui_draw.cpp ../gs2/emitter.cpp
SHELL_SRC = shell/program.cpp shell/scripts.cpp shell/gui_host.cpp world/player.cpp world/walk.cpp world/actions.cpp $(GS2) $(CACHE)
HDRS = $(wildcard net/*.hpp cache/*.hpp files/*.hpp draw/*.hpp shell/*.hpp world/*.hpp tests/*.hpp ../../torque/gui/*.hpp ../gs2/*.hpp)

.PHONY: all test clean
all: build/quattro-session build/quattro-play

build:
	mkdir -p build

build/codec-test: $(NET) $(HDRS) tests/codec_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tests/codec_test.cpp -o $@ $(LIBS)

build/cache-test: $(CACHE) $(HDRS) tests/cache_test.cpp | build
	$(CXX) $(CXXFLAGS) $(CACHE) tests/cache_test.cpp -o $@

build/session-test: $(NET) $(HDRS) tests/session_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tests/session_test.cpp -o $@ $(LIBS) -pthread

build/level-test: $(FILES) $(DRAW) $(HDRS) tests/level_test.cpp | build
	$(CXX) $(CXXFLAGS) $(FILES) $(DRAW) tests/level_test.cpp -o $@ $(LIBS)

build/program-test: $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(HDRS) draw/window_x11.cpp tests/program_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) $(FILES) $(DRAW) $(SHELL_SRC) draw/window_x11.cpp tests/program_test.cpp -o $@ $(LIBS) -pthread

build/props-test: $(NET) world/player.cpp world/walk.cpp world/actions.cpp $(FILES) $(HDRS) tests/props_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) world/player.cpp world/walk.cpp world/actions.cpp $(FILES) tests/props_test.cpp -o $@ $(LIBS)

build/scripts-test: $(NET) $(SHELL_SRC) $(HDRS) tests/scripts_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) shell/scripts.cpp $(GS2) $(CACHE) tests/scripts_test.cpp -o $@ $(LIBS)

build/gui-test: $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(HDRS) draw/window_x11.cpp tests/gui_host_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) $(FILES) $(DRAW) $(SHELL_SRC) draw/window_x11.cpp tests/gui_host_test.cpp -o $@ $(LIBS) -pthread

build/quattro-session: $(NET) $(HDRS) tools/quattro_session.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tools/quattro_session.cpp -o $@ $(LIBS)

build/quattro-play: $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(HDRS) draw/window_x11.cpp tools/quattro_play.cpp | build
	$(CXX) $(CXXFLAGS) $(X11_DEFS) $(NET) $(FILES) $(DRAW) $(SHELL_SRC) draw/window_x11.cpp tools/quattro_play.cpp -o $@ $(LIBS) $(X11_LIBS)

test: build/codec-test build/cache-test build/session-test build/level-test build/props-test build/scripts-test build/program-test build/gui-test build/quattro-session build/quattro-play
	./build/codec-test
	./build/cache-test
	./build/session-test
	./build/level-test
	./build/props-test
	./build/scripts-test
	./build/program-test
	./build/gui-test
	./build/quattro-session --list | grep -q 'G3D0511C'

clean:
	rm -rf build
