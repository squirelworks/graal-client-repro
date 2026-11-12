# The 4.x/5.0 engine library (Track C1). Builds a shared library the
# Pascal launcher loads at run time, and its tests.
#   make            build/libgraalengine.so (GraalEngine.dll on Windows)
#   make test       the C++ recording-host tests
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
CPPFLAGS += -Iinclude -Isrc -DGRAALENGINE_BUILD

SOURCES = src/exports.cpp src/engine.cpp src/canvas.cpp
HEADERS = include/graalengine.h include/graalengine_slots.def src/host.hpp src/canvas.hpp src/engine.hpp

ifeq ($(OS),Windows_NT)
LIB = build/GraalEngine.dll
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
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(LIBFLAGS) $(SOURCES) -o $@

# The tests compile the sources in, so they can hang their own controls on
# the canvas; the launcher-side test (Pascal) loads the shared library.
build/engine-test$(EXE): tests/engine_test.cpp $(SOURCES) $(HEADERS) | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/engine_test.cpp $(SOURCES) -o $@

test: $(LIB) build/engine-test$(EXE)
	./build/engine-test$(EXE)
	python3 tests/check_exports.py $(LIB)

clean:
	rm -rf build
