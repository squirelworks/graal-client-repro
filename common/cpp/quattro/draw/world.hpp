// The world passes of the 6.x program, drawn into a software canvas.
//
// The original draws the world in named passes, then the GUI
// (Graal_analysis client-internals/engine-600r2.md, "Drawing"):
// Game_Draw -> Draw_Tiles -> Game_Draw_GetDrawObjects -> Game_Draw_Player
// -> Game_Draw_Texts, then RenderGUI. This file keeps those names as the
// pass order. The original presents through OpenGL; the pixels here are
// the rebuild's own software rasterisation (Torque::Gui::Canvas, shared
// with common/torque/gui), not the original renderer's.
//
// The lobby rule (protocol/v5v6-lab-play.md): while the server's name
// starts with "login", no characters and no HUD are drawn, and 6.03r7 (the
// Linux and Windows release) draws no tiles either, only chests and image
// NPCs.
#pragma once

#include "../files/level.hpp"
#include "../../../torque/gui/canvas.hpp"

#include <functional>
#include <string>
#include <vector>

namespace Quattro::Draw {

using Torque::Gui::Canvas;
using Torque::Gui::Color;
using Torque::Gui::Image;
using Torque::Gui::Rect;

constexpr int kTile = 16;

struct Actor {
  double x = 0, y = 0;  // tiles
  std::string chat;
};

struct WorldState {
  Files::Level level;
  bool have_level = false;
  Actor player;
  std::vector<Actor> others;
  bool lobby = false;        // server name starts with "login"
  bool lobby_tiles = false;  // the build draws tiles in the lobby
};

struct View {
  double left = 0, top = 0;  // tiles at the canvas's top-left
};

// Centres the view on the player, clamped to the level.
View follow(const WorldState& w, int canvas_w, int canvas_h);

// Pass names in the order they run, for tests and the profiler.
const std::vector<std::string>& pass_order();

class WorldRenderer {
 public:
  // `tiles` is the tile sheet (pics1.png, 2048 x 512 in 16-pixel tiles).
  // With no sheet, each tile is a flat colour from its id (rebuild
  // stand-in, so a session can be seen without the player's files).
  void set_tile_sheet(Image sheet) { sheet_ = std::move(sheet); }
  bool has_tile_sheet() const { return !sheet_.empty(); }

  // Runs every pass. `trace`, when set, gets each pass name as it runs.
  void draw(Canvas& c, const WorldState& w, const View& v,
            const std::function<void(const std::string&)>& trace = {}) const;

 private:
  void draw_tiles(Canvas& c, const WorldState& w, const View& v) const;
  void draw_objects(Canvas& c, const WorldState& w, const View& v) const;
  void draw_player(Canvas& c, const WorldState& w, const View& v) const;
  Image sheet_;
};

// The stand-in colour for a tile id with no sheet.
Color tile_colour(uint16_t t);

}  // namespace Quattro::Draw
