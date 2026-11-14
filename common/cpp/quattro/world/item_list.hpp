// The item list (Q): a window of weapon cells, laid out and moved through
// as 2.05 does (Graal_analysis manual/04-behaviour/06-hud-ui.md, "The item
// list"; client-internals/decomp-findings-2026-10-28/02-item-list.md):
// - the window is framed from (16, 80) to 16 px from the right and bottom
//   edges; the cells go from (48, 112) to 48 px from the right and 64 px
//   from the bottom;
// - a cell is max(image width, label width) + 10 wide and image height +
//   label height + 15 tall, packed left to right then down; the image is
//   centred 5 px from the top and the label centred below it; a weapon
//   with no image gets a 32 x 32 place; the selected cell is filled
//   RGB(255, 212, 128); text size 16;
// - an arrow stretches the selected cell to the edge in its direction and
//   takes the overlapping cell with the closest near edge, selecting it at
//   once (nothing is sent);
// - Delete removes the selected weapon (29 NPCWEAPONDEL with the name);
//   Esc, the item key and the other game keys close the list.
// Weapons whose name starts with '-' are not in the list.
//
// On 6.x servers the item list is usually a GS2 GUI script the server sends
// (Graal_analysis protocol/v6x-clients.md); this window is what the client
// shows itself. Folders ('/' in a name) and the scroll arrows are not
// drawn yet; cells past the bottom are left out.
#pragma once

#include "weapons.hpp"

#include <functional>
#include <utility>
#include <vector>

namespace Quattro::World {

struct ItemCell {
  int index = 0;            // in the weapon list
  int x = 0, y = 0, w = 0, h = 0;
  int image_w = 32, image_h = 32;
  int label_w = 0;
};

// Image size by file name ({0, 0}: none); label width by text.
using ImageSize = std::function<std::pair<int, int>(const std::string&)>;
using TextWidth = std::function<int(const std::string&)>;

std::vector<ItemCell> layout_items(const WeaponList& list, int width, int height, const ImageSize& image,
                                   const TextWidth& text, int label_h = 16);

// The cell an arrow (0 up, 1 left, 2 down, 3 right) moves to from the
// selected weapon's cell; -1 when there is none that way.
int move_in_items(const std::vector<ItemCell>& cells, int selected, int dir);

constexpr int kItemWindowLeft = 16, kItemWindowTop = 80, kItemWindowMargin = 16;
constexpr int kItemCellsLeft = 48, kItemCellsTop = 112, kItemCellsRight = 48, kItemCellsBottom = 64;

}  // namespace Quattro::World
