# Frankenstein 6.037: the Quattro program on the 6.03r7 row (common/cpp/quattro)
# with the 5.12 Graal3D link (common/cpp/graal3dengine) linked in, not loaded.
#   make        build/frankenstein-6037
#   make test   the view, then Login -> 178 to a "3 " server -> UDP login step 6
CXX ?= g++
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror -O2
Q = ../common/cpp/quattro
G = ../common/cpp/graal3dengine
TG = ../common/torque/gui
GS = ../common/cpp/gs2
CPPFLAGS += -I$(G)/src -I../common/cpp/third_party/torque3d
LIBS = -lz -lbz2
OUT ?= build
EXE =
ifeq ($(OS),Windows_NT)
LIBS += -lws2_32 -ladvapi32
WINDOW_LIBS = -luser32 -lgdi32
PLAYER_LDFLAGS = -static -static-libgcc -static-libstdc++
EXE = .exe
else ifeq ($(shell uname -s),Darwin)
X11_DEFS = -DQUATTRO_COCOA
WINDOW_LIBS = -framework Cocoa
COCOA = $(Q)/draw/window_cocoa.mm
else
ifneq ($(wildcard /usr/include/X11/Xlib.h),)
X11_DEFS = -DQUATTRO_X11
X11_LIBS = -lX11
endif
endif

NET = $(Q)/net/gtypes.cpp $(Q)/net/gen5.cpp $(Q)/net/profile.cpp $(Q)/net/socket.cpp $(Q)/net/connection.cpp $(Q)/net/seccrypto.cpp $(Q)/net/seclogin.cpp
CACHE = $(Q)/cache/des.cpp $(Q)/cache/grescr.cpp
TGUI = $(TG)/image.cpp $(TG)/canvas.cpp $(TG)/gft.cpp $(TG)/bitmap_array.cpp
FILES = $(Q)/files/level.cpp $(Q)/files/gani.cpp $(Q)/files/gmap.cpp
DRAW = $(Q)/draw/world.cpp $(Q)/draw/assets.cpp $(Q)/draw/body_colors.cpp $(Q)/draw/hud.cpp $(Q)/draw/ui_font.cpp $(Q)/draw/ui_font_data.cpp $(TGUI)
GS2 = $(GS)/loader.cpp $(GS)/machine.cpp $(GS)/var.cpp $(GS)/startscripts.cpp $(GS)/engine_commands.cpp $(GS)/delivery.cpp $(GS)/gui.cpp $(GS)/gui_draw.cpp $(GS)/emitter.cpp
SHELL_SRC = $(Q)/shell/program.cpp $(Q)/shell/npcs.cpp $(Q)/shell/server_text.cpp $(Q)/world/npcs.cpp $(Q)/shell/weapon_api.cpp $(Q)/shell/scripts.cpp $(Q)/shell/gui_host.cpp $(Q)/world/player.cpp $(Q)/world/walk.cpp $(Q)/world/actions.cpp $(Q)/world/effects.cpp $(Q)/world/floor_items.cpp $(Q)/world/weapons.cpp $(Q)/world/health.cpp $(Q)/world/item_list.cpp $(GS2) $(CACHE)
G3D = $(G)/src/bits.cpp $(G)/src/world.cpp $(G)/src/link.cpp $(G)/src/udp.cpp ../common/cpp/third_party/torque3d/huffman.cpp
# The 5.12 repro's world renderer (common/cpp/graal3dengine/render); its
# stb_image part is built on its own, without -Werror, as third-party code.
RENDER = $(addprefix $(G)/render/,mesh.cpp read_3ds.cpp read_dif.cpp read_dts.cpp read_ft.cpp terrain.cpp texture.cpp raster.cpp resources.cpp scene.cpp motion.cpp draw.cpp)
FRANK = src/net/udp/link3d.cpp src/graal3d5120/view3d.cpp src/host6037/host.cpp
WINDOW = $(Q)/draw/window_x11.cpp $(Q)/draw/window_native.cpp $(COCOA)
CORE = $(NET) $(FILES) $(DRAW) $(SHELL_SRC) $(G3D) $(RENDER) $(FRANK)
HDRS = $(wildcard src/*/*.hpp src/net/udp/*.hpp $(Q)/*/*.hpp $(G)/src/*.hpp $(G)/render/*.hpp $(TG)/*.hpp $(GS)/*.hpp)

.PHONY: all test clean
all: $(OUT)/frankenstein-6037$(EXE)

$(OUT):
	mkdir -p $(OUT)

# One object per source under $(OUT)/obj, by its path with ../ as up/.
obj = $(patsubst %,$(OUT)/obj/%.o,$(subst ../,up/,$(1)))
CORE_OBJ = $(call obj,$(CORE)) $(OUT)/obj/render_stb.o

$(OUT)/obj/render_stb.o: $(G)/render/stb_impl.cpp $(G)/render/texture.hpp
	@mkdir -p $(dir $@)
	$(CXX) -I../common/cpp/third_party/stb -std=c++17 -O2 -w $(filter -m32 -m64 -fsanitize=% -g,$(CXXFLAGS)) -c $< -o $@

$(OUT)/obj/up/%.o: ../% $(HDRS)
	@mkdir -p $(dir $@)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(X11_DEFS) -c $< -o $@

$(OUT)/obj/%.o: % $(HDRS)
	@mkdir -p $(dir $@)
	$(CXX) $(CPPFLAGS) -I$(G)/tests $(CXXFLAGS) $(X11_DEFS) -c $< -o $@

$(OUT)/frankenstein-6037$(EXE): $(CORE_OBJ) $(call obj,$(WINDOW) src/main.cpp) | $(OUT)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(PLAYER_LDFLAGS) $(LIBS) $(X11_LIBS) $(WINDOW_LIBS)

# The test links the X11 window file only for its headless fallback.
$(OUT)/frankenstein-test$(EXE): $(CORE_OBJ) $(call obj,tests/frankenstein_test.cpp) $(OUT)/obj/test-window.o | $(OUT)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LIBS) -pthread

$(OUT)/obj/test-window.o: $(Q)/draw/window_x11.cpp $(HDRS)
	@mkdir -p $(dir $@)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

test: $(OUT)/frankenstein-test$(EXE) $(OUT)/frankenstein-6037$(EXE)
	./$(OUT)/frankenstein-test$(EXE)
	./$(OUT)/frankenstein-6037$(EXE) 2>/dev/null; test $$? -eq 2

clean:
	rm -rf $(OUT)
