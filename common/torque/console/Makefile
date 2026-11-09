CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

.PHONY: all test clean
all: build/dso-inspect

build:
	mkdir -p build

build/dso-inspect: dso.cpp dso.hpp dso_inspect.cpp | build
	$(CXX) $(CXXFLAGS) dso.cpp dso_inspect.cpp -o $@

build/dso-test: dso.cpp dso.hpp tests/dso_test.cpp | build
	$(CXX) $(CXXFLAGS) dso.cpp tests/dso_test.cpp -o $@

test: build/dso-test build/dso-inspect
	./build/dso-test

clean:
	rm -rf build
