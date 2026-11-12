#include "ui_font.hpp"

namespace Quattro::Draw {

namespace {
int index_of(char ch) {
  int c = static_cast<unsigned char>(ch);
  if (c < 32) c = '?';
  return c - 32;
}
}  // namespace

int ui_text_width(std::string_view s, bool bold) {
  const UiFace& f = ui_face(bold);
  int w = 0;
  for (char ch : s) w += f.adv[index_of(ch)];
  return w;
}

void ui_draw_text(Torque::Gui::Canvas& c, int x, int y, std::string_view s, Torque::Gui::Color colour, bool bold) {
  const UiFace& f = ui_face(bold);
  for (char ch : s) {
    int i = index_of(ch);
    for (int r = 0; r < kUiLineHeight; ++r) {
      unsigned bits = f.rows[i][r];
      for (int b = 0; bits && b < f.width[i]; ++b)
        if (bits & (1u << b)) c.blend_pixel(x + b, y + r, colour);
    }
    x += f.adv[i];
  }
}

}  // namespace Quattro::Draw
