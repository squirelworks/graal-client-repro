CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2

.PHONY: test clean
build:
	mkdir -p build
build/vm-test: execute.hpp execute.cpp tests.cpp | build
	$(CXX) $(CXXFLAGS) execute.cpp tests.cpp -o $@
build/dso-run-test: ../dso.cpp ../dso.hpp execute.hpp execute.cpp run_dso.hpp run_dso.cpp run_dso_test.cpp | build
	$(CXX) $(CXXFLAGS) ../dso.cpp execute.cpp run_dso.cpp run_dso_test.cpp -o $@
test: build/vm-test build/dso-run-test
	./build/vm-test
	./build/dso-run-test
clean:
	rm -rf build
