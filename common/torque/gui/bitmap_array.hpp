// Splitting of theme bitmap arrays (common/ui/themes/*/*.png).
//
// A theme PNG packs several pieces (button corners and edges per state,
// window frame pieces, scroll arrows, check box states) into one image.
// The pieces are separated by lines in a separator colour, which is the
// colour of the top-left pixel. The rule below was read from the 31
// shipped 3.04 theme images in the lab (README.md lists the cell counts
// it yields):
//
//   - a row whose every pixel is the separator colour is a separator row;
//     each maximal run of other rows is a band;
//   - inside a band, a column whose every pixel (within the band) is the
//     separator colour is a separator column; each maximal run of other
//     columns is one cell;
//   - cells are numbered band by band from the top, left to right.
//
// Colours compare as exact RGBA8 values. A piece that is entirely the
// separator colour therefore disappears (the 3.04 text edit image has a
// separator-coloured centre and yields 8 cells, not 9). Whether a profile
// treats its bitmap as an array is the caller's choice (`hasBitmapArray`
// in the .th scripts); splitting a plain image just trims its separator-
// coloured margin.
#pragma once

#include "image.hpp"

#include <vector>

namespace Torque::Gui {

struct Rect {
  int x = 0, y = 0, width = 0, height = 0;
  bool empty() const { return width <= 0 || height <= 0; }
  bool operator==(const Rect& o) const {
    return x == o.x && y == o.y && width == o.width && height == o.height;
  }
};

struct BitmapArray {
  Color separator;
  std::vector<std::vector<Rect>> bands;  // cells per band, top to bottom
  std::vector<Rect> cells;               // all cells in reading order
};

BitmapArray split_bitmap_array(const Image& image);

}  // namespace Torque::Gui
