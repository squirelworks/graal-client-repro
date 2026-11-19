#include "world.hpp"
#include "ui_font.hpp"

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
  v.left = w.focus ? axis(w.focus_x, vw) : axis(w.player.x + 1.5, vw);
  v.top = w.focus ? axis(w.focus_y, vh) : axis(w.player.y + 1.5, vh);
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
  if (w.have_level) draw_texts(c, w, v);
}

// Chat and NPC messages, centred above what says them, white on a
// one-pixel black outline (rebuild stand-in look: the original's text
// pass is not copied out). Characters are 48 px wide; an image NPC's
// width is its image or image part.
void WorldRenderer::draw_texts(Canvas& c, const WorldState& w, const View& v) const {
  auto say = [&](const std::string& s, int cx, int top) {
    if (s.empty()) return;
    const int x = cx - ui_text_width(s, false) / 2, y = top - kUiLineHeight;
    for (int dx = -1; dx <= 1; ++dx)
      for (int dy = -1; dy <= 1; ++dy)
        if (dx || dy) ui_draw_text(c, x + dx, y + dy, s, {0, 0, 0, 255}, false);
    ui_draw_text(c, x, y, s, {255, 255, 255, 255}, false);
  };
  auto at = [&](double tx, double ty, int& px, int& py) {
    px = static_cast<int>(std::lround((tx - v.left) * kTile));
    py = static_cast<int>(std::lround((ty - v.top) * kTile));
  };
  int px = 0, py = 0;
  for (const auto& n : w.npcs) {
    at(n.x, n.y, px, py);
    if (n.character) {
      if (!w.lobby) say(n.actor.chat, px + 24, py);
      continue;
    }
    int width = n.has_part ? n.part.width : 32;
    if (!n.has_part && assets_ && !n.image.empty())
      if (const Image* img = assets_->image(n.image)) width = img->width;
    say(n.message, px + width / 2, py);
  }
  if (w.lobby || !w.player_chat) return;
  for (const auto& o : w.others) {
    at(o.x, o.y, px, py);
    say(o.chat, px + 24, py);
  }
  if (!w.player_hidden) {
    at(w.player.x, w.player.y, px, py);
    say(w.player.chat, px + 24, py);
  }
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
    if (!w.chest_boxes) break;
    int px = static_cast<int>(std::lround((ch.x - v.left) * kTile));
    int py = static_cast<int>(std::lround((ch.y - v.top) * kTile));
    c.fill_rect({px, py, 2 * kTile, 2 * kTile}, {150, 90, 30, 255});
    c.frame_rect({px, py, 2 * kTile, 2 * kTile}, {250, 210, 80, 255});
  }
  // Server NPCs: image NPCs in the lobby too, characters only outside it.
  for (const auto& n : w.npcs) {
    int px = static_cast<int>(std::lround((n.x - v.left) * kTile));
    int py = static_cast<int>(std::lround((n.y - v.top) * kTile));
    if (n.character) {
      if (!w.lobby) draw_actor(c, n.actor, px, py, {120, 200, 120, 255});
      continue;
    }
    const Image* img = assets_ && !n.image.empty() ? assets_->image(n.image) : nullptr;
    if (!img) continue;
    Rect src = n.has_part ? n.part : Rect{0, 0, img->width, img->height};
    c.blit(*img, src, px, py);
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
  if (!w.player_hidden) draw_actor(c, w.player, px, py, {230, 60, 60, 255});
  if (!assets_) return;
  for (const auto& e : w.effects) {
    const Image* sheet = assets_->image(e.image.empty() ? "sprites.png" : e.image);
    if (!sheet) continue;
    int ex = static_cast<int>(std::lround(e.x - v.left * kTile));
    int ey = static_cast<int>(std::lround(e.y - v.top * kTile));
    c.blit(*sheet, e.src, ex, ey);
  }
}

namespace {
std::string upper(std::string s) {
  for (char& ch : s) ch = static_cast<char>(std::toupper(static_cast<unsigned char>(ch)));
  return s;
}
}  // namespace

// The gani's step for the actor's tick and facing, each part from its
// sheet (as the Pascal clients draw it, common/GAni.pas), the body in the
// player's colours. Prop 10 may be "name,param1,param2,..."; PARAM sheet
// and PARAM1 step parts use those images (Adventure.pas DrawPlayer).
void WorldRenderer::draw_actor(Canvas& c, const Actor& a, int px, int py, Color box) const {
  std::string gani_name = a.gani.empty() ? "idle" : a.gani;
  std::array<std::string, 21> params = a.param;
  if (auto comma = gani_name.find(','); comma != std::string::npos) {
    // Fill empty param slots from the comma list after the gani name.
    std::string rest = gani_name.substr(comma + 1);
    gani_name.resize(comma);
    size_t i = 1;
    while (i < params.size() && !rest.empty()) {
      auto next = rest.find(',');
      std::string one = next == std::string::npos ? rest : rest.substr(0, next);
      if (params[i].empty()) params[i] = one;
      if (next == std::string::npos) break;
      rest = rest.substr(next + 1);
      ++i;
    }
  }
  const Files::Gani* g = nullptr;
  if (assets_) {
    g = assets_->gani(gani_name);
    if (!g) g = assets_->gani("idle");
  }
  if (!g || g->steps.empty()) {
    // No ganis: a box where the body is. Stand-in.
    c.fill_rect({px + 8, py + 8, 32, 40}, box);
    c.frame_rect({px + 8, py + 8, 32, 40}, {255, 255, 255, 255});
    return;
  }
  for (size_t i = 1; i < params.size(); ++i)
    if (params[i].empty()) params[i] = g->default_param[i];
  auto param_file = [&](int n) -> std::string {
    if (n >= 1 && n < static_cast<int>(params.size()) && !params[static_cast<size_t>(n)].empty())
      return params[static_cast<size_t>(n)];
    // Adventure: a SPRITE sheet PARAM1 falls back to the sword picture.
    if (n == 1) return a.sword.empty() ? "sword1.png" : a.sword;
    return {};
  };
  const auto& parts = g->steps[g->step_at(a.ani_tick)].dirs[static_cast<size_t>(a.dir & 3)];
  int head_y = 0;  // the carried object follows the head when no PARAM1 part
  bool has_param1 = false;
  for (const auto& part : parts) {
    // PARAM1 step token: the carried object at this offset (lift/carry).
    if (part.sprite == Files::kParamSprite - 1) {
      has_param1 = true;
      if (a.carry.width > 0) {
        if (const Image* sprites = assets_->image("sprites.png"))
          c.blit(*sprites, a.carry, px + part.x, py + part.y);
      } else if (std::string file = param_file(1); !file.empty()) {
        if (const Image* img = assets_->image(file)) c.blit(*img, px + part.x, py + part.y);
      }
      continue;
    }
    if (part.sprite <= Files::kParamSprite - 2) {
      // PARAMn (n >= 2) step token: the caller's parameter image, whole.
      int n = Files::kParamSprite - part.sprite;
      if (std::string file = param_file(n); !file.empty()) {
        if (const Image* img = assets_->image(file)) c.blit(*img, px + part.x, py + part.y);
      }
      continue;
    }
    const Files::GaniSprite* s = g->sprite(part.sprite);
    if (!s) continue;
    std::string sheet = upper(s->sheet), file;
    if (sheet == "SPRITES") file = "sprites.png";
    else if (sheet == "HEAD") {
      head_y = part.y;
      file = !a.head.empty() ? a.head : !g->default_head.empty() ? g->default_head : "head0.png";
    } else if (sheet == "BODY") file = !a.body.empty() ? a.body : !g->default_body.empty() ? g->default_body : "body.png";
    else if (sheet == "SWORD") file = a.sword.empty() ? "sword1.png" : a.sword;
    else if (sheet == "SHIELD") file = a.shield.empty() ? "shield1.png" : a.shield;
    else if (sheet.compare(0, 4, "ATTR") == 0) {
      int n = std::atoi(sheet.c_str() + 4);
      if (n >= 1 && n <= 30) {
        if (n < static_cast<int>(a.attr.size()) && !a.attr[static_cast<size_t>(n)].empty()) file = a.attr[static_cast<size_t>(n)];
        else file = g->default_attr[static_cast<size_t>(n)];
      }
    } else if (sheet.compare(0, 5, "PARAM") == 0) {
      file = param_file(std::atoi(sheet.c_str() + 5));
    } else {
      file = s->sheet;
    }
    const Image* img = file.empty() ? nullptr : sheet == "BODY" ? assets_->body(file, a.colors) : assets_->image(file);
    if (img) c.blit(*img, {s->x, s->y, s->w, s->h}, px + part.x, py + part.y);
  }
  // Classic lift/carry ganis with no PARAM1 part: carry above the head.
  if (a.carry.width > 0 && !has_param1) {
    const Image* sprites = assets_->image("sprites.png");
    int dy = head_y - 22;
    if (a.lift_tick >= 0 && a.lift_tick < Actor::kLiftTicks) dy = Actor::kLiftY[a.lift_tick];
    if (sprites) c.blit(*sprites, a.carry, px + 8, py + dy);
  }
}

}  // namespace Quattro::Draw
