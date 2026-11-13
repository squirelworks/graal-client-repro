#include "effects.hpp"

#include "../net/gtypes.hpp"

#include <algorithm>

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
// The two images each piece swaps between every tick: right, left.
constexpr int kPotRight[2] = {97, 96}, kPotLeft[2] = {99, 98};
constexpr int kSignRight[2] = {100, 103}, kSignLeft[2] = {102, 101};

enum BurstKind { kLeaves = 0, kPot = 1, kSign = 2 };

}  // namespace

int item_sprite(int item) { return item >= 0 && item < 25 ? kItemSprites[item] : -1; }

void Effects::throw_object(int carry_sprite, int px, int py, int dir) {
  if (carry_sprite < 0) return;
  thrown_.push_back({carry_sprite, px + 8, py - 22, py + 34, dir & 3, 0});
}

void Effects::cut_bush(int tx, int ty) { bursts_.push_back({kLeaves, tx * 16, ty * 16, 0, kCutLeafDelay}); }

void Effects::chest_item(int item, int cx, int cy) {
  int s = item_sprite(item);
  if (s >= 0) items_.push_back({s, cx, cy - 1, 0});
}

std::vector<Packet> Effects::tick() {
  std::vector<Packet> out;
  // Pieces age first, so a break starts whole on the tick it lands.
  for (size_t i = 0; i < bursts_.size();) {
    Burst& b = bursts_[i];
    int life = (b.kind == kLeaves ? kLeafTicks : kBreakTicks) + b.delay;
    if (++b.age >= life) bursts_.erase(bursts_.begin() + static_cast<long>(i));
    else ++i;
  }
  for (size_t i = 0; i < thrown_.size();) {
    Thrown& t = thrown_[i];
    if (++t.age <= kThrowTicks) {  // drawn at 0..8, breaks on the 9th tick
      ++i;
      continue;
    }
    // The pieces start one step past the landing cell, 13 px lower (lab:
    // facing right and down).
    int x = t.x + kDX[t.dir] * kThrowStep * (kThrowTicks + 1);
    int y = t.y + kDY[t.dir] * kThrowStep * (kThrowTicks + 1) + kThrowDrop[kThrowTicks] + 13;
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
    int y = t.y + kDY[t.dir] * kThrowStep * t.age + kThrowDrop[t.age];
    out.push_back({kShadowSprite, x + 4, t.ground + kDY[t.dir] * kThrowStep * t.age});
    out.push_back({carried_sprite(t.carry), x, y});
  }
  for (const auto& b : bursts_) {
    if (b.age < b.delay) continue;
    int age = b.age - b.delay;
    for (int q = 0; q < 4; ++q) {
      bool right = q & 1, bottom = q & 2;
      int x = b.x + (right ? 16 : 0), y = b.y + (bottom ? 16 : 0);
      int sprite;
      if (b.kind == kLeaves) {
        int t = age + 1;
        if (!right) {
          x -= 2 * t;  // left leaves go left; the top one also rises
          if (!bottom) y -= 4 * t;
        } else {
          x += 2 * std::min(t, 2);  // right leaves go right, then fall
          y += 2 * std::max(t - 2, 0);
        }
        sprite = ((age + q) / 2) % 2 ? kLeafB : kLeafA;
      } else {
        int d = kBreakSpread * (age + 1);
        x += right ? d : -d;
        y += bottom ? d : -d;
        const int* pair = b.kind == kPot ? (right ? kPotRight : kPotLeft) : (right ? kSignRight : kSignLeft);
        sprite = pair[age % 2];
      }
      out.push_back({sprite, x, y});
    }
  }
  return out;
}

}  // namespace Quattro::World
