# The 4.x/5.0 engine library (Track C1). Builds a shared library the
# Pascal launcher loads at run time, and its tests.
#   make            build/libgraalengine.so (GraalEngineRepro.dll on Windows)
#   make test       the C++ recording-host tests
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
CPPFLAGS += -Iinclude -Isrc -I../gs2 -I../../torque/gui -I../third_party/stb -DGRAALENGINE_BUILD
LDLIBS = -lz -lbz2

# The GS2 machine (common/cpp/gs2) is linked in: the menus run on it.
GS2 = ../gs2/loader.cpp ../gs2/machine.cpp ../gs2/var.cpp ../gs2/startscripts.cpp \
      ../gs2/engine_commands.cpp ../gs2/delivery.cpp ../gs2/gui.cpp ../gs2/gui_draw.cpp ../gs2/emitter.cpp
# PNG pictures and theme bitmap arrays come from the Torque GUI layer.
TQGUI = ../../torque/gui/image.cpp ../../torque/gui/bitmap_array.cpp
# The 2D session is the Quattro program's (common/cpp/quattro): gen-5
# connection, levels, walking and the world passes.
Q = ../quattro
QUATTRO = $(Q)/net/gtypes.cpp $(Q)/net/gen5.cpp $(Q)/net/profile.cpp $(Q)/net/socket.cpp \
          $(Q)/net/connection.cpp $(Q)/cache/des.cpp $(Q)/cache/grescr.cpp $(Q)/files/level.cpp \
          $(Q)/draw/world.cpp $(Q)/world/player.cpp $(Q)/world/walk.cpp $(Q)/shell/program.cpp \
          $(Q)/shell/scripts.cpp ../../torque/gui/canvas.cpp ../../torque/gui/gft.cpp
SOURCES = src/exports.cpp src/engine.cpp src/canvas.cpp src/scripts.cpp src/gui_host.cpp src/session.cpp \
          $(GS2) $(TQGUI) $(QUATTRO)
# Third-party, built on its own without -Werror.
HEADERS = include/graalengine.h include/graalengine_slots.def src/host.hpp src/canvas.hpp src/engine.hpp src/gui_host.hpp \
          src/session.hpp $(wildcard $(Q)/*/*.hpp)

ifeq ($(OS),Windows_NT)
# Not GraalEngine.dll: the player's install has the original under that
# name, and the start menus are read from it.
LIB = build/GraalEngineRepro.dll
LIBFLAGS = -shared -static-libgcc -static-libstdc++ -Wl,--out-implib,build/libgraalengine.dll.a
LDLIBS += -lws2_32
EXE = .exe
else
LIB = build/libgraalengine.so
LIBFLAGS = -shared -fPIC -fvisibility=hidden
EXE =
endif

.PHONY: all test clean
all: $(LIB)

build:
	mkdir -p build

build/stb_impl.o: src/stb_impl.cpp | build
	$(CXX) -Isrc -I../third_party/stb -std=c++17 -O2 -fPIC -w $(filter -m32 -m64 -fsanitize=% -g,$(CXXFLAGS)) -c src/stb_impl.cpp -o $@

$(LIB): $(SOURCES) $(HEADERS) build/stb_impl.o | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(LIBFLAGS) $(SOURCES) build/stb_impl.o -o $@ $(LDLIBS)

# The tests compile the sources in, so they can hang their own controls on
# the canvas; the launcher-side test (Pascal) loads the shared library.
build/engine-test$(EXE): tests/engine_test.cpp $(SOURCES) $(HEADERS) build/stb_impl.o | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/engine_test.cpp $(SOURCES) build/stb_impl.o -o $@ $(LDLIBS) -pthread

test: $(LIB) build/engine-test$(EXE)
	./build/engine-test$(EXE)
	python3 tests/check_exports.py $(LIB)

clean:
	rm -rf build
