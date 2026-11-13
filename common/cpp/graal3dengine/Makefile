# The 4.x/5.0 3D library (Track C4). Builds a shared library beside the
# engine library (common/cpp/graalengine), which it links against, as the
# original Graal3DEngine.dll imports from GraalEngine.dll.
#   make            build/libgraal3dengine.so (Graal3DEngineRepro.dll on Windows)
#   make test       the link against the recorded vectors, then both
#                   libraries over loopback UDP, then the export check
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
CPPFLAGS += -Iinclude -Isrc -I../graalengine/include -I../third_party/torque3d -DGRAAL3DENGINE_BUILD
LDLIBS = -lz -lbz2

CORE = src/bits.cpp src/world.cpp src/link.cpp src/udp.cpp ../third_party/torque3d/huffman.cpp
SOURCES = src/exports.cpp $(CORE)
HEADERS = include/graal3dengine.h ../graalengine/include/graalengine.h ../graalengine/include/graalengine_slots.def \
          $(wildcard src/*.hpp) ../third_party/torque3d/huffman.hpp tests/vectors.hpp
ENGINE_DIR = ../graalengine

ifeq ($(OS),Windows_NT)
# Not Graal3DEngine.dll: the player's install has the original under that name.
LIB = build/Graal3DEngineRepro.dll
ENGINE_LIB = $(ENGINE_DIR)/build/GraalEngineRepro.dll
ENGINE_LINK = $(ENGINE_DIR)/build/libgraalengine.dll.a
LIBFLAGS = -shared -static-libgcc -static-libstdc++ -Wl,--out-implib,build/libgraal3dengine.dll.a
LIB_LINK = build/libgraal3dengine.dll.a
LDLIBS += -lws2_32
EXE = .exe
RPATH =
else
LIB = build/libgraal3dengine.so
ENGINE_LIB = $(ENGINE_DIR)/build/libgraalengine.so
ENGINE_LINK = -L$(ENGINE_DIR)/build -lgraalengine
LIBFLAGS = -shared -fPIC -fvisibility=hidden
LIB_LINK = -Lbuild -lgraal3dengine
EXE =
ifeq ($(shell uname -s),Darwin)
RPATH = -Wl,-rpath,@loader_path
else
RPATH = -Wl,-rpath,'$$ORIGIN'
endif
endif

.PHONY: all test clean engine
all: $(LIB)

build:
	mkdir -p build

engine:
	$(MAKE) -C $(ENGINE_DIR) all CXX="$(CXX)" CXXFLAGS="$(CXXFLAGS)"

$(ENGINE_LIB): engine

$(LIB): $(SOURCES) $(HEADERS) engine | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(LIBFLAGS) $(SOURCES) -o $@ $(ENGINE_LINK) $(LDLIBS) $(RPATH)
	cp $(ENGINE_LIB) build/

build/link-test$(EXE): tests/link_test.cpp $(CORE) $(HEADERS) | build
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/link_test.cpp $(CORE) -o $@ $(LDLIBS)

build/bridge-test$(EXE): tests/bridge_test.cpp $(LIB) | build
	$(CXX) $(CPPFLAGS) -UGRAAL3DENGINE_BUILD $(CXXFLAGS) tests/bridge_test.cpp src/bits.cpp src/udp.cpp \
	  ../third_party/torque3d/huffman.cpp -o $@ $(LIB_LINK) $(ENGINE_LINK) $(LDLIBS) $(RPATH)

test: build/link-test$(EXE) build/bridge-test$(EXE)
	./build/link-test$(EXE)
	./build/bridge-test$(EXE)
	python3 tests/check_exports.py $(LIB)

clean:
	rm -rf build
