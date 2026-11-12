CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

SOURCES = parser.cpp codegen.cpp
HEADERS = ast.hpp parser.hpp compile.hpp opcodes.hpp ../dso.hpp

.PHONY: all test clean
all: build/ts-compile

build:
	mkdir -p build

build/ts-compile: $(SOURCES) $(HEADERS) tscompile.cpp | build
	$(CXX) $(CXXFLAGS) $(SOURCES) tscompile.cpp -o $@

build/compiler-test: $(SOURCES) $(HEADERS) ../dso.cpp ../instructions.cpp ../instructions.hpp tests/compiler_test.cpp | build
	$(CXX) $(CXXFLAGS) $(SOURCES) ../dso.cpp ../instructions.cpp tests/compiler_test.cpp -o $@

test: build/compiler-test build/ts-compile
	./build/compiler-test

clean:
	rm -rf build
