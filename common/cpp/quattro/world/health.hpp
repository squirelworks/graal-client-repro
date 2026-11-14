// Being hurt: hearts, the hurt pose and its knockback, dying, coming back,
// and other players' sword swings judged on this player's side.
//
// From Graal_analysis:
// - protocol/v5v6-lab-play.md (5.24r4, 5.30r3 and 6.03r7 on a lab server):
//   a hit plays `hurt` for 1.55 s, the 31 ticks of the hurt gani, and
//   pushes the player 5 tiles in 5 ticks.
// - client-internals/feature-specs/02-weapons-combat.md (2.05): the victim's
//   client decides a hit. A swing counts when the attacker shows the sword
//   (gani `sword`), the victim is 0 to 4 tiles ahead of it and under 2 to
//   the side, and the victim's AP is not exactly 100; no second hit while
//   hurt. CURPOWER (prop 2) is in half hearts and the client sends its new
//   value; at 0 it sends 14 CLAIMPKER with the killer's id.
// - manual/02-protocol/05-plo.md: 40 HURTPLAYER (s attacker, c (dx+4)*16,
//   c (dy+4)*16, c power in half hearts); refused from an NPC or from a
//   player more than 10 tiles away.
//
// Rebuild readings, as in the 2.x Pascal rebuilds (Adventure.pas
// HurtPlayer, KnockStep, Respawn): the knockback is a tile a tick along
// the hit's direction scaled to one tile (east when it has none), a step
// is undone when one of twelve body points would be in a wall; a swing
// hurts sword power / 2 hearts, once a second per attacker; a dead player
// comes back on an arrow key with hearts by alignment (AP under 20 three,
// under 40 five, else all) where it entered the level, sending its
// hearts and a 0 LEVELWARP.
#pragma once

#include "actions.hpp"
#include "player.hpp"

#include <map>
#include <vector>

namespace Quattro::World {

class Health {
 public:
  bool dead() const { return dead_; }
  bool hurting() const { return hurt_ > 0; }
  bool hurtable(const Player& p) const { return hurt_ == 0 && !dead_ && p.ap != 100; }

  // A hit of `hearts` from the direction (kx, ky); `attacker` is the
  // player id or -1. Returns what to send: CURPOWER, and CLAIMPKER on death.
  std::vector<Packet> hit(Player& p, double hearts, double kx, double ky, int attacker = -1);
  // 40 HURTPLAYER's body.
  std::vector<Packet> on_hurt_player(Player& p, std::string_view body, const std::map<int, Player>& others);
  // Other players' swings this tick.
  std::vector<Packet> check_swords(Player& p, const std::map<int, Player>& others);
  // One 50 ms tick: knockback, then back to idle when the hurt ends.
  void tick(Player& p, const Files::Level& level, const TileTypes& types);
  // While dead, an arrow key brings the player back at (x, y).
  std::vector<Packet> respawn(Player& p, double x, double y, const std::string& level);
  void reset() { hurt_ = 0; dead_ = false; swing_tick_.clear(); }

  static constexpr int kHurtTicks = 31, kKnockTicks = 5, kSwingGap = 20;

 private:
  int hurt_ = 0;
  bool dead_ = false;
  double kx_ = 1, ky_ = 0;
  int ticks_ = 0;
  std::map<int, int> swing_tick_;  // attacker -> tick of its last hit
};

}  // namespace Quattro::World
