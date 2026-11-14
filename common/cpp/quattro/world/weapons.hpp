// The player's weapon list and what using a weapon does: built-in bombs
// and shots, laid or fired by this player or by others in the level.
//
// Behaviour, from Graal_analysis:
// - The list (manual/04-behaviour/06-hud-ui.md, "The selected weapon";
//   client-internals/status-display.md): server weapons (33) and built-in
//   ones (43, an item index) share one list in arrival order; a name the
//   list has is skipped; every add selects the new last entry; selecting
//   index i takes the first entry from i on, wrapping, whose name is not
//   empty and does not start with '-'; a delete keeps the selection's index
//   if it still exists, else the new last entry. 34 deletes by name, 194
//   clears the list (protocol/packet-ids.md).
// - Built-in weapons: items 7 bow, 8 bomb, 12 superbomb, 20 fireball,
//   21 fireblast, 22 nukeshot, 23 joltbomb; the name is the item name with a
//   capital first letter; images wbowi1..4 and wbomb1..3, as .png from 2.22
//   on (the 5.x/6.x lab fetched wbowi1.png and wbomb1.png after the warp,
//   protocol/v5v6-lab-play.md).
// - Combat messages (client-internals/feature-specs/02-weapons-combat.md,
//   manual/02-protocol/04-pli.md and 05-plo.md):
//     C->S 4 BOMBADD  c x*2, c y*2, c power (+8 own), c fuse (55 seen)
//     C->S 9 ARROWADD c x*2, c y*2, c flags (dir & 3, +8 own), c sprite, c kind + 33
//     C->S 27 EXPLOSION c radius, c x*2, c y*2, c power (+8 own)
//     S->C 11 BOMBADD  s player + the four bytes; 12 BOMBDEL c x*2, c y*2
//     S->C 19 ARROWADD s player + the five bytes; 36 EXPLOSION s player + the four
//
// Rebuild readings, the same as the 2.x Pascal rebuilds' (Adventure.pas
// LayBombOf, AddBlast, Shoot, TickShots), since no 6.x note gives them:
// a bomb goes 1.5 tiles ahead of the body; a blast of reach 2 lives 11
// ticks; only the owner's blast changes the board (a bush is cut, a sign,
// pot or stone lifted, at four points of each piece); a shot moves one
// tile a tick and stops at a wall. The fuse is the 55 ticks seen on the
// wire (the Pascal rebuilds send 60).
#pragma once

#include "actions.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace Quattro::World {

struct Weapon {
  std::string name, image;
  int item = -1;  // the built-in item index, or -1 for a server weapon
};

class WeaponList {
 public:
  // Adds unless the list has the name, and selects it. False when skipped.
  bool add(const std::string& name, const std::string& image = {}, int item = -1);
  // A built-in weapon by item index (43); false for an item that is no weapon.
  bool add_default(int item);
  void remove(const std::string& name);
  void clear() { list_.clear(); selected_ = -1; }
  // Selects index i by the 2.05 rule (hidden names are passed over).
  void select(int i);
  // The next shown weapon after the selected one (the rebuild's Q, below).
  void select_next() { select(selected_ + 1); }

  const std::vector<Weapon>& list() const { return list_; }
  int selected_index() const { return selected_; }
  const Weapon* selected() const {
    return selected_ >= 0 && selected_ < static_cast<int>(list_.size()) ? &list_[static_cast<size_t>(selected_)] : nullptr;
  }
  // Whether any entry is shown (a name not starting with '-').
  bool any_shown() const;

 private:
  std::vector<Weapon> list_;
  int selected_ = -1;
};

// The built-in weapon's name and image, empty for an item that is none.
std::string default_weapon_name(int item);
std::string default_weapon_image(int item);
inline bool hidden_weapon(const std::string& name) { return name.empty() || name[0] == '-'; }

struct Bomb {
  double x = 0, y = 0;  // top-left of the 2 x 2 bomb, tiles
  int power = 1;        // 1..3
  int fuse = 0;         // ticks left
  bool mine = false;
};

struct Blast {
  double x = 0, y = 0;  // the bomb's top-left, tiles
  int reach = 2, power = 1, age = 0;
  bool mine = false;
};

struct Shot {
  double x = 0, y = 0;  // top-left, tiles
  int dir = 0, sprite = 107, kind = 0;  // kind 0 arrow, 1 fireball, 2 fireblast, 3 nuke
  bool mine = false;
};

class Combat {
 public:
  // Lays this player's bomb (power 1..3) 1.5 tiles ahead of the body; the
  // 4 BOMBADD to send. It takes one from the count, and none goes without
  // one. put_bomb places one where a script says and takes none.
  std::vector<Packet> lay_bomb(Player& p, int power);
  std::vector<Packet> put_bomb(int power, double x, double y);
  // Fires a shot of `kind` from just ahead of the body's middle; an arrow
  // takes one from the count, and none goes without one.
  std::vector<Packet> shoot(Player& p, int kind);
  std::vector<Packet> shoot_from(double x, double y, int dir, int kind);

  // From the server: 11, 12, 19, 36. False for other ids.
  bool on_message(int id, std::string_view body);

  // One 50 ms tick: fuses burn, blasts age, shots fly. Returns what to
  // send: 27 EXPLOSION for this player's bombs, and the board changes of
  // their blasts (1 BOARDMODIFY).
  std::vector<Packet> tick(Files::Level& level, const ObjectTables& tables, const TileTypes& types);
  void clear() { bombs_.clear(); blasts_.clear(); shots_.clear(); }

  // What hits this player now, judged on the victim's side as 2.05 does:
  // a blast piece whose centre is under a tile from the body's centre
  // (x + 1.5, y + 2) on both axes (a power-3 blast one heart, else half);
  // another player's shot over the body box (x + 0.5 to 2.5, y + 1 to 3),
  // which then goes (a fireball or nuke one heart, else half). A shot
  // met head on by a shield while standing or walking does not hurt: with
  // shield power 2 or more it flies back as this player's own (the 9
  // ARROWADD with flag 4 is in `out`), with power 1 it drops.
  struct Hit {
    double hearts = 0.5, kx = 0, ky = 0;
  };
  std::vector<Hit> hits_on(const Player& me, const ObjectTables& tables, std::vector<Packet>& out);

  const std::vector<Bomb>& bombs() const { return bombs_; }
  const std::vector<Blast>& blasts() const { return blasts_; }
  const std::vector<Shot>& shots() const { return shots_; }

  static constexpr int kFuse = 55, kBlastTicks = 11, kBlastReach = 2, kArrowSprite = 107;

 private:
  void add_blast(double x, double y, int reach, int power, bool mine);
  std::vector<Bomb> bombs_;
  std::vector<Blast> blasts_;
  std::vector<Shot> shots_;
  std::vector<std::pair<double, double>> pending_;  // own blasts whose board change is due
};

}  // namespace Quattro::World
