#include "effects.hpp"

#include "../net/gtypes.hpp"

namespace Quattro::World {

namespace {

constexpr int kDX[4] = {0, -1, 0, 1};
constexpr int kDY[4] = {-1, 0, 1, 0};

// The sprite of each item number (arrays.dat list 24), as the Pascal
// rebuilds draw floor and chest items; item 0, the green gralat, is the
// lab's (0, 144) 16 x 28.
constexpr int kItemSprites[25] = {136, 137, 138, 67,  143, 139, 145, 351, 65,  350, 314, 315, 321,
                                  323, 322, 324, 325, 328, 329, 330, 331, 332, 333, 334, 349};

constexpr int kShadowSprite = 0;
constexpr int kLeafA = 25, kLeafB = 26;
constexpr int kPotRight = 97, kPotLeft = 99;
constexpr int kSignRight = 100, kSignLeft = 102;  // which side each goes is a rebuild guess

enum BurstKind { kLeaves = 0, kPot = 1, kSign = 2, kCutLeaves = 3 };

}  // namespace

int item_sprite(int item) { return item >= 0 && item < 25 ? kItemSprites[item] : -1; }

void Effects::throw_object(int carry_sprite, int px, int py, int dir) {
  if (carry_sprite < 0) return;
  thrown_.push_back({carry_sprite, px + 8, py - 22, py + 34, dir & 3, 0});
}

void Effects::cut_bush(int tx, int ty) { bursts_.push_back({kCutLeaves, tx * 16, ty * 16, 0}); }

void Effects::chest_item(int item, int cx, int cy) {
  int s = item_sprite(item);
  if (s >= 0) items_.push_back({s, cx, cy - 1, 0});
}

std::vector<Packet> Effects::tick() {
  std::vector<Packet> out;
  // Pieces age first, so a break starts whole on the tick it lands.
  for (size_t i = 0; i < bursts_.size();) {
    Burst& b = bursts_[i];
    int life = b.kind == kCutLeaves ? kLeafTicks : kBreakTicks;
    if (++b.age >= life) bursts_.erase(bursts_.begin() + static_cast<long>(i));
    else ++i;
  }
  for (size_t i = 0; i < thrown_.size();) {
    Thrown& t = thrown_[i];
    if (++t.age < kThrowTicks) {
      ++i;
      continue;
    }
    int x = t.x + kDX[t.dir] * kThrowStep * kThrowTicks;
    int y = t.y + kDY[t.dir] * kThrowStep * kThrowTicks + kThrowDrop;
    int kind = t.carry == 1 ? kLeaves : t.carry == 5 ? kPot : t.carry == 7 ? kSign : -1;
    if (kind >= 0) bursts_.push_back({kind, x, y, 0});
    thrown_.erase(thrown_.begin() + static_cast<long>(i));
  }
  for (size_t i = 0; i < items_.size();) {
    Item& it = items_[i];
    if (++it.age >= kChestItemTicks) {
      out.push_back({13, Net::gchar(static_cast<unsigned>(it.tx * 2)) + Net::gchar(static_cast<unsigned>(it.ty * 2))});
      items_.erase(items_.begin() + static_cast<long>(i));
    } else {
      ++i;
    }
  }
  return out;
}

std::vector<Piece> Effects::pieces() const {
  std::vector<Piece> out;
  for (const auto& it : items_) out.push_back({it.sprite, it.tx * 16 + 8, it.ty * 16 - 2});
  for (const auto& t : thrown_) {
    int x = t.x + kDX[t.dir] * kThrowStep * t.age;
    int y = t.y + kDY[t.dir] * kThrowStep * t.age + kThrowDrop * t.age / kThrowTicks;
    out.push_back({kShadowSprite, x + 2, t.ground + kDY[t.dir] * kThrowStep * t.age});
    out.push_back({carried_sprite(t.carry), x, y});
  }
  for (const auto& b : bursts_) {
    for (int q = 0; q < 4; ++q) {
      bool right = q & 1, bottom = q & 2;
      int sx = right ? 1 : -1, sy = bottom ? 1 : -1;
      int x = b.x + (right ? 16 : 0), y = b.y + (bottom ? 16 : 0);
      int sprite;
      if (b.kind == kCutLeaves) {
        // Down and out.
        x += sx * b.age;
        y += 2 * b.age;
      } else {
        x += sx * kBreakSpread * b.age;
        y += sy * kBreakSpread * b.age;
      }
      if (b.kind == kPot) sprite = right ? kPotRight : kPotLeft;
      else if (b.kind == kSign) sprite = right ? kSignRight : kSignLeft;
      else sprite = (b.age / 2) % 2 ? kLeafB : kLeafA;
      out.push_back({sprite, x, y});
    }
  }
  return out;
}

}  // namespace Quattro::World
