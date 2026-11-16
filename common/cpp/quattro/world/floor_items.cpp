#include "floor_items.hpp"

#include "../net/gtypes.hpp"

#include <algorithm>
#include <cmath>

namespace Quattro::World {

namespace {
using Net::gchar;

constexpr double kBounceSpan = 7.0 * 3.14159265358979323846;  // 7 * Pi

}  // namespace

void FloorItems::add(double x, double y, int item, int life) {
  FloorItem it;
  it.x = x;
  it.y = y;
  it.item = item;
  it.life = life;
  it.permanent = life < 100;
  items_.push_back(it);
}

void FloorItems::remove_at(double x, double y) {
  items_.erase(std::remove_if(items_.begin(), items_.end(),
                              [&](const FloorItem& it) { return it.x == x && it.y == y; }),
               items_.end());
}

void FloorItems::give_item(Player& p, int item) {
  auto rupees = [&](int n) { p.rupees = std::min(p.rupees + n, 9999999); };
  switch (item) {
    case 0: rupees(1); break;
    case 1: rupees(5); break;
    case 2: rupees(30); break;
    case 19: rupees(100); break;
    case 3: p.bombs = std::min(p.bombs + 5, 99); break;
    case 4: p.arrows = std::min(p.arrows + 5, 99); break;
    case 5: p.power = std::min(p.power + 2, p.max_power * 2); break;
    case 24: p.status |= ItemKeys::kStatusHasSpin; break;
    default: break;
  }
}

std::vector<Packet> FloorItems::tick(Player& p, bool online) {
  std::vector<Packet> out;
  for (size_t i = 0; i < items_.size();) {
    FloorItem& it = items_[i];
    --it.life;
    if (it.life < 0) {
      if (!it.permanent && online) {
        out.push_back({kPlItemDel, gchar(static_cast<unsigned>(std::lround(it.x * 2))) +
                                       gchar(static_cast<unsigned>(std::lround(it.y * 2)))});
      }
      items_.erase(items_.begin() + static_cast<long>(i));
      continue;
    }
    // Grace of four ticks before pickup, then within 2 tiles of centres.
    if (!it.permanent && it.life < kItemLife - 4 &&
        std::abs(p.x + 1.5 - (it.x + 1)) < 2 && std::abs(p.y + 2 - (it.y + 1)) < 2) {
      if (online) {
        out.push_back({kPlItemTake, gchar(static_cast<unsigned>(std::lround(it.x * 2))) +
                                        gchar(static_cast<unsigned>(std::lround(it.y * 2))) +
                                        gchar(static_cast<unsigned>(it.item))});
      } else {
        give_item(p, it.item);
      }
      items_.erase(items_.begin() + static_cast<long>(i));
      continue;
    }
    ++i;
  }
  return out;
}

std::vector<Piece> FloorItems::pieces(SizeFn size, void* ctx) const {
  std::vector<Piece> out;
  for (const auto& it : items_) {
    if (!it.permanent && it.life < 37 && (it.life & 1)) continue;
    int sprite = item_sprite(it.item);
    if (sprite < 0) continue;
    int sw = 16, sh = 28;
    if (size && !size(sprite, sw, sh, ctx)) continue;
    double lift = 0;
    if (it.life >= kItemLife - kBounceSpan) {
      double t = static_cast<double>(it.life) / kItemLife;
      lift = std::abs(std::sin(it.life / 3.0)) * std::pow(t, 16.0) * 3.0;
    }
    // Shadow under the item; item centred on (x+1, y+1 - lift).
    out.push_back({0, static_cast<int>(std::lround((it.x + 0.5) * 16)),
                   static_cast<int>(std::lround((it.y + 1 + sh / 16.0 / 2 - 0.5) * 16))});
    out.push_back({sprite, static_cast<int>(std::lround((it.x + 1) * 16)) - sw / 2,
                   static_cast<int>(std::lround((it.y + 1 - lift) * 16)) - sh / 2});
  }
  return out;
}

}  // namespace Quattro::World
