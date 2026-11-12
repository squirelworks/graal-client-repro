CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

LIB = loader.cpp machine.cpp var.cpp startscripts.cpp engine_commands.cpp
HEADERS = gs2.hpp startscripts.hpp engine_commands.hpp

.PHONY: all test clean
all: build/gs2-test build/gs2-dis build/gs2-scan

build:
	mkdir -p build

build/gs2-test: $(LIB) $(HEADERS) tests/gs2_test.cpp tests/assembler.hpp | build
	$(CXX) $(CXXFLAGS) $(LIB) tests/gs2_test.cpp -o $@ -lz

build/gs2-dis: $(LIB) $(HEADERS) tools/gs2_dis.cpp | build
	$(CXX) $(CXXFLAGS) $(LIB) tools/gs2_dis.cpp -o $@ -lz

build/gs2-scan: $(LIB) $(HEADERS) tools/gs2_scan.cpp | build
	$(CXX) $(CXXFLAGS) $(LIB) tools/gs2_scan.cpp -o $@ -lz

test: build/gs2-test build/gs2-dis build/gs2-scan
	./build/gs2-test

clean:
	rm -rf build
