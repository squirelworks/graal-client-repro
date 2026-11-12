// The built-in UI font for GUI text until the player's own fonts are read
// (rebuild stand-in: 6.x draws TrueType faces such as tempsitcbd.ttf, which
// are not ours to ship). Liberation Sans at a 16 px line, regular and bold.
#pragma once

#include "../../../torque/gui/canvas.hpp"

#include <string_view>

namespace Quattro::Draw {

struct UiFace {
  const unsigned char* adv;          // advance per char, 32..255
  const unsigned char* width;        // cell width per char
  const unsigned short (*rows)[16];  // one bit per pixel, bit 0 leftmost
};

constexpr int kUiLineHeight = 16;

const UiFace& ui_face(bool bold);
int ui_text_width(std::string_view s, bool bold);
// Draws `s` with the top of its 16 px line at y, inside the canvas clip.
void ui_draw_text(Torque::Gui::Canvas& c, int x, int y, std::string_view s, Torque::Gui::Color colour, bool bold);

}  // namespace Quattro::Draw
