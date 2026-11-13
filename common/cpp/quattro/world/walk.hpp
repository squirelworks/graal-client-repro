// Walking on the board: the wall test and the push state.
//
// Behaviour, from Graal_analysis:
// - client-internals/decomp-findings-2026-10-25-l/02-arrays-dat.md: the
//   arrays.dat layout; array 0 lists the passable tiles, array 1 the liquids
//   (water and lava, both walkable); every other tile is a wall.
// - .../01-walking-body-box.md: each held arrow is its own half-tile step,
//   in the order up, left, down, right; six probe points on the leading
//   edge of a two-tile box; the step is kept when the first four are free;
//   a refused step may nudge 0.1 tile along the edge so a corner does not
//   catch; a chest blocks its 2 x 2 tiles.
// - protocol/v5v6-lab-play.md (5.24r4, 5.30r3, 6.03r7 agree): `walk` keeps
//   playing against a wall, `push` starts on the 18th blocked tick (0.9 s),
//   and while pushing the client sends 38 "pushed,0" about 0.55 s after the
//   push starts, then every 1.0 s.
//
// Rebuild choices: with no arrays.dat in the player's folder every tile is
// passable (the lab did not show where 6.x reads its table from); the
// 0.0625 snap after a step is left out (the note did not read it).
#pragma once

#include "../files/level.hpp"
#include "player.hpp"

#include <bitset>
#include <string>
#include <string_view>

namespace Quattro::World {

struct TileTypes {
  bool loaded = false;  // false: everything is passable
  std::bitset<4096> passable, liquid;

  bool blocks(uint16_t tile) const { return loaded && !passable[tile & 0xFFF] && !liquid[tile & 0xFFF]; }
};

// Reads arrays.dat: big-endian u32 headers (low 16 bits a count, high 16
// bits non-zero for nested arrays), to the end of the file. False when the
// file does not parse or has fewer than two arrays.
bool read_arrays_dat(std::string_view data, TileTypes& out, std::string& error);

// Is the point (in tiles) blocked on this level?
bool point_blocked(const Files::Level& level, const TileTypes& types, double x, double y);

// One half-tile step in direction `dir` (0 up, 1 left, 2 down, 3 right).
// Moves the player when the step is free (or nudges it along the edge) and
// sets its facing. Returns true when the step was kept.
bool step(Player& p, int dir, const Files::Level& level, const TileTypes& types);

// The walk/push/idle state across ticks.
class Walker {
 public:
  // keys: bit 0 up, 1 left, 2 down, 3 right. Returns the 38 action to send
  // this tick, or empty. While `carrying`, the gani is `carry` when moving
  // and `carrystill` when not (item-drawing lab).
  std::string tick(Player& p, unsigned keys, const Files::Level& level, const TileTypes& types,
                   bool carrying = false);
  bool pushing() const { return blocked_ticks_ >= kPushAfter; }
  // Keep the player on the board (0 to 62). Off for a gmap, whose parts
  // join at the edges (the program wraps the position).
  bool clamp = true;

  static constexpr int kPushAfter = 18;       // 0.9 s
  static constexpr int kFirstPushed = 11;     // about 0.55 s after push starts
  static constexpr int kPushedEvery = 20;     // 1.0 s

 private:
  int blocked_ticks_ = 0;
};

}  // namespace Quattro::World
