// The item keys: S swings the sword (and spins), A lifts, throws, grabs or
// lays, D toggles the weapon state, and walking into a chest opens it.
//
// Behaviour, from the 6.03r7 item-keys lab (Linux client, 2026-11-13), plus
// the spin and lay mode from the 2.05/2.22 live runs (same rules the 4.04r2
// Adventure rebuild uses; STATUS bit 0x40):
// - Every carry sprite prop sent is also kept in the player's carry_sprite.
// - S: gani `sword` with the facing (props 10 and 17) at once, `idle`
//   5 ticks (0.25 s) later; holding S swings once. A bush (arrays.dat
//   list 9) at the blade's tip is cut in the same tick: 1 BOARDMODIFY with
//   its 2 x 2 "left" tiles from list 10. No hit or item packet.
// - S again during the swing, with STATUS bit 0x40 (has-spin): cuts the
//   swing off and plays `spin` for 13 ticks, then idle. S during the spin
//   is ignored. Hit reach for a spin is every facing (health.cpp).
// - A, free: a liftable object (list 11, the first glove + 2 entries) at
//   the tip is lifted: BOARDMODIFY with list 12, gani `lift` and carry
//   sprite -1 in one tick; the carry sprite 4 ticks (0.20 s) later (bush
//   1, sign 7, pot 5); gani `carrystill` 6 ticks (0.30 s) after the press.
// - A, carrying: 11 THROWCARRIED (empty), gani `idle`, carry sprite -1.
//   Nothing is sent when it lands.
// - A against anything else that blocks: gani `grab`; with the arrow away
//   from it held, `pull`. Only the pose changes; it stays after release.
// - A with S held and nothing to lift (probe not a wall): enter the lay
//   mode with the first layable item. A with S held again picks the next;
//   A alone lays it two tiles ahead (three up) and sends 12 ITEMADD for
//   floor items plus the counter prop. An arrow, D or S leaves without
//   laying. Custom sword/shield pictures and water-vs-land are not told
//   apart yet (same known limits as the Pascal rebuilds).
// - D (and Q, Tab) with no weapon shown: the status prop toggles bit 0
//   (20 <-> 21). With one, the program uses the weapon instead (weapons.hpp).
// - Walking into a closed chest opens it: 20 OPENCHEST x, y, once.
//
// The probe point and the 2 x 2 match follow the 2.22 Pascal rebuild's
// Adventure.pas (ProbePoint, MatchObject). What is drawn for them is in
// effects.hpp. Rebuild choice: the stone's carry sprite was not seen
// (glove 1 cannot lift it), so lifting it sends no second carry sprite.
#pragma once

#include "../files/level.hpp"
#include "player.hpp"
#include "walk.hpp"

#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace Quattro::World {

// One 2 x 2 object: tiles (col 0 row 0, col 0 row 1, col 1 row 0, col 1 row 1).
using Object = std::array<int, 4>;
inline int object_tile(const Object& o, int col, int row) { return o[static_cast<size_t>(col * 2 + row)]; }

struct ObjectTables {
  std::vector<Object> cut, cut_left, lift, lift_left;
  std::vector<uint32_t> sprites;  // list 24: packed sprites.png rects
  bool loaded = false;
};

// Sprite `i` of list 24 on sprites.png; false when there is none.
bool sprite_rect(const ObjectTables& t, int i, int& x, int& y, int& w, int& h);

// The object lists of arrays.dat (9 cut, 10 what a cut leaves, 11 lift,
// 12 what a lift leaves) and its sprite list (24). False when the file does not parse.
bool read_object_tables(std::string_view arrays_dat, ObjectTables& out);

// The point the blade or the hands reach, in tiles, for the facing.
void probe_point(const Player& p, double& x, double& y);

// The first object of `list` (up to `max_count` entries) whose 2 x 2 tiles
// on the board cover (x, y); its index, or -1. `ox`, `oy` its corner.
int match_object(const Files::Level& level, const std::vector<Object>& list, int max_count, double x, double y,
                 int& ox, int& oy);

struct Packet {
  int id = 0;
  std::string body;
};

// Item key bits for ItemKeys::tick.
enum ItemKey : unsigned { kKeyA = 1, kKeyS = 2, kKeyD = 4 };

// Indexes that may lie on the board (Adventure.FloorItem; PLO_ITEMADD).
inline bool is_floor_item(int item) {
  return (item >= 0 && item <= 5) || item == 7 || item == 8 || item == 19 || item == 24;
}

class ItemKeys {
 public:
  explicit ItemKeys(int sprite_after = 4, int still_after = 6)
      : sprite_after_(sprite_after), still_after_(still_after) {}
  // One 50 ms tick. `keys`: the held ItemKey bits; `arrows`: the held walk
  // keys (bit 0 up, 1 left, 2 down, 3 right). Changes the player and the
  // board, and returns what to send (props as id 2, the rest as is). Call
  // before the walker; while busy() the walker should get no arrows.
  std::vector<Packet> tick(Player& p, unsigned keys, unsigned arrows, Files::Level& level,
                           const ObjectTables& tables, const TileTypes& types);
  // A walk into a closed chest at (x, y) of the probe: the OPENCHEST to send,
  // once per chest per level. Call after the walker with the walk keys.
  std::vector<Packet> touch_chests(const Player& p, unsigned arrows, const Files::Level& level);
  void new_level() { opened_.clear(); }

  bool busy() const {
    return mode_ == Mode::Sword || mode_ == Mode::Spin || mode_ == Mode::Lift || mode_ == Mode::Lay;
  }
  bool carrying() const { return mode_ == Mode::Carry || mode_ == Mode::Lift; }
  bool lifting() const { return mode_ == Mode::Lift; }
  bool laying() const { return mode_ == Mode::Lay; }
  // The item index being offered in the lay mode, or -1.
  int laying_item() const { return mode_ == Mode::Lay ? lay_item_ : -1; }
  // The carry sprite of what is lifted or carried (from the press on), or -1.
  int carry_sprite() const { return carrying() && carry_kind_ >= 0 && carry_kind_ < 3 ? kLiftSprites[carry_kind_] : -1; }
  static constexpr int kLiftSprites[3] = {1, 7, 5};  // bush, sign, pot

  static constexpr int kSwordTicks = 5, kSpinTicks = 13, kCarrySpriteAfter = 4, kCarryStillAfter = 6;
  // STATUS bit: the player has the spin attack (server or spinattack item).
  static constexpr int kStatusHasSpin = 0x40;

 private:
  enum class Mode { Free, Sword, Spin, Lift, Carry, Lay };
  Mode mode_ = Mode::Free;
  int sprite_after_, still_after_;
  int ticks_ = 0;       // since the mode started
  int carry_kind_ = -1;
  int lay_item_ = -1;   // item index while Mode::Lay
  unsigned last_keys_ = 0;
  std::vector<std::pair<int, int>> opened_;
};

// A BOARDMODIFY body: x, y, w, h and the tiles row by row.
std::string board_modify(int x, int y, int w, int h, const std::vector<int>& tiles);

// Puts object `o` on the board at (x, y) and returns the 1 BOARDMODIFY for
// it, or empty when nothing changed.
std::string put_object(Files::Level& level, int x, int y, const Object& o);

}  // namespace Quattro::World
