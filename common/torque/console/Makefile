CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

.PHONY: all test clean
all: build/dso-inspect

build:
	mkdir -p build

build/dso-inspect: dso.cpp dso.hpp instructions.cpp instructions.hpp dso_inspect.cpp | build
	$(CXX) $(CXXFLAGS) dso.cpp instructions.cpp dso_inspect.cpp -o $@

build/dso-test: dso.cpp dso.hpp tests/dso_test.cpp | build
	$(CXX) $(CXXFLAGS) dso.cpp tests/dso_test.cpp -o $@

build/instructions-test: instructions.cpp instructions.hpp tests/instructions_test.cpp | build
	$(CXX) $(CXXFLAGS) instructions.cpp tests/instructions_test.cpp -o $@

test: build/dso-test build/instructions-test build/dso-inspect
	./build/dso-test
	./build/instructions-test
	./build/dso-inspect --little-floats build/instruction-fixture.dso --instructions > build/instruction-result.txt
	grep -q '3 instructions; not executed' build/instruction-result.txt
	./build/dso-inspect --little-floats build/unknown-instruction-fixture.dso
	./build/dso-inspect --little-floats build/unknown-instruction-fixture.dso --instructions; test $$? -eq 1

clean:
	rm -rf build
