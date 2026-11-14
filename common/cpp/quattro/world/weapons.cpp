#include "weapons.hpp"

#include "walk.hpp"

#include <algorithm>
#include <cmath>

namespace Quattro::World {

namespace {

int half(double tiles) { return static_cast<int>(std::lround(tiles * 2)); }
double snap_half(double tiles) { return std::round(tiles * 2) / 2; }

}  // namespace

std::string default_weapon_name(int item) {
  switch (item) {
    case 7: return "Bow";
    case 8: return "Bomb";
    case 12: return "Superbomb";
    case 20: return "Fireball";
    case 21: return "Fireblast";
    case 22: return "Nukeshot";
    case 23: return "Joltbomb";
    default: return {};
  }
}

std::string default_weapon_image(int item) {
  switch (item) {
    case 7: return "wbowi1.png";
    case 8: return "wbomb1.png";
    case 12: return "wbomb2.png";
    case 20: return "wbowi2.png";
    case 21: return "wbowi3.png";
    case 22: return "wbowi4.png";
    case 23: return "wbomb3.png";
    default: return {};
  }
}

bool WeaponList::add(const std::string& name, const std::string& image, int item) {
  for (const auto& w : list_)
    if (w.name == name) return false;
  list_.push_back({name, image, item});
  select(static_cast<int>(list_.size()) - 1);
  return true;
}

bool WeaponList::add_default(int item) {
  std::string name = default_weapon_name(item);
  if (name.empty()) return false;
  return add(name, default_weapon_image(item), item);
}

void WeaponList::remove(const std::string& name) {
  for (size_t i = 0; i < list_.size(); ++i)
    if (list_[i].name == name) {
      list_.erase(list_.begin() + static_cast<std::ptrdiff_t>(i));
      if (selected_ >= static_cast<int>(list_.size())) selected_ = static_cast<int>(list_.size()) - 1;
      return;
    }
}

void WeaponList::select(int i) {
  const int n = static_cast<int>(list_.size());
  if (n == 0) {
    selected_ = -1;
    return;
  }
  if (i < 0 || i >= n) i = 0;
  for (int k = 0; k < n; ++k) {
    int j = (i + k) % n;
    if (!hidden_weapon(list_[static_cast<size_t>(j)].name)) {
      selected_ = j;
      return;
    }
  }
  selected_ = i;
}

bool WeaponList::any_shown() const {
  return std::any_of(list_.begin(), list_.end(), [](const Weapon& w) { return !hidden_weapon(w.name); });
}

// ------------------------------------------------------------------ combat

std::vector<Packet> Combat::put_bomb(int power, double x, double y) {
  power = std::clamp(power, 1, 3);
  Bomb b;
  b.x = snap_half(x);
  b.y = snap_half(y);
  b.power = power;
  b.fuse = kFuse;
  b.mine = true;
  bombs_.push_back(b);
  return {{4, Net::gchar(static_cast<unsigned>(half(b.x))) + Net::gchar(static_cast<unsigned>(half(b.y))) +
                  Net::gchar(static_cast<unsigned>(power + 8)) + Net::gchar(kFuse)}};
}

std::vector<Packet> Combat::lay_bomb(Player& p, int power) {
  static constexpr double kDx[4] = {0, -1.5, 0, 1.5}, kDy[4] = {-1.5, 0, 1.5, 0};
  if (p.bombs <= 0) return {};
  --p.bombs;
  int d = p.dir & 3;
  return put_bomb(power, p.x + 0.5 + kDx[d], p.y + 1 + kDy[d]);
}

std::vector<Packet> Combat::shoot_from(double x, double y, int dir, int kind) {
  Shot s;
  s.x = x;
  s.y = y;
  s.dir = dir & 3;
  s.sprite = kArrowSprite + s.dir;
  s.kind = std::clamp(kind, 0, 3);
  s.mine = true;
  shots_.push_back(s);
  return {{9, Net::gchar(static_cast<unsigned>(half(s.x))) + Net::gchar(static_cast<unsigned>(half(s.y))) +
                  Net::gchar(static_cast<unsigned>(s.dir + 8)) + Net::gchar(static_cast<unsigned>(s.sprite)) +
                  Net::gchar(static_cast<unsigned>(s.kind + 1))}};
}

std::vector<Packet> Combat::shoot(Player& p, int kind) {
  // Just ahead of the body's middle, by facing.
  static constexpr double kSx[4] = {1.25, -0.5, 1.25, 2.5}, kSy[4] = {0, 1.75, 2.5, 1.75};
  if (kind == 0) {
    if (p.arrows <= 0) return {};
    --p.arrows;
  }
  int d = p.dir & 3;
  return shoot_from(p.x + kSx[d], p.y + kSy[d], d, kind);
}

bool Combat::on_message(int id, std::string_view body) {
  Net::Reader r(body);
  switch (id) {
    case 11: {  // BOMBADD: s player, x*2, y*2, power, fuse
      r.gshort();
      Bomb b;
      b.x = r.gchar() / 2.0;
      b.y = r.gchar() / 2.0;
      b.power = std::clamp(static_cast<int>(r.gchar() & 7), 1, 3);
      b.fuse = std::max(1, static_cast<int>(r.gchar()));
      if (r.ok()) bombs_.push_back(b);
      return true;
    }
    case 12: {  // BOMBDEL: x*2, y*2 (no player)
      double x = r.gchar() / 2.0, y = r.gchar() / 2.0;
      if (r.ok())
        bombs_.erase(std::remove_if(bombs_.begin(), bombs_.end(),
                                    [&](const Bomb& b) { return !b.mine && b.x == x && b.y == y; }),
                     bombs_.end());
      return true;
    }
    case 19: {  // ARROWADD: s player, x*2, y*2, flags, sprite, kind + 33
      r.gshort();
      Shot s;
      s.x = r.gchar() / 2.0;
      s.y = r.gchar() / 2.0;
      unsigned flags = r.gchar();
      s.dir = static_cast<int>(flags & 3);
      s.sprite = static_cast<int>(r.gchar());
      s.kind = std::clamp(static_cast<int>(r.gchar()) - 1, 0, 3);
      if (!r.ok()) return true;
      if (flags & 4)  // first removes a matching shot (a shield sent it back)
        shots_.erase(std::remove_if(shots_.begin(), shots_.end(),
                                    [&](const Shot& o) { return !o.mine && std::fabs(o.x - s.x) < 1.5 && std::fabs(o.y - s.y) < 1.5; }),
                     shots_.end());
      shots_.push_back(s);
      return true;
    }
    case 36: {  // EXPLOSION: s player, radius, x*2, y*2, power
      r.gshort();
      int radius = static_cast<int>(r.gchar());
      double x = r.gchar() / 2.0, y = r.gchar() / 2.0;
      int power = std::clamp(static_cast<int>(r.gchar() & 7), 1, 3);
      if (r.ok()) {
        // The other player's bomb there goes with it.
        bombs_.erase(std::remove_if(bombs_.begin(), bombs_.end(),
                                    [&](const Bomb& b) { return !b.mine && b.x == x && b.y == y; }),
                     bombs_.end());
        add_blast(x, y, radius, power, false);
      }
      return true;
    }
    default:
      return false;
  }
}

void Combat::add_blast(double x, double y, int reach, int power, bool mine) {
  Blast b;
  b.x = x;
  b.y = y;
  b.reach = std::clamp(reach, 0, 15);
  b.power = power;
  b.mine = mine;
  blasts_.push_back(b);
}

std::vector<Packet> Combat::tick(Files::Level& level, const ObjectTables& tables, const TileTypes& types) {
  std::vector<Packet> out;
  // Fuses: an own bomb sends its explosion and changes the board.
  for (size_t i = 0; i < bombs_.size();) {
    Bomb& b = bombs_[i];
    if (--b.fuse > 0) {
      ++i;
      continue;
    }
    if (b.mine)
      out.push_back({27, Net::gchar(kBlastReach) + Net::gchar(static_cast<unsigned>(half(b.x))) +
                             Net::gchar(static_cast<unsigned>(half(b.y))) + Net::gchar(static_cast<unsigned>(b.power + 8))});
    add_blast(b.x, b.y, kBlastReach, b.power, b.mine);
    if (b.mine && tables.loaded) {
      // Each piece of the blast: the centre, then `reach` pieces 2 tiles
      // apart each way; four points of each.
      static constexpr int kDx[5] = {0, 0, -1, 0, 1}, kDy[5] = {0, -1, 0, 1, 0};
      for (int d = 0; d < 5; ++d)
        for (int k = (d == 0 ? 0 : 1); k <= (d == 0 ? 0 : kBlastReach); ++k) {
          double px = b.x + kDx[d] * 2 * k, py = b.y + kDy[d] * 2 * k;
          for (int c = 0; c < 4; ++c) {
            double qx = px + 0.5 + (c & 1), qy = py + 0.5 + (c >> 1);
            int ox = 0, oy = 0;
            std::string mod;
            if (match_object(level, tables.cut, 1, qx, qy, ox, oy) == 0 && !tables.cut_left.empty()) {
              mod = put_object(level, ox, oy, tables.cut_left[0]);
            } else {
              int e = match_object(level, tables.lift, 4, qx, qy, ox, oy);
              if (e >= 1 && e < static_cast<int>(tables.lift_left.size()))
                mod = put_object(level, ox, oy, tables.lift_left[static_cast<size_t>(e)]);
            }
            if (!mod.empty()) out.push_back({1, mod});
          }
        }
    }
    bombs_.erase(bombs_.begin() + static_cast<std::ptrdiff_t>(i));
  }
  // Blasts show for 11 ticks.
  for (auto& b : blasts_) ++b.age;
  blasts_.erase(std::remove_if(blasts_.begin(), blasts_.end(), [](const Blast& b) { return b.age > kBlastTicks; }),
                blasts_.end());
  // Shots: one tile a tick; a wall or the level's edge stops them.
  static constexpr int kDx[4] = {0, -1, 0, 1}, kDy[4] = {-1, 0, 1, 0};
  for (size_t i = 0; i < shots_.size();) {
    Shot& s = shots_[i];
    s.x += kDx[s.dir];
    s.y += kDy[s.dir];
    double w = 0.5, h = 0.5;
    int sx = 0, sy = 0, sw = 0, sh = 0;
    if (sprite_rect(tables, s.sprite, sx, sy, sw, sh)) {
      w = sw / 16.0;
      h = sh / 16.0;
    }
    bool gone = s.x < -2 || s.y < -2 || s.x >= Files::kBoardSide || s.y >= Files::kBoardSide;
    bool hit = !gone && point_blocked(level, types, s.x + w / 2, s.y + h / 2);
    // A fireblast or a nuke leaves a blast where it stops.
    if (hit && s.kind >= 2) add_blast(s.x - 0.5, s.y - 0.5, kBlastReach, 1, s.mine);
    if (gone || hit) {
      shots_.erase(shots_.begin() + static_cast<std::ptrdiff_t>(i));
      continue;
    }
    ++i;
  }
  return out;
}

std::vector<Combat::Hit> Combat::hits_on(const Player& me, const ObjectTables& tables, std::vector<Packet>& out) {
  std::vector<Hit> hits;
  const double cx = me.x + 1.5, cy = me.y + 2;
  static constexpr int kDx[5] = {0, 0, -1, 0, 1}, kDy[5] = {0, -1, 0, 1, 0};
  for (const auto& b : blasts_)
    for (int d = 0; d < 5; ++d)
      for (int k = (d == 0 ? 0 : 1); k <= (d == 0 ? 0 : b.reach); ++k) {
        double px = b.x + kDx[d] * 2 * k + 1, py = b.y + kDy[d] * 2 * k + 1;
        if (std::fabs(px - cx) < 1 && std::fabs(py - cy) < 1) hits.push_back({b.power == 3 ? 1.0 : 0.5, double(kDx[d]), double(kDy[d])});
      }
  static constexpr int kSx[4] = {0, -1, 0, 1}, kSy[4] = {-1, 0, 1, 0};
  for (size_t i = 0; i < shots_.size();) {
    Shot& s = shots_[i];
    double w = 0.5, h = 0.5;
    int sx = 0, sy = 0, sw = 0, sh = 0;
    if (sprite_rect(tables, s.sprite, sx, sy, sw, sh)) {
      w = sw / 16.0;
      h = sh / 16.0;
    }
    bool over = s.x + w > me.x + 0.5 && s.x < me.x + 2.5 && s.y + h > me.y + 1 && s.y < me.y + 3;
    if (s.mine || !over) {
      ++i;
      continue;
    }
    const bool still = me.gani.empty() || me.gani == "idle" || me.gani == "walk";
    if ((me.dir & 3) == (s.dir ^ 2) && me.shield_power > 0 && s.kind <= 1 && still) {
      if (me.shield_power >= 2) {
        s.dir ^= 2;
        if (s.sprite >= kArrowSprite && s.sprite < kArrowSprite + 4) s.sprite = kArrowSprite + s.dir;
        s.mine = true;
        out.push_back({9, Net::gchar(static_cast<unsigned>(half(s.x))) + Net::gchar(static_cast<unsigned>(half(s.y))) +
                              Net::gchar(static_cast<unsigned>(s.dir + 4 + 8)) + Net::gchar(static_cast<unsigned>(s.sprite)) +
                              Net::gchar(static_cast<unsigned>(s.kind + 1))});
        ++i;
      } else {
        shots_.erase(shots_.begin() + static_cast<std::ptrdiff_t>(i));
      }
      continue;
    }
    hits.push_back({(s.kind == 1 || s.kind == 3) ? 1.0 : 0.5, double(kSx[s.dir]), double(kSy[s.dir])});
    shots_.erase(shots_.begin() + static_cast<std::ptrdiff_t>(i));
  }
  return hits;
}

}  // namespace Quattro::World
