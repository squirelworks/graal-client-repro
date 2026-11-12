CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

ENGINE = engine.cpp interpret.cpp builtins.cpp classes304.cpp prefs304.cpp input304.cpp textlist304.cpp ../dso.cpp ../instructions.cpp
HEADERS = engine.hpp internal.hpp ../dso.hpp ../instructions.hpp

.PHONY: all test clean
all: build/tq-boot build/engine-test build/input-test

build:
	mkdir -p build

COMPILER = ../compiler/parser.cpp ../compiler/codegen.cpp
COMPILER_HEADERS = ../compiler/ast.hpp ../compiler/parser.hpp ../compiler/compile.hpp ../compiler/opcodes.hpp

build/tq-boot: $(ENGINE) $(HEADERS) $(COMPILER) $(COMPILER_HEADERS) host/tq_boot.cpp | build
	$(CXX) $(CXXFLAGS) $(ENGINE) $(COMPILER) host/tq_boot.cpp -o $@

build/engine-test: $(ENGINE) $(HEADERS) tests/engine_test.cpp tests/assembler.hpp | build
	$(CXX) $(CXXFLAGS) $(ENGINE) tests/engine_test.cpp -o $@

build/input-test: $(ENGINE) $(HEADERS) $(COMPILER) $(COMPILER_HEADERS) tests/input_test.cpp | build
	$(CXX) $(CXXFLAGS) $(ENGINE) $(COMPILER) tests/input_test.cpp -o $@

test: build/engine-test build/tq-boot build/input-test
	./build/engine-test
	./build/input-test

clean:
	rm -rf build
