CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

.PHONY: test clean
build:
	mkdir -p build
build/vm-test: execute.hpp execute.cpp tests.cpp | build
	$(CXX) $(CXXFLAGS) execute.cpp tests.cpp -o $@
test: build/vm-test
	./build/vm-test
clean:
	rm -rf build
