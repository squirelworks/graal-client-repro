// What the 6.x client draws for the item keys besides the players:
// a thrown object's flight and break, a cut bush's leaves, and the item
// over an opened chest.
//
// From the 6.03r7 item-drawing lab (Linux client, 2026-11-13; the timing
// series with frames 45-55 ms apart). Every rectangle below is a sprite of
// arrays.dat list 24 on sprites.png, and the lab's measured rects match
// those sprites.
// - The carried object is sprite 260 + the carry sprite prop (bush 1 -> 261,
//   pot 5 -> 265, sign 7 -> 267), a 32 x 32 cell. It is drawn at the
//   player's top-left + (8, head y - 22) in every facing. While lifting it
//   stays on the ground row (+47) for 4 ticks, then rises in 4 (+30, +16,
//   -16, -22).
// - Throw: the object leaves from the carried position and moves 16 px a
//   tick in the facing for 8 ticks (128 px). It drops 1 px on the first
//   tick and 3 px a tick after (23 px in all). Its shadow (sprite 0,
//   24 x 12) is centred under the cell (x + 4) on the ground, the player's
//   top + 34, and moves with it. Nothing is sent on landing.
// - Break: 4 pieces, a 2 x 2 one step past the landing cell, 4 ticks.
//   Pot and sign pieces move 4 px a tick diagonally outward and swap
//   their image every tick (pot 97 <-> 96 on the right, 99 <-> 98 on the
//   left; sign 100 <-> 103 and 102 <-> 101). A bush gives leaves instead.
// - Leaves (a thrown bush, or S on a bush): sprites 25 and 26, 6 ticks,
//   each leaf flipping its image every 2 ticks out of phase with the
//   others. The top leaves rise 4 px a tick, the left ones go 2 px left,
//   the right ones 2 px right for 2 ticks and then fall 2 px a tick. A
//   cut bush's leaves show from 4 ticks (0.21 s) after the key.
// - Opening a chest: its item (list 24 sprite of the item) is drawn one tile
//   above the chest at (+8, -2) px. The client sends 13 ITEMDEL (x * 2,
//   y * 2 of that point) after 1.2 s (item-keys lab; the timing series saw
//   1.35 s) and the item goes.
//
// Rebuild choices: the leaves' paths are the lab's per-tick drifts rounded
// to one rule per corner; the break's offset past the landing cell was
// measured facing right and down only; a thrown stone (carry sprite 3)
// breaks into nothing, as it was not measured. The gralat the server drops
// from a cut bush (its ITEMADD) is a floor item, not drawn yet.
#pragma once

#include "actions.hpp"

#include <vector>

namespace Quattro::World {

// One sprite to draw: arrays.dat list 24 index, top-left in world pixels.
struct Piece {
  int sprite = 0;
  int x = 0, y = 0;
};

// The carried object's sprite for a carry sprite prop, or -1.
inline int carried_sprite(int carry_sprite) { return carry_sprite >= 0 ? 260 + carry_sprite : -1; }

// The list 24 sprite of a chest or floor item, or -1.
int item_sprite(int item);

class Effects {
 public:
  // A throw by a player whose top-left is at (px, py) world pixels, facing
  // `dir`, carrying `carry_sprite` (the prop value).
  void throw_object(int carry_sprite, int px, int py, int dir);
  // S cut the bush whose 2 x 2 corner is tile (tx, ty).
  void cut_bush(int tx, int ty);
  // A chest at tile (cx, cy) opened with `item`.
  void chest_item(int item, int cx, int cy);

  // One 50 ms tick. Returns the packets to send (ITEMDEL).
  std::vector<Packet> tick();
  // What to draw now, back to front.
  std::vector<Piece> pieces() const;
  void clear() { thrown_.clear(); bursts_.clear(); items_.clear(); }
  bool empty() const { return thrown_.empty() && bursts_.empty() && items_.empty(); }

  static constexpr int kThrowTicks = 8, kThrowStep = 16;
  static constexpr int kBreakTicks = 4, kBreakSpread = 4;
  static constexpr int kLeafTicks = 6, kCutLeafDelay = 4;
  static constexpr int kChestItemTicks = 24;
  // The drop of a thrown object below its carried height, by ticks in the air.
  static constexpr int kThrowDrop[kThrowTicks + 1] = {0, 1, 4, 7, 10, 13, 17, 20, 23};

 private:
  struct Thrown {
    int carry, x, y, ground, dir, age;
  };
  // Four pieces from a 32 x 32 cell at (x, y).
  struct Burst {
    int kind;  // 0 leaves, 1 pot, 2 sign
    int x, y, age;
    int delay = 0;  // ticks before it shows
  };
  struct Item {
    int sprite, tx, ty, age;
  };
  std::vector<Thrown> thrown_;
  std::vector<Burst> bursts_;
  std::vector<Item> items_;
};

}  // namespace Quattro::World
