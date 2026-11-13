// What the 6.x client draws for the item keys besides the players:
// a thrown object's flight and break, a cut bush's leaves, and the item
// over an opened chest.
//
// From the 6.03r7 item-drawing lab (Linux client, 2026-11-13). Every
// rectangle below is a sprite of arrays.dat list 24 on sprites.png, and the
// lab's measured rects match those sprites.
// - The carried object is sprite 260 + the carry sprite prop (bush 1 -> 261,
//   pot 5 -> 265, sign 7 -> 267), a 32 x 32 cell. It is drawn at the
//   player's top-left + (8, head y - 22): it bobs with the head while
//   walking. While lifting it rises from (8, +8) to (8, -22).
// - Throw: the object leaves from the carried position and travels 128 px
//   (8 ticks of 16 px) in the facing. It drops 24 px towards the ground on
//   the way. Its shadow (sprite 0, 24 x 12) stays on the ground, at the
//   player's top + 34 and the object's x + 2. Nothing is sent on landing.
// - Break: 4 pieces in a 2 x 2 pattern spread outward. Bush: leaves
//   (sprites 25 and 26, the same image for all four, alternating). Pot:
//   shards 97 on the right, 99 on the left. Sign: 100 and 102.
// - S on a bush: the same 4 leaves start on the bush and drift down and out.
// - Opening a chest: its item (list 24 sprite of the item) is drawn one tile
//   above the chest at (+8, -2) px. After 1.2 s the client sends 13 ITEMDEL
//   (x * 2, y * 2 of that point) and the item goes.
//
// Rebuild choices (marked APPROX): the lab's frames were 120-450 ms apart
// on a loaded VM, so the break and leaf durations, speeds and the leaf
// frame rate are estimates. The stone (carry sprite 3) breaks with no
// pieces, as it was not measured.
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

  static constexpr int kThrowTicks = 8, kThrowStep = 16, kThrowDrop = 24;
  static constexpr int kBreakTicks = 6, kBreakSpread = 2;  // APPROX: ~0.3 s, 8 px per sampled frame
  static constexpr int kLeafTicks = 9;                     // APPROX: ~0.44 s
  static constexpr int kChestItemTicks = 24;               // 1.2 s (item-keys lab, unloaded)

 private:
  struct Thrown {
    int carry, x, y, ground, dir, age;
  };
  // Four pieces from a 32 x 32 cell at (x, y).
  struct Burst {
    int kind;  // 0 leaves (break), 1 pot, 2 sign, 3 leaves (cut)
    int x, y, age;
  };
  struct Item {
    int sprite, tx, ty, age;
  };
  std::vector<Thrown> thrown_;
  std::vector<Burst> bursts_;
  std::vector<Item> items_;
};

}  // namespace Quattro::World
