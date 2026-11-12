# The 4.x/5.0 engine library (Track C1). Builds a shared library the
# Pascal launcher loads at run time, and its tests.
#   make            build/libgraalengine.so (GraalEngineRepro.dll on Windows)
#   make test       the C++ recording-host tests
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
CPPFLAGS += -Iinclude -Isrc -I../gs2 -DGRAALENGINE_BUILD
LDLIBS = -lz

# The GS2 machine (common/cpp/gs2) is linked in: the menus run on it.
GS2 = ../gs2/loader.cpp ../gs2/machine.cpp ../gs2/var.cpp ../gs2/startscripts.cpp \
      ../gs2/engine_commands.cpp ../gs2/delivery.cpp
SOURCES = src/exports.cpp src/engine.cpp src/canvas.cpp src/scripts.cpp $(GS2)
HEADERS = include/graalengine.h include/graalengine_slots.def src/host.hpp src/canvas.hpp src/engine.hpp

ifeq ($(OS),Windows_NT)
# Not GraalEngine.dll: the player's install has the original under that
# name, and the start menus are read from it.
LIB = build/GraalEngineRepro.dll
LIBFLAGS = -shared -static-libgcc -static-libstdc++ -Wl,--out-implib,build/libgraalengine.dll.a
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

$(LIB): $(SOURCES) $(HEADERS) | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(LIBFLAGS) $(SOURCES) -o $@ $(LDLIBS)

# The tests compile the sources in, so they can hang their own controls on
# the canvas; the launcher-side test (Pascal) loads the shared library.
build/engine-test$(EXE): tests/engine_test.cpp $(SOURCES) $(HEADERS) | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/engine_test.cpp $(SOURCES) -o $@ $(LDLIBS)

test: $(LIB) build/engine-test$(EXE)
	./build/engine-test$(EXE)
	python3 tests/check_exports.py $(LIB)

clean:
	rm -rf build
