CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LDLIBS = -lz

SOURCES = image.cpp gft.cpp bitmap_array.cpp canvas.cpp
HEADERS = image.hpp gft.hpp bitmap_array.hpp canvas.hpp

.PHONY: all test lab clean
all: build/gui-inspect

build:
	mkdir -p build

build/gui-inspect: $(SOURCES) $(HEADERS) gui_inspect.cpp | build
	$(CXX) $(CXXFLAGS) $(SOURCES) gui_inspect.cpp -o $@ $(LDLIBS)

build/gui-test: $(SOURCES) $(HEADERS) tests/gui_test.cpp | build
	$(CXX) $(CXXFLAGS) $(SOURCES) tests/gui_test.cpp -o $@ $(LDLIBS)

test: build/gui-test build/gui-inspect
	./build/gui-test

# Checks against an owner-supplied 3.04 install; skips when TORQUE304_RELEASE is unset.
lab: build/gui-inspect
	sh tests/lab_check.sh build/gui-inspect

clean:
	rm -rf build
