// The 6.x built-in HUD, drawn over the world from state.png.
//
// Layout from the 6.03r7 HUD lab (Linux client, 2026-11-12), in client
// pixels; nothing scales with the window:
// - the A, S, D tabs, the AP and MP bars and the gralat, bomb and arrow
//   counters keep their x from the left edge;
// - the hearts keep their x from the right edge (the first at width - 198);
// - up to 4 hearts are full size (40 x 44, 45 px apart) in one row; from 5
//   they are small (35 px apart) in staggered rows of 5, 6, 5 and 4;
// - only the current hearts are drawn, in half-heart steps;
// - the AP bar always shows; its fill is the fixed 100-pixel strip cut at
//   the AP value. The MP bar shows only when MP is above 0;
// - at 5 and 5.5 hearts the small block sits 10 px lower;
// - the A, S and D tabs are the same sprite with no letters; the glove
//   (sprites.png, from power 2) sits in A and the sword (swordN.png) in S;
// - gralats are drawn with no padding, bombs and arrows with two digits,
//   from state.png's digit row, 12 px apart.
//
// The sheet positions are those of the player's own state.png (224 x 145);
// the rebuild does not ship one. With no state.png nothing is drawn.
#pragma once

#include "assets.hpp"

#include "../../../torque/gui/canvas.hpp"

#include <string>
#include <vector>

namespace Quattro::Draw {

struct HudState {
  int half_hearts = 0;  // the player's power, in half hearts
  int gralats = 0, bombs = 0, arrows = 0;
  int ap = 50, mp = 0;
  int glove_power = 0, sword_power = 0;
  std::string sword_image;  // empty: sword<power>.png
};

class Hud {
 public:
  explicit Hud(Assets* assets) : assets_(assets) {}

  // Draws the HUD on the whole canvas (the client area).
  void draw(Torque::Gui::Canvas& c, const HudState& s) const;

  // Where the hearts go for this state, as top-left corners; `small` says
  // which size. Exposed for tests.
  struct HeartSlot {
    int x = 0, y = 0;
    bool half = false;
  };
  static std::vector<HeartSlot> heart_slots(int half_hearts, int width, bool& small);

  // The text of a counter: gralats unpadded, bombs and arrows two digits
  // (the last two of a larger value's first two digits are kept, as the
  // lab's arrows=100 drew "10").
  static std::string counter_text(int value, bool two_digits);

 private:
  void draw_number(Torque::Gui::Canvas& c, const Torque::Gui::Image& sheet, const std::string& text,
                   int centre_x, int y) const;
  Assets* assets_;
};

}  // namespace Quattro::Draw
