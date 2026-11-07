# host304: system C++ only. Not on the FreePascal path.
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LDFLAGS ?= -lz

SRC = src/main.cpp src/guigraal.cpp src/script.cpp src/login.cpp
OUT = build/host304

.PHONY: all clean

all: $(OUT)

build:
	mkdir -p build

$(OUT): $(SRC) src/guigraal.hpp src/script.hpp src/login.hpp | build
	$(CXX) $(CXXFLAGS) -o $@ $(SRC) $(LDFLAGS)

clean:
	rm -rf build
