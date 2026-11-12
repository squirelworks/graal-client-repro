// Player colours on the body image. The body PNG is a palette image; five
// of its entries are the player's colours and one is the outline. Which
// entries, and the 20 colours a player can pick, are the ones the Pascal
// clients use (graal-*/src/Adventure.pas, BodyFor and ColorTable): entry 5
// skin, 6 coat, 4 sleeves, 3 shoes, 1 belt, 0 the outline (colour 18), and
// 2 the clear colour. Whether 6.x keeps the same entries was not seen in a
// lab; it reads the same body.png.
#pragma once

#include "../../../torque/gui/image.hpp"

#include <array>
#include <cstdint>
#include <vector>

namespace Quattro::Draw {

// The 20 player colours, index 0..19 (white, yellow, orange, pink, red,
// darkred, lightgreen, green, darkgreen, lightblue, blue, darkblue, brown,
// cynober, purple, darkpurple, lightgray, gray, black, transparent).
Torque::Gui::Color player_colour(int index);

// The PLTE entries of a PNG (with tRNS alpha), or empty when it has none.
std::vector<Torque::Gui::Color> png_palette(const std::vector<std::uint8_t>& png);

// `image` decoded from a palette PNG with `palette`: each pixel whose
// colour is a recoloured entry takes the player's colour.
Torque::Gui::Image recolour_body(const Torque::Gui::Image& image, const std::vector<Torque::Gui::Color>& palette,
                                 const std::array<int, 5>& colors);

}  // namespace Quattro::Draw
