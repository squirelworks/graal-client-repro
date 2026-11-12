CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
LIBS = -lz -lbz2
ifeq ($(OS),Windows_NT)
LIBS += -lws2_32
endif

NET = net/gtypes.cpp net/gen5.cpp net/profile.cpp net/socket.cpp net/connection.cpp
CACHE = cache/des.cpp cache/grescr.cpp
HDRS = $(wildcard net/*.hpp cache/*.hpp tests/*.hpp)

.PHONY: all test clean
all: build/quattro-session

build:
	mkdir -p build

build/codec-test: $(NET) $(HDRS) tests/codec_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tests/codec_test.cpp -o $@ $(LIBS)

build/cache-test: $(CACHE) $(HDRS) tests/cache_test.cpp | build
	$(CXX) $(CXXFLAGS) $(CACHE) tests/cache_test.cpp -o $@

build/session-test: $(NET) $(HDRS) tests/session_test.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tests/session_test.cpp -o $@ $(LIBS) -pthread

build/quattro-session: $(NET) $(HDRS) tools/quattro_session.cpp | build
	$(CXX) $(CXXFLAGS) $(NET) tools/quattro_session.cpp -o $@ $(LIBS)

test: build/codec-test build/cache-test build/session-test build/quattro-session
	./build/codec-test
	./build/cache-test
	./build/session-test
	./build/quattro-session --list | grep -q 'G3D0511C'

clean:
	rm -rf build
