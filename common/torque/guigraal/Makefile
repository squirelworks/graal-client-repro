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
GAME_SRC_3153 = ../../../graal-3.153-G3D28015/src
LIB_DIR = build/lib

.PHONY: all test lib clean
all: build/guigraal-test build/frame-test build/tq-play build/graal304-torque

build:
	mkdir -p build

build/guigraal-test: $(CONTROL) $(ENGINE) $(COMPILER) $(HEADERS) tests/guigraal_test.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) $(ENGINE) $(COMPILER) tests/guigraal_test.cpp -o $@

HOST = host/boot304.cpp pascal_game304.cpp
HOST_HEADERS = host/boot304.hpp

build/tq-play: $(CONTROL) $(HOST) $(ENGINE) $(COMPILER) $(HEADERS) $(HOST_HEADERS) host/tq_play.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) $(HOST) $(ENGINE) $(COMPILER) host/tq_play.cpp -o $@ -ldl

# The windowed 3.04 program: the canvas renderer, mouse and an X11 window.
GUI_DIR = ../gui
GUI = $(GUI_DIR)/image.cpp $(GUI_DIR)/gft.cpp $(GUI_DIR)/bitmap_array.cpp $(GUI_DIR)/canvas.cpp \
  $(GUI_DIR)/profile.cpp $(GUI_DIR)/render.cpp $(GUI_DIR)/mouse.cpp
GUI_HEADERS = $(GUI_DIR)/render.hpp $(GUI_DIR)/mouse.hpp $(GUI_DIR)/canvas.hpp host/window.hpp host/frame304.hpp

build/graal304-torque: $(CONTROL) $(HOST) $(GUI) $(ENGINE) $(COMPILER) $(HEADERS) $(HOST_HEADERS) $(GUI_HEADERS) \
    host/frame304.cpp host/window_x11.cpp host/graal304_torque.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) $(HOST) $(GUI) $(ENGINE) $(COMPILER) host/frame304.cpp host/window_x11.cpp \
	  host/graal304_torque.cpp -o $@ -ldl -lz -lX11

# The frame logic without a window, for tests.
build/frame-test: $(CONTROL) $(GUI) $(ENGINE) $(COMPILER) $(HEADERS) $(GUI_HEADERS) host/frame304.cpp \
    tests/frame_test.cpp | build
	$(CXX) $(CXXFLAGS) $(CONTROL) $(GUI) $(ENGINE) $(COMPILER) host/frame304.cpp tests/frame_test.cpp -o $@ -lz

lib: | build
	mkdir -p $(LIB_DIR)
	cd $(GAME_SRC) && $(FPC) -Mdelphi -Sh -vew -O2 -Fu../../common -Fu. \
	  -FE$(CURDIR)/$(LIB_DIR) -FU$(CURDIR)/$(LIB_DIR) Game304Lib.lpr
	mkdir -p $(LIB_DIR)/units3153
	cd $(GAME_SRC_3153) && $(FPC) -Mdelphi -Sh -vew -O2 -Fu../../common -Fu. \
	  -FE$(CURDIR)/$(LIB_DIR) -FU$(CURDIR)/$(LIB_DIR)/units3153 Game3153Lib.lpr

test: build/guigraal-test build/frame-test
	./build/guigraal-test
	./build/frame-test

clean:
	rm -rf build
