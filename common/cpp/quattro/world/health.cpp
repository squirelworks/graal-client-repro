#include "health.hpp"

#include "walk.hpp"

#include <algorithm>
#include <cmath>

namespace Quattro::World {

std::vector<Packet> Health::hit(Player& p, double hearts, double kx, double ky, int attacker) {
  if (!hurtable(p)) return {};
  const int full = p.max_power * 2;
  p.power = std::min(p.power, full) - static_cast<int>(std::lround(hearts * 2));
  if (p.power > full) p.power = full;
  double len = std::sqrt(kx * kx + ky * ky);
  if (len < 0.0001) {
    kx_ = 1;
    ky_ = 0;
  } else {
    kx_ = kx / len;
    ky_ = ky / len;
  }
  std::vector<Packet> out;
  if (p.power <= 0) {
    p.power = 0;
    dead_ = true;
    hurt_ = 0;
    p.gani = "dead";
    out.push_back({2, Net::gchar(kCurPower) + Net::gchar(0)});
    if (attacker >= 0) out.push_back({14, Net::gshort(static_cast<unsigned>(attacker))});
    return out;
  }
  hurt_ = kHurtTicks;
  p.gani = "hurt";
  out.push_back({2, Net::gchar(kCurPower) + Net::gchar(static_cast<unsigned>(p.power))});
  return out;
}

std::vector<Packet> Health::on_hurt_player(Player& p, std::string_view body, const std::map<int, Player>& others) {
  Net::Reader r(body);
  int id = static_cast<int>(r.gshort());
  if (!r.ok() || body.size() < 5) return {};
  if (body.size() - 2 >= 6) return {};  // from an NPC
  auto it = others.find(id);
  if (it == others.end()) return {};
  const Player& a = it->second;
  if ((a.x - p.x) * (a.x - p.x) + (a.y - p.y) * (a.y - p.y) > 100) return {};
  double dx = (static_cast<int>(r.gchar()) + 32 - 0x60) / 16.0;
  double dy = (static_cast<int>(r.gchar()) + 32 - 0x60) / 16.0;
  int power = std::clamp(static_cast<int>(r.gchar()), 0, 2);
  if (!r.ok()) return {};
  return hit(p, power / 2.0, dx, dy, id);
}

std::vector<Packet> Health::check_swords(Player& p, const std::map<int, Player>& others) {
  if (!hurtable(p)) return {};
  for (const auto& [id, a] : others) {
    if (a.gone || a.gani != "sword") continue;
    if (!a.level.empty() && !p.level.empty() && a.level != p.level) continue;
    double dx = p.x - a.x, dy = p.y - a.y, ahead = 0, side = 0;
    switch (a.dir & 3) {
      case 0: ahead = -dy; side = dx; break;
      case 1: ahead = -dx; side = dy; break;
      case 2: ahead = dy; side = dx; break;
      default: ahead = dx; side = dy; break;
    }
    if (ahead < 0 || ahead > 4 || std::fabs(side) >= 2) continue;
    auto last = swing_tick_.find(id);
    if (last != swing_tick_.end() && ticks_ - last->second < kSwingGap) continue;
    swing_tick_[id] = ticks_;
    return hit(p, std::clamp(a.sword_power, -20, 20) / 2.0, dx, dy, id);
  }
  return {};
}

void Health::tick(Player& p, const Files::Level& level, const TileTypes& types) {
  ++ticks_;
  if (hurt_ <= 0) return;
  if (kHurtTicks - hurt_ < kKnockTicks) {
    static constexpr double kPx[12] = {0.6, 1.5, 2.4, 0.6, 0.6, 0.6, 0.6, 1.5, 2.4, 2.4, 2.4, 2.4};
    static constexpr double kPy[12] = {1.1, 1.1, 1.1, 1.1, 2.0, 2.9, 2.9, 2.9, 2.9, 1.1, 2.0, 2.9};
    double nx = p.x + kx_, ny = p.y + ky_;
    bool blocked = false;
    for (int i = 0; i < 12 && !blocked; ++i) blocked = point_blocked(level, types, nx + kPx[i], ny + kPy[i]);
    if (!blocked) {
      p.x = nx;
      p.y = ny;
    }
  }
  if (--hurt_ == 0 && p.gani == "hurt") p.gani = "idle";
}

std::vector<Packet> Health::respawn(Player& p, double x, double y, const std::string& level) {
  if (!dead_) return {};
  dead_ = false;
  hurt_ = 0;
  p.power = p.ap < 20 ? 6 : p.ap < 40 ? 10 : p.max_power * 2;
  p.power = std::min(p.power, p.max_power * 2);
  p.x = x;
  p.y = y;
  p.gani = "idle";
  std::vector<Packet> out;
  out.push_back({2, Net::gchar(kCurPower) + Net::gchar(static_cast<unsigned>(std::max(0, p.power)))});
  if (!level.empty())
    out.push_back({0, Net::gchar(static_cast<unsigned>(std::lround(x * 2))) +
                          Net::gchar(static_cast<unsigned>(std::lround(y * 2))) + level});
  return out;
}

}  // namespace Quattro::World
