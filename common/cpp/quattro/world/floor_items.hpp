// Items lying on the board: the server's 22 ITEMADD / 23 ITEMDEL, a local
// lay (12), and the 164-tick life from the 2.05 Adventure rebuild
// (client-internals/item-drops.md). The gralat a cut bush drops is one of
// these; Quattro did not draw them yet.
//
// Behaviour (Adventure.pas AddItem / TickItems / DrawItems):
// - Only FloorItem indexes are kept from the wire; a local lay may add any
//   laid index (Pascal AddItem before the FloorItem send filter).
// - Life counts down one per 50 ms tick from 164; life < 100 is permanent
//   (shown, never taken, never ITEMDEL).
// - After four ticks, walking near the item sends 32 ITEMTAKE (online) or
//   applies GiveItem offline; life < 0 sends 13 ITEMDEL when not permanent.
// - Draw: blinks when life < 37 and odd; a short bounce on land; shadow
//   under the sprite, item centred on (x+1, y+1).
#pragma once

#include "actions.hpp"
#include "effects.hpp"
#include "player.hpp"

#include <string>
#include <vector>

namespace Quattro::World {

struct FloorItem {
  double x = 0, y = 0;  // tiles, top-left
  int item = 0;
  int life = 0;
  bool permanent = false;
};

class FloorItems {
 public:
  static constexpr int kItemLife = 164;
  static constexpr int kPlItemTake = 32;
  static constexpr int kPlItemDel = 13;

  // Adds an item. `life` defaults to kItemLife; permanent when life < 100.
  void add(double x, double y, int item, int life = kItemLife);
  // Removes every item at exactly (x, y) tiles (PLO_ITEMDEL).
  void remove_at(double x, double y);
  void clear() { items_.clear(); }

  // One 50 ms tick. Online: ITEMTAKE / ITEMDEL to send. Offline: applies
  // GiveItem into `p` when taken. `online` is whether a session is up.
  std::vector<Packet> tick(Player& p, bool online);

  // What to draw now (sprite index + top-left world pixels), back to front.
  // `sprite_wh` returns the list-24 cell size for an item sprite, or false.
  using SizeFn = bool (*)(int sprite, int& w, int& h, void* ctx);
  std::vector<Piece> pieces(SizeFn size, void* ctx) const;

  const std::vector<FloorItem>& list() const { return items_; }
  bool empty() const { return items_.empty(); }

  // Offline GiveItem: rupees, bombs, arrows, hearts, spin bit. Weapons and
  // power-ups that need the weapon list are left for the caller / server.
  static void give_item(Player& p, int item);

 private:
  std::vector<FloorItem> items_;
};

}  // namespace Quattro::World
