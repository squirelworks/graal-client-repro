CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

ENGINE = engine.cpp interpret.cpp builtins.cpp classes304.cpp prefs304.cpp ../dso.cpp ../instructions.cpp
HEADERS = engine.hpp internal.hpp ../dso.hpp ../instructions.hpp

.PHONY: all test clean
all: build/tq-boot build/engine-test

build:
	mkdir -p build

build/tq-boot: $(ENGINE) $(HEADERS) host/tq_boot.cpp | build
	$(CXX) $(CXXFLAGS) $(ENGINE) host/tq_boot.cpp -o $@

build/engine-test: $(ENGINE) $(HEADERS) tests/engine_test.cpp tests/assembler.hpp | build
	$(CXX) $(CXXFLAGS) $(ENGINE) tests/engine_test.cpp -o $@

test: build/engine-test build/tq-boot
	./build/engine-test

clean:
	rm -rf build
