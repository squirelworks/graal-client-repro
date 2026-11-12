// GANI0001 sprite-mode animations: the sprite table, the header flags and
// the ANI steps. Grammar: Graal_analysis formats/gani.txt, read the same
// way as common/GAni.pas (the Pascal clients' reader): keywords match
// without case; a step holds four direction rows (one with
// SINGLEDIRECTION); WAIT n lengthens the step before it; ATTACHSPRITE
// hangs a child over its parent, ATTACHSPRITE2 under it, expanded into the
// steps when the file is read.
//
// Movie mode (GANI0002) and the SCRIPT block are skipped here.
#pragma once

#include <array>
#include <string>
#include <string_view>
#include <vector>

namespace Quattro::Files {

struct GaniSprite {
  int id = -1;
  std::string sheet;  // SPRITES, HEAD, BODY, SWORD, SHIELD, ATTR1..30, PARAMn or a file
  int x = 0, y = 0, w = 0, h = 0;
};

struct GaniPart {
  int sprite = -1;  // a sprite id, or kParamSprite - n for PARAMn
  int x = 0, y = 0;
};

constexpr int kParamSprite = -1000;

struct GaniStep {
  std::array<std::vector<GaniPart>, 4> dirs;  // up, left, down, right
  int ticks = 1;                              // 1 + WAIT
  std::string sound;
};

struct Gani {
  std::vector<GaniSprite> sprites;
  std::vector<GaniStep> steps;
  bool loop = false, continuous = false, single_direction = false;
  std::string set_back_to, default_head, default_body;
  std::array<std::string, 31> default_attr;  // 1..30

  const GaniSprite* sprite(int id) const;
  int total_ticks() const;
  // The step shown `tick` ticks after the start: looping, or holding the
  // last step.
  size_t step_at(int tick) const;
};

// False when the text has no steps.
bool read_gani(std::string_view text, Gani& out);

}  // namespace Quattro::Files
