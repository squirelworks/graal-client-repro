CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

.PHONY: test clean
build:
	mkdir -p build
build/native-test: functions.hpp functions.cpp tests.cpp | build
	$(CXX) $(CXXFLAGS) functions.cpp tests.cpp -o $@
test: build/native-test
	./build/native-test
clean:
	rm -rf build
