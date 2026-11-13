#include "walk.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace Quattro::World {

namespace {

bool u32be(std::string_view d, size_t& at, uint32_t& v) {
  if (at + 4 > d.size()) return false;
  v = (uint32_t(uint8_t(d[at])) << 24) | (uint32_t(uint8_t(d[at + 1])) << 16) | (uint32_t(uint8_t(d[at + 2])) << 8) |
      uint32_t(uint8_t(d[at + 3]));
  at += 4;
  return true;
}

// Reads one array (flat or nested). Flat values go to `out` when given.
bool read_array(std::string_view d, size_t& at, std::bitset<4096>* out, int depth) {
  uint32_t h = 0;
  if (depth > 8 || !u32be(d, at, h)) return false;
  uint32_t n = h & 0xFFFF;
  bool nested = (h >> 16) != 0;
  for (uint32_t i = 0; i < n; ++i) {
    if (nested) {
      if (!read_array(d, at, nullptr, depth + 1)) return false;
    } else {
      uint32_t v = 0;
      if (!u32be(d, at, v)) return false;
      if (out && v < 4096) out->set(v);
    }
  }
  return true;
}

// The six probe points of a facing, as offsets from the sprite's top-left:
// a fixed offset on the leading edge and six across it.
struct Probe {
  bool horizontal_edge;  // up and down: the edge runs along x
  double edge;
  std::array<double, 6> across;
};

constexpr std::array<double, 6> kAcrossX = {0.525, 1.475, 1.525, 2.475, 2.525, 0.475};
constexpr std::array<double, 6> kAcrossY = {1.025, 1.975, 2.025, 2.975, 3.025, 0.975};
const Probe kProbes[4] = {
    {true, 1.0, kAcrossX},   // up
    {false, 0.5, kAcrossY},  // left
    {true, 3.0, kAcrossX},   // down
    {false, 2.5, kAcrossY},  // right
};
constexpr double kDx[4] = {0, -0.5, 0, 0.5};
constexpr double kDy[4] = {-0.5, 0, 0.5, 0};

}  // namespace

bool read_arrays_dat(std::string_view data, TileTypes& out, std::string& error) {
  TileTypes t;
  size_t at = 0;
  int index = 0;
  while (at < data.size()) {
    std::bitset<4096>* target = index == 0 ? &t.passable : index == 1 ? &t.liquid : nullptr;
    if (!read_array(data, at, target, 0)) {
      error = "arrays.dat: array " + std::to_string(index) + " ends early";
      return false;
    }
    ++index;
  }
  if (index < 2) {
    error = "arrays.dat: fewer than two arrays";
    return false;
  }
  t.loaded = true;
  out = t;
  return true;
}

bool point_blocked(const Files::Level& level, const TileTypes& types, double x, double y) {
  for (const auto& c : level.chests) {
    if (x >= c.x && x <= c.x + 2 && y >= c.y && y <= c.y + 2) return true;
  }
  int tx = static_cast<int>(std::floor(x)), ty = static_cast<int>(std::floor(y));
  if (tx < 0 || ty < 0 || tx >= Files::kBoardSide || ty >= Files::kBoardSide) return false;
  if (level.layers.empty()) return false;
  return types.blocks(level.tile(tx, ty));
}

bool step(Player& p, int dir, const Files::Level& level, const TileTypes& types) {
  if (dir < 0 || dir > 3) return false;
  p.dir = dir;
  const Probe& pr = kProbes[dir];
  double nx = p.x + kDx[dir], ny = p.y + kDy[dir];
  std::array<bool, 6> blocked{};
  for (size_t i = 0; i < 6; ++i) {
    double px = pr.horizontal_edge ? nx + pr.across[i] : nx + pr.edge;
    double py = pr.horizontal_edge ? ny + pr.edge : ny + pr.across[i];
    blocked[i] = point_blocked(level, types, px, py);
  }
  if (!blocked[0] && !blocked[1] && !blocked[2] && !blocked[3]) {
    p.x = nx;
    p.y = ny;
    return true;
  }
  // Refused: a 0.1 nudge across the edge so a corner does not catch.
  double nudge = 0;
  if (blocked[0] && !blocked[2] && !blocked[3] && !blocked[4]) nudge = 0.1;
  else if (!blocked[0] && !blocked[1] && blocked[3] && !blocked[5]) nudge = -0.1;
  if (pr.horizontal_edge) p.x += nudge;
  else p.y += nudge;
  return false;
}

std::string Walker::tick(Player& p, unsigned keys, const Files::Level& level, const TileTypes& types) {
  if ((keys & 0xF) == 0) {
    blocked_ticks_ = 0;
    if (p.gani == "walk" || p.gani == "push") p.gani = "idle";
    return {};
  }
  bool refused = false;
  for (int dir = 0; dir < 4; ++dir) {
    if (keys & (1u << dir)) refused |= !step(p, dir, level, types);
  }
  if (clamp) {
    p.x = std::max(0.0, std::min(p.x, Files::kBoardSide - 2.0));
    p.y = std::max(0.0, std::min(p.y, Files::kBoardSide - 2.0));
  }
  blocked_ticks_ = refused ? blocked_ticks_ + 1 : 0;
  p.gani = pushing() ? "push" : "walk";
  if (!pushing()) return {};
  int t = blocked_ticks_ - kPushAfter;
  if (t == kFirstPushed || (t > kFirstPushed && (t - kFirstPushed) % kPushedEvery == 0)) return "pushed,0";
  return {};
}

}  // namespace Quattro::World
