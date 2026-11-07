# host4208: system C++ only. Not on the FreePascal path.
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LDFLAGS ?= -lz

SRC = src/main.cpp src/surface.cpp src/login.cpp
OUT = build/host4208

.PHONY: all clean

all: $(OUT)

build:
	mkdir -p build

$(OUT): $(SRC) src/surface.hpp src/login.hpp | build
	$(CXX) $(CXXFLAGS) -o $@ $(SRC) $(LDFLAGS)

clean:
	rm -rf build
