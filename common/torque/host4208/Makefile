# host4208: system C++ only. Not on the FreePascal path.
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LDFLAGS ?= -lz
UNAME_S := $(shell uname -s)
ifneq ($(filter MINGW% MSYS% CYGWIN%,$(UNAME_S)),)
  LDFLAGS += -lws2_32
endif
ifeq ($(OS),Windows_NT)
  LDFLAGS += -lws2_32
endif

SRC = src/main.cpp src/surface.cpp src/controls.cpp src/login.cpp
OUT = build/host4208

.PHONY: all clean

all: $(OUT)

build:
	mkdir -p build

$(OUT): $(SRC) src/surface.hpp src/controls.hpp src/login.hpp | build
	$(CXX) $(CXXFLAGS) -o $@ $(SRC) $(LDFLAGS)

clean:
	rm -rf build
