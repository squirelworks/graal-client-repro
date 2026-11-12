#include "world.hpp"

#include <algorithm>
#include <cmath>

namespace Quattro::Draw {

const std::vector<std::string>& pass_order() {
  static const std::vector<std::string> order = {"Game_Draw", "Draw_Tiles", "Game_Draw_GetDrawObjects",
                                                 "Game_Draw_Player", "Game_Draw_Texts"};
  return order;
}

View follow(const WorldState& w, int canvas_w, int canvas_h) {
  const double vw = static_cast<double>(canvas_w) / kTile;
  const double vh = static_cast<double>(canvas_h) / kTile;
  View v;
  v.left = std::clamp(w.player.x + 1.5 - vw / 2, 0.0, std::max(0.0, Files::kBoardSide - vw));
  v.top = std::clamp(w.player.y + 2.0 - vh / 2, 0.0, std::max(0.0, Files::kBoardSide - vh));
  return v;
}

Color tile_colour(uint16_t t) {
  // A fixed hash so neighbouring ids look different. Rebuild stand-in.
  uint32_t h = static_cast<uint32_t>(t) * 2654435761u;
  return {static_cast<uint8_t>(64 + (h >> 24) % 128), static_cast<uint8_t>(64 + (h >> 16) % 128),
          static_cast<uint8_t>(64 + (h >> 8) % 128), 255};
}

void WorldRenderer::draw(Canvas& c, const WorldState& w, const View& v,
                         const std::function<void(const std::string&)>& trace) const {
  auto mark = [&](const char* name) {
    if (trace) trace(name);
  };
  mark("Game_Draw");
  c.clear({0, 0, 0, 255});
  mark("Draw_Tiles");
  if (w.have_level && (!w.lobby || w.lobby_tiles)) draw_tiles(c, w, v);
  mark("Game_Draw_GetDrawObjects");
  if (w.have_level) draw_objects(c, w, v);
  mark("Game_Draw_Player");
  if (!w.lobby) draw_player(c, w, v);
  mark("Game_Draw_Texts");
}

void WorldRenderer::draw_tiles(Canvas& c, const WorldState& w, const View& v) const {
  const int x0 = static_cast<int>(std::floor(v.left));
  const int y0 = static_cast<int>(std::floor(v.top));
  const int ox = static_cast<int>(std::lround((v.left - x0) * kTile));
  const int oy = static_cast<int>(std::lround((v.top - y0) * kTile));
  const int cols = c.width() / kTile + 2;
  const int rows = c.height() / kTile + 2;
  for (size_t layer = 0; layer < w.level.layers.size(); ++layer) {
    for (int ty = 0; ty < rows; ++ty) {
      for (int tx = 0; tx < cols; ++tx) {
        int bx = x0 + tx, by = y0 + ty;
        if (bx < 0 || by < 0 || bx >= Files::kBoardSide || by >= Files::kBoardSide) continue;
        uint16_t t = w.level.tile(bx, by, layer);
        // Upper layers leave tile 0 transparent (rebuild reading of the
        // 5.x layers; the note does not say which id is empty).
        if (layer > 0 && t == 0) continue;
        int px = tx * kTile - ox, py = ty * kTile - oy;
        if (sheet_.empty()) {
          c.fill_rect({px, py, kTile, kTile}, tile_colour(t));
        } else {
          int col, row;
          Files::tile_sheet_pos(t, col, row);
          c.blit(sheet_, {col * kTile, row * kTile, kTile, kTile}, px, py);
        }
      }
    }
  }
}

void WorldRenderer::draw_objects(Canvas& c, const WorldState& w, const View& v) const {
  // Chests: a framed 2 x 2 tile box until chest.png is drawn. Stand-in.
  for (const auto& ch : w.level.chests) {
    int px = static_cast<int>(std::lround((ch.x - v.left) * kTile));
    int py = static_cast<int>(std::lround((ch.y - v.top) * kTile));
    c.fill_rect({px, py, 2 * kTile, 2 * kTile}, {150, 90, 30, 255});
    c.frame_rect({px, py, 2 * kTile, 2 * kTile}, {250, 210, 80, 255});
  }
  if (w.lobby) return;
  for (const auto& o : w.others) {
    int px = static_cast<int>(std::lround((o.x - v.left) * kTile));
    int py = static_cast<int>(std::lround((o.y - v.top) * kTile));
    c.fill_rect({px + 8, py + 8, 32, 40}, {80, 120, 230, 255});
  }
}

void WorldRenderer::draw_player(Canvas& c, const WorldState& w, const View& v) const {
  // The player as a 3 x 3 tile box until ganis are drawn. Stand-in.
  int px = static_cast<int>(std::lround((w.player.x - v.left) * kTile));
  int py = static_cast<int>(std::lround((w.player.y - v.top) * kTile));
  c.fill_rect({px + 8, py + 8, 32, 40}, {230, 60, 60, 255});
  c.frame_rect({px + 8, py + 8, 32, 40}, {255, 255, 255, 255});
}

}  // namespace Quattro::Draw
