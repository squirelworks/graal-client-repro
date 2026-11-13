#include "world.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>

namespace Quattro::Draw {

const std::vector<std::string>& pass_order() {
  static const std::vector<std::string> order = {"Game_Draw", "Draw_Tiles", "Game_Draw_GetDrawObjects",
                                                 "Game_Draw_Player", "Game_Draw_Texts"};
  return order;
}

View follow(const WorldState& w, int canvas_w, int canvas_h) {
  const double vw = static_cast<double>(canvas_w) / kTile;
  const double vh = static_cast<double>(canvas_h) / kTile;
  // Clamped to the level while the view fits in it; a view wider (or
  // taller) than the level keeps the player centred, as the real 6.03r7
  // does at 1280 x 1024 (frames lab, 2026-11-13).
  auto axis = [](double centre, double span) {
    double v = centre - span / 2;
    return span > Files::kBoardSide ? v : std::clamp(v, 0.0, Files::kBoardSide - span);
  };
  View v;
  v.left = axis(w.player.x + 1.5, vw);
  v.top = axis(w.player.y + 1.5, vh);
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
  c.fill_rect(c.clip(), {0, 0, 0, 255});  // inside the clip: the playfield may be one control
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
    draw_actor(c, o, px, py, {80, 120, 230, 255});
  }
}

void WorldRenderer::draw_player(Canvas& c, const WorldState& w, const View& v) const {
  int px = static_cast<int>(std::lround((w.player.x - v.left) * kTile));
  int py = static_cast<int>(std::lround((w.player.y - v.top) * kTile));
  draw_actor(c, w.player, px, py, {230, 60, 60, 255});
}

namespace {
std::string upper(std::string s) {
  for (char& ch : s) ch = static_cast<char>(std::toupper(static_cast<unsigned char>(ch)));
  return s;
}
}  // namespace

// The gani's step for the actor's tick and facing, each part from its
// sheet (as the Pascal clients draw it, common/GAni.pas), the body in the
// player's colours.
void WorldRenderer::draw_actor(Canvas& c, const Actor& a, int px, int py, Color box) const {
  const Files::Gani* g = nullptr;
  if (assets_) {
    g = assets_->gani(a.gani.empty() ? "idle" : a.gani);
    if (!g) g = assets_->gani("idle");
  }
  if (!g || g->steps.empty()) {
    // No ganis: a box where the body is. Stand-in.
    c.fill_rect({px + 8, py + 8, 32, 40}, box);
    c.frame_rect({px + 8, py + 8, 32, 40}, {255, 255, 255, 255});
    return;
  }
  const auto& parts = g->steps[g->step_at(a.ani_tick)].dirs[static_cast<size_t>(a.dir & 3)];
  for (const auto& part : parts) {
    const Files::GaniSprite* s = g->sprite(part.sprite);
    if (!s) continue;
    std::string sheet = upper(s->sheet), file;
    if (sheet == "SPRITES") file = "sprites.png";
    else if (sheet == "HEAD") file = !a.head.empty() ? a.head : !g->default_head.empty() ? g->default_head : "head0.png";
    else if (sheet == "BODY") file = !a.body.empty() ? a.body : !g->default_body.empty() ? g->default_body : "body.png";
    else if (sheet == "SWORD") file = a.sword.empty() ? "sword1.png" : a.sword;
    else if (sheet == "SHIELD") file = a.shield.empty() ? "shield1.png" : a.shield;
    else if (sheet.compare(0, 4, "ATTR") == 0) {
      int n = std::atoi(sheet.c_str() + 4);
      if (n >= 1 && n <= 30) {
        if (n < static_cast<int>(a.attr.size()) && !a.attr[static_cast<size_t>(n)].empty()) file = a.attr[static_cast<size_t>(n)];
        else file = g->default_attr[static_cast<size_t>(n)];
      }
    } else if (sheet.compare(0, 5, "PARAM") == 0) {
      continue;  // the caller's parameter images: not drawn yet
    } else {
      file = s->sheet;
    }
    const Image* img = file.empty() ? nullptr : sheet == "BODY" ? assets_->body(file, a.colors) : assets_->image(file);
    if (img) c.blit(*img, {s->x, s->y, s->w, s->h}, px + part.x, py + part.y);
  }
}

}  // namespace Quattro::Draw
