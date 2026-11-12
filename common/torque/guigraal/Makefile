CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
FPC ?= fpc

ENGINE_DIR = ../console/engine
ENGINE = $(ENGINE_DIR)/engine.cpp $(ENGINE_DIR)/interpret.cpp $(ENGINE_DIR)/builtins.cpp \
  $(ENGINE_DIR)/classes304.cpp $(ENGINE_DIR)/prefs304.cpp $(ENGINE_DIR)/input304.cpp \
  $(ENGINE_DIR)/textlist304.cpp \
  ../console/dso.cpp ../console/instructions.cpp
COMPILER = ../console/compiler/parser.cpp ../console/compiler/codegen.cpp
CONTROL = guigraal304.cpp
HEADERS = guigraal304.hpp game304.hpp pascal_game304.hpp game304_abi.h $(ENGINE_DIR)/engine.hpp

# The 3.04 Pascal game as a shared library (make lib; needs Free Pascal).
GAME_SRC = ../../../graal-3.04-G3D03014/src
LIB_DIR = build/lib

.PHONY: all test lib clean
all: build/guigraal-test build/tq-play

build:
	mkdir -p build

build/guigraal-test: $(CONTROL) $(ENGINE) $(COMPILER) $(HEADERS) tests/guigraal_test.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) $(ENGINE) $(COMPILER) tests/guigraal_test.cpp -o $@

build/tq-play: $(CONTROL) pascal_game304.cpp $(ENGINE) $(COMPILER) $(HEADERS) host/tq_play.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) pascal_game304.cpp $(ENGINE) $(COMPILER) host/tq_play.cpp -o $@ -ldl

lib: | build
	mkdir -p $(LIB_DIR)
	cd $(GAME_SRC) && $(FPC) -Mdelphi -Sh -vew -O2 -Fu../../common -Fu. \
	  -FE$(CURDIR)/$(LIB_DIR) -FU$(CURDIR)/$(LIB_DIR) Game304Lib.lpr

test: build/guigraal-test
	./build/guigraal-test

clean:
	rm -rf build
