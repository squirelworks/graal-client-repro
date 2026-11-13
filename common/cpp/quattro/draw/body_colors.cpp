#include "body_colors.hpp"

#include <map>

namespace Quattro::Draw {

using Torque::Gui::Color;

Color player_colour(int index) {
  static const Color table[20] = {
      {255, 255, 255, 255}, {255, 255, 0, 255}, {255, 173, 107, 255}, {255, 132, 132, 255}, {255, 0, 0, 255},
      {206, 24, 41, 255},   {132, 255, 132, 255}, {0, 255, 0, 255},   {0, 198, 0, 255},     {132, 132, 255, 255},
      {0, 0, 255, 255},     {0, 0, 198, 255},     {132, 0, 0, 255},   {0, 255, 255, 255},   {255, 0, 255, 255},
      {132, 0, 132, 255},   {206, 206, 206, 255}, {132, 132, 132, 255}, {0, 0, 8, 255},     {0, 0, 0, 0}};
  return table[((index % 20) + 20) % 20];
}

std::vector<Color> png_palette(const std::vector<std::uint8_t>& png) {
  std::vector<Color> pal;
  if (png.size() < 8) return pal;
  size_t pos = 8;
  while (pos + 12 <= png.size()) {
    uint32_t len = (uint32_t(png[pos]) << 24) | (uint32_t(png[pos + 1]) << 16) | (uint32_t(png[pos + 2]) << 8) |
                   png[pos + 3];
    if (len > png.size() - pos - 12) break;
    const uint8_t* type = &png[pos + 4];
    const uint8_t* body = &png[pos + 8];
    if (type[0] == 'P' && type[1] == 'L' && type[2] == 'T' && type[3] == 'E') {
      pal.clear();
      for (uint32_t i = 0; i + 2 < len; i += 3) pal.push_back({body[i], body[i + 1], body[i + 2], 255});
    } else if (type[0] == 't' && type[1] == 'R' && type[2] == 'N' && type[3] == 'S') {
      for (uint32_t i = 0; i < len && i < pal.size(); ++i) pal[i].a = body[i];
    } else if (type[0] == 'I' && type[1] == 'E' && type[2] == 'N' && type[3] == 'D') {
      break;
    }
    pos += len + 12;
  }
  return pal;
}

Torque::Gui::Image recolour_body(const Torque::Gui::Image& image, const std::vector<Color>& palette,
                                 const std::array<int, 5>& colors) {
  static const int slots[7] = {5, 6, 4, 3, 1, 0, 2};
  // Colour (as RGBA) -> replacement. The first entry with a colour wins,
  // as a decoded pixel cannot say which of two equal entries it came from.
  auto key = [](Color c) { return (uint32_t(c.r) << 24) | (uint32_t(c.g) << 16) | (uint32_t(c.b) << 8) | c.a; };
  std::map<uint32_t, Color> swap;
  for (int i = 0; i < 7; ++i) {
    size_t slot = static_cast<size_t>(slots[i]);
    if (slot >= palette.size()) continue;
    Color to = i < 5 ? player_colour(colors[static_cast<size_t>(i)]) : i == 5 ? player_colour(18) : Color{0, 0, 0, 0};
    swap.emplace(key(palette[slot]), to);
  }
  Torque::Gui::Image out = image;
  for (auto& px : out.pixels) {
    auto it = swap.find(key(px));
    if (it != swap.end()) px = it->second;
  }
  return out;
}

}  // namespace Quattro::Draw
