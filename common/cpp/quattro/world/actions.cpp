#include "actions.hpp"

#include "../net/gtypes.hpp"

#include <cmath>
#include <cstdint>
#include <algorithm>

namespace Quattro::World {

namespace {

using Net::gchar;
using Net::gint3;
using Net::gshort;
using Net::gstring;

// 2.05 rev 2 lay order (4.04r2 Adventure.pas). Entries CanLay rejects are skipped.
constexpr int kLayOrder[] = {0, 1, 2, 19, 3, 4, 5, 6, 16, 8, 12, 23, 7, 20, 21, 22, 9, 15, 17, 10, 13, 18, 14, 24};
constexpr double kLayDX[4] = {0, -2, 0, 2};
constexpr double kLayDY[4] = {-3, 0, 2, 0};

bool can_lay(const Player& p, int item) {
  switch (item) {
    case 0: return p.rupees >= 1;
    case 1: return p.rupees >= 5;
    case 2: return p.rupees >= 30;
    case 19: return p.rupees >= 100;
    case 3: return p.bombs >= 5;
    case 4: return p.arrows >= 5;
    case 5: return p.power >= 3;
    case 6: return p.glove_power == 2;
    case 16: return p.glove_power == 3;
    case 10: return p.sword_power == 1;
    case 13: return p.sword_power == 2;
    case 18: return p.sword_power == 3;
    case 14: return p.sword_power == 4;
    case 9: return p.shield_power == 1;
    case 15: return p.shield_power == 2;
    case 17: return p.shield_power == 3;
    case 24: return (p.status & ItemKeys::kStatusHasSpin) != 0;
    default: return false;
  }
}

bool floor_item(int item) {
  return (item >= 0 && item <= 5) || item == 7 || item == 8 || item == 19 || item == 24;
}

int next_layable(const Player& p, int after) {
  const int n = static_cast<int>(sizeof(kLayOrder) / sizeof(kLayOrder[0]));
  int start = 0;
  for (int i = 0; i < n; ++i)
    if (kLayOrder[i] == after) start = i + 1;
  for (int i = 0; i < n; ++i) {
    int item = kLayOrder[(start + i) % n];
    if (can_lay(p, item)) return item;
  }
  return -1;
}

std::vector<Packet> take_lay_cost(Player& p, int item) {
  std::string prop;
  switch (item) {
    case 0:
      p.rupees -= 1;
      prop = gchar(kRupees) + gint3(static_cast<uint32_t>(p.rupees));
      break;
    case 1:
      p.rupees -= 5;
      prop = gchar(kRupees) + gint3(static_cast<uint32_t>(p.rupees));
      break;
    case 2:
      p.rupees -= 30;
      prop = gchar(kRupees) + gint3(static_cast<uint32_t>(p.rupees));
      break;
    case 19:
      p.rupees -= 100;
      prop = gchar(kRupees) + gint3(static_cast<uint32_t>(p.rupees));
      break;
    case 3:
      p.bombs -= 5;
      prop = gchar(kBombs) + gchar(static_cast<unsigned>(p.bombs));
      break;
    case 4:
      p.arrows -= 5;
      prop = gchar(kArrows) + gchar(static_cast<unsigned>(p.arrows));
      break;
    case 5:
      p.power -= 2;
      prop = gchar(kCurPower) + gchar(static_cast<unsigned>(p.power));
      break;
    case 6:
    case 16:
      --p.glove_power;
      prop = gchar(kGlovePower) + gchar(static_cast<unsigned>(p.glove_power));
      break;
    case 10:
    case 13:
    case 18:
    case 14:
      --p.sword_power;
      prop = gchar(kSwordPower) + gchar(static_cast<unsigned>(p.sword_power));
      break;
    case 9:
    case 15:
    case 17:
      --p.shield_power;
      prop = gchar(kShieldPower) + gchar(static_cast<unsigned>(p.shield_power));
      break;
    default:
      p.status &= ~ItemKeys::kStatusHasSpin;
      prop = gchar(kStatus) + gchar(static_cast<unsigned>(p.status));
      break;
  }
  return {{2, prop}};
}

struct Node {
  std::vector<int> values;
  std::vector<Node> items;
};

bool u32be(std::string_view d, size_t& at, uint32_t& v) {
  if (at + 4 > d.size()) return false;
  v = (uint32_t(uint8_t(d[at])) << 24) | (uint32_t(uint8_t(d[at + 1])) << 16) | (uint32_t(uint8_t(d[at + 2])) << 8) |
      uint32_t(uint8_t(d[at + 3]));
  at += 4;
  return true;
}

bool read_node(std::string_view d, size_t& at, Node& out, int depth) {
  uint32_t h = 0;
  if (depth > 8 || !u32be(d, at, h)) return false;
  uint32_t n = h & 0xFFFF;
  bool nested = (h >> 16) != 0;
  for (uint32_t i = 0; i < n; ++i) {
    if (nested) {
      out.items.emplace_back();
      if (!read_node(d, at, out.items.back(), depth + 1)) return false;
    } else {
      uint32_t v = 0;
      if (!u32be(d, at, v)) return false;
      out.values.push_back(static_cast<int>(v));
    }
  }
  return true;
}

// A list of 2 x 2 objects: object -> column -> row values.
std::vector<Object> objects(const Node& list) {
  std::vector<Object> out;
  for (const auto& o : list.items) {
    Object obj{-1, -1, -1, -1};
    for (size_t c = 0; c < 2 && c < o.items.size(); ++c)
      for (size_t r = 0; r < 2 && r < o.items[c].values.size(); ++r) obj[c * 2 + r] = o.items[c].values[r];
    out.push_back(obj);
  }
  return out;
}

int tile_of(double v) { return static_cast<int>(std::floor(v)); }

std::string prop_gani(const std::string& g) { return gchar(kGani) + gstring(g); }
std::string prop_carry(int sprite) { return gchar(kCarrySprite) + gchar(static_cast<unsigned>(sprite)); }

}  // namespace

bool read_object_tables(std::string_view data, ObjectTables& out) {
  std::vector<Node> lists;
  size_t at = 0;
  while (at < data.size()) {
    lists.emplace_back();
    if (!read_node(data, at, lists.back(), 0)) return false;
  }
  ObjectTables t;
  if (lists.size() > 12) {
    t.cut = objects(lists[9]);
    t.cut_left = objects(lists[10]);
    t.lift = objects(lists[11]);
    t.lift_left = objects(lists[12]);
    t.loaded = true;
  }
  if (lists.size() > 24)
    for (int v : lists[24].values) t.sprites.push_back(static_cast<uint32_t>(v));
  out = t;
  return true;
}

bool sprite_rect(const ObjectTables& t, int i, int& x, int& y, int& w, int& h) {
  x = y = w = h = 0;
  if (i < 0 || i >= static_cast<int>(t.sprites.size())) return false;
  // x: 9 bits, y / 2: 10 bits, w / 2 and h / 2: 6 bits each.
  uint32_t v = t.sprites[static_cast<size_t>(i)];
  h = static_cast<int>(v & 63) * 2;
  w = static_cast<int>((v >> 6) & 63) * 2;
  y = static_cast<int>((v >> 12) & 1023) * 2;
  x = static_cast<int>(v >> 23);
  return w > 0 && h > 0;
}

void probe_point(const Player& p, double& x, double& y) {
  switch (p.dir & 3) {
    case 0: x = p.x + 1.5; y = p.y; break;
    case 1: x = p.x - 0.5; y = p.y + 2; break;
    case 2: x = p.x + 1.5; y = p.y + 4; break;
    default: x = p.x + 3.5; y = p.y + 2; break;
  }
}

int match_object(const Files::Level& level, const std::vector<Object>& list, int max_count, double x, double y,
                 int& ox, int& oy) {
  ox = oy = 0;
  int tx = tile_of(x), ty = tile_of(y);
  if (level.layers.empty() || tx < 0 || ty < 0 || tx >= Files::kBoardSide || ty >= Files::kBoardSide) return -1;
  int t = level.tile(tx, ty);
  int n = std::min(max_count, static_cast<int>(list.size()));
  for (int e = 0; e < n; ++e) {
    const Object& o = list[static_cast<size_t>(e)];
    for (int c = 0; c < 2; ++c)
      for (int r = 0; r < 2; ++r) {
        if (object_tile(o, c, r) != t) continue;
        int cx = tx - c, cy = ty - r;
        bool ok = cx >= 0 && cy >= 0 && cx + 1 < Files::kBoardSide && cy + 1 < Files::kBoardSide;
        for (int c2 = 0; ok && c2 < 2; ++c2)
          for (int r2 = 0; ok && r2 < 2; ++r2)
            if (level.tile(cx + c2, cy + r2) != object_tile(o, c2, r2)) ok = false;
        if (ok) {
          ox = cx;
          oy = cy;
          return e;
        }
      }
  }
  return -1;
}

std::string board_modify(int x, int y, int w, int h, const std::vector<int>& tiles) {
  std::string s = gchar(static_cast<unsigned>(x)) + gchar(static_cast<unsigned>(y)) + gchar(static_cast<unsigned>(w)) +
                  gchar(static_cast<unsigned>(h));
  for (int t : tiles) s += gshort(static_cast<unsigned>(t));
  return s;
}

std::string put_object(Files::Level& level, int x, int y, const Object& o) {
  if (level.layers.empty()) return {};
  std::vector<int> tiles;
  bool changed = false;
  for (int r = 0; r < 2; ++r)
    for (int c = 0; c < 2; ++c) {
      int t = object_tile(o, c, r);
      if (t < 0 || x + c < 0 || y + r < 0 || x + c >= Files::kBoardSide || y + r >= Files::kBoardSide) return {};
      auto& cell = level.layers[0][static_cast<size_t>(x + c + (y + r) * Files::kBoardSide)];
      if (cell != t) changed = true;
      cell = static_cast<uint16_t>(t);
      tiles.push_back(t);
    }
  return changed ? board_modify(x, y, 2, 2, tiles) : std::string();
}

std::vector<Packet> ItemKeys::tick(Player& p, unsigned keys, unsigned arrows, Files::Level& level,
                                   const ObjectTables& tables, const TileTypes& types) {
  std::vector<Packet> out;
  unsigned pressed = keys & ~last_keys_;
  last_keys_ = keys;
  ++ticks_;

  // S again during the swing with the has-spin STATUS bit: cut off the
  // swing and play spin (2.05/2.22; 4.04r2 Adventure.Attack). Checked
  // before the sword times out so a press on the last swing tick still spins.
  if ((pressed & kKeyS) && mode_ == Mode::Sword && (p.status & kStatusHasSpin) != 0) {
    mode_ = Mode::Spin;
    ticks_ = 0;
    p.gani = "spin";
    out.push_back({2, prop_gani(p.gani) + gchar(kSprite) + gchar(static_cast<unsigned>(p.dir & 3))});
    return out;
  }

  // Timed steps of the current mode.
  if (mode_ == Mode::Sword && ticks_ >= kSwordTicks) {
    mode_ = Mode::Free;
    p.gani = "idle";
    out.push_back({2, prop_gani(p.gani)});
  } else if (mode_ == Mode::Spin && ticks_ >= kSpinTicks) {
    mode_ = Mode::Free;
    p.gani = "idle";
    out.push_back({2, prop_gani(p.gani)});
  } else if (mode_ == Mode::Lift) {
    if (ticks_ == sprite_after_ && carry_kind_ >= 0 && carry_kind_ < 3) {
      p.carry_sprite = ItemKeys::kLiftSprites[carry_kind_];
      out.push_back({2, prop_carry(p.carry_sprite)});
    }
    if (ticks_ >= still_after_) {
      mode_ = Mode::Carry;
      p.gani = "carrystill";
      out.push_back({2, prop_gani(p.gani)});
    }
  }

  // Lay mode: an arrow, D or S leaves without laying; A with S held picks
  // the next item; A alone lays it (4.04r2 Adventure.PlayerTick / Action).
  if (mode_ == Mode::Lay) {
    if ((arrows & 0xF) != 0 || (pressed & (kKeyD | kKeyS)) != 0) {
      mode_ = Mode::Free;
      lay_item_ = -1;
      return out;
    }
    if (pressed & kKeyA) {
      if (keys & kKeyS) {
        lay_item_ = next_layable(p, lay_item_);
        if (lay_item_ < 0) mode_ = Mode::Free;
        return out;
      }
      const int item = lay_item_;
      mode_ = Mode::Free;
      lay_item_ = -1;
      if (item < 0 || !can_lay(p, item)) return out;
      const int d = p.dir & 3;
      const double x = p.x + 0.5 + kLayDX[d];
      const double y = p.y + 1 + kLayDY[d];
      if (floor_item(item)) {
        const unsigned ix = static_cast<unsigned>(std::lround(x * 2));
        const unsigned iy = static_cast<unsigned>(std::lround(y * 2));
        out.push_back({12, gchar(ix) + gchar(iy) + gchar(static_cast<unsigned>(item))});
      }
      auto cost = take_lay_cost(p, item);
      out.insert(out.end(), cost.begin(), cost.end());
      return out;
    }
    return out;
  }

  if (pressed & kKeyD) {
    p.status ^= 1;
    out.push_back({2, gchar(kStatus) + gchar(static_cast<unsigned>(p.status))});
  }

  if (pressed & kKeyS) {
    if (mode_ == Mode::Spin) return out;  // S during the spin is ignored
    if (mode_ == Mode::Free && p.sword_power > 0) {
      mode_ = Mode::Sword;
      ticks_ = 0;
      p.gani = "sword";
      double x, y;
      probe_point(p, x, y);
      int ox, oy;
      int e = match_object(level, tables.cut, static_cast<int>(tables.cut.size()), x, y, ox, oy);
      std::string board;
      if (e >= 0 && e < static_cast<int>(tables.cut_left.size()))
        board = put_object(level, ox, oy, tables.cut_left[static_cast<size_t>(e)]);
      out.push_back({2, prop_gani(p.gani) + gchar(kSprite) + gchar(static_cast<unsigned>(p.dir & 3))});
      if (!board.empty()) out.push_back({1, board});
      return out;
    }
  }

  if (pressed & kKeyA) {
    if (mode_ == Mode::Carry) {
      mode_ = Mode::Free;
      carry_kind_ = -1;
      p.gani = "idle";
      p.carry_sprite = -1;
      out.push_back({11, ""});
      out.push_back({2, prop_gani(p.gani) + prop_carry(-1)});
      return out;
    }
    if (mode_ != Mode::Free) return out;
    double x, y;
    probe_point(p, x, y);
    int ox, oy;
    int e = match_object(level, tables.lift, p.glove_power + 2, x, y, ox, oy);
    if (e >= 0 && e < static_cast<int>(tables.lift_left.size())) {
      std::string board = put_object(level, ox, oy, tables.lift_left[static_cast<size_t>(e)]);
      mode_ = Mode::Lift;
      ticks_ = 0;
      carry_kind_ = e;
      p.gani = "lift";
      p.carry_sprite = -1;
      if (!board.empty()) out.push_back({1, board});
      out.push_back({2, prop_gani(p.gani) + prop_carry(-1)});
      return out;
    }
    // A with S held and a clear tip: enter the lay mode.
    if (keys & kKeyS) {
      if (point_blocked(level, types, x, y)) return out;
      const int item = next_layable(p, -1);
      if (item < 0) return out;
      mode_ = Mode::Lay;
      lay_item_ = item;
      p.gani = "idle";
      return out;
    }
    if (point_blocked(level, types, x, y)) {
      // Grab; pulling when the arrow away from the facing is held.
      static const unsigned kAway[4] = {4, 8, 1, 2};
      p.gani = (arrows & kAway[p.dir & 3]) ? "pull" : "grab";
      out.push_back({2, prop_gani(p.gani)});
    }
  }
  return out;
}

std::vector<Packet> ItemKeys::touch_chests(const Player& p, unsigned arrows, const Files::Level& level) {
  std::vector<Packet> out;
  if ((arrows & 0xF) == 0) return out;
  double x, y;
  probe_point(p, x, y);
  for (const auto& c : level.chests) {
    if (x < c.x || x > c.x + 2 || y < c.y || y > c.y + 2) continue;
    bool done = false;
    for (const auto& o : opened_) done |= o.first == c.x && o.second == c.y;
    if (done) continue;
    opened_.push_back({c.x, c.y});
    out.push_back({20, gchar(static_cast<unsigned>(c.x)) + gchar(static_cast<unsigned>(c.y))});
  }
  return out;
}

}  // namespace Quattro::World
