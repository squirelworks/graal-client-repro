CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LDLIBS = -lz

SOURCES = image.cpp gft.cpp bitmap_array.cpp canvas.cpp profile.cpp
HEADERS = image.hpp gft.hpp bitmap_array.hpp canvas.hpp profile.hpp

# The control renderer reads the console engine's object tree.
ENGINE_DIR = ../console/engine
ENGINE = $(ENGINE_DIR)/engine.cpp $(ENGINE_DIR)/interpret.cpp $(ENGINE_DIR)/builtins.cpp \
         $(ENGINE_DIR)/classes304.cpp $(ENGINE_DIR)/prefs304.cpp ../console/dso.cpp ../console/instructions.cpp
ENGINE_HEADERS = $(ENGINE_DIR)/engine.hpp $(ENGINE_DIR)/internal.hpp ../console/dso.hpp ../console/instructions.hpp
COMPILER = ../console/compiler/parser.cpp ../console/compiler/codegen.cpp
COMPILER_HEADERS = ../console/compiler/ast.hpp ../console/compiler/parser.hpp ../console/compiler/compile.hpp \
                   ../console/compiler/opcodes.hpp
RENDER = render.cpp jpeg.cpp system_font.cpp
RENDER_HEADERS = render.hpp jpeg.hpp system_font.hpp
# stb_image and stb_truetype (third-party, public domain) as system headers,
# so their own warnings do not trip -Werror
STB_FLAGS = -isystem ../../cpp/third_party/stb

.PHONY: all test lab clean
all: build/gui-inspect build/tq-shot

build:
	mkdir -p build

build/gui-inspect: $(SOURCES) $(HEADERS) gui_inspect.cpp | build
	$(CXX) $(CXXFLAGS) $(SOURCES) gui_inspect.cpp -o $@ $(LDLIBS)

build/gui-test: $(SOURCES) $(HEADERS) tests/gui_test.cpp | build
	$(CXX) $(CXXFLAGS) $(SOURCES) tests/gui_test.cpp -o $@ $(LDLIBS)

build/render-test: $(SOURCES) $(HEADERS) $(RENDER) $(RENDER_HEADERS) $(ENGINE) $(ENGINE_HEADERS) tests/render_test.cpp | build
	$(CXX) $(CXXFLAGS) $(STB_FLAGS) $(SOURCES) $(RENDER) $(ENGINE) tests/render_test.cpp -o $@ $(LDLIBS)

build/tq-shot: $(SOURCES) $(HEADERS) $(RENDER) $(RENDER_HEADERS) $(ENGINE) $(ENGINE_HEADERS) $(COMPILER) $(COMPILER_HEADERS) host/tq_shot.cpp | build
	$(CXX) $(CXXFLAGS) $(STB_FLAGS) $(SOURCES) $(RENDER) $(ENGINE) $(COMPILER) host/tq_shot.cpp -o $@ $(LDLIBS)

test: build/gui-test build/gui-inspect build/render-test build/tq-shot
	./build/gui-test
	./build/render-test

# Checks against an owner-supplied 3.04 install; skips when TORQUE304_RELEASE is unset.
lab: build/gui-inspect build/tq-shot
	sh tests/lab_check.sh build/gui-inspect build/tq-shot

clean:
	rm -rf build
