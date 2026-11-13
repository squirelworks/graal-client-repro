// A gmap (GRMAP001): a grid of level names that plays as one map.
//
// From Graal_analysis manual/03-formats/02-gmap.md: `WIDTH` and `HEIGHT`
// give the grid; a `LEVELNAMES` ... `LEVELNAMESEND` block lists one grid
// row per line of quoted, comma-separated names, row-major, lowercased for
// lookup. The DungeonGenerator's short form has no `LEVELNAMES` block: the
// grid is rebuilt from the bottom-right name in `GENERATED`, as
// `<prefix>_<column letter>-<1-based row>.graal` (the 4.04r2 install's
// levels/tutorial/offlinetutorial.gmap is one). `GENERATED 1` is the
// TerrainGenerator's flag, not a name. The other keys (heights, images,
// seeds) are not read here.
#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace Quattro::Files {

struct Gmap {
  int width = 0, height = 0;
  std::vector<std::string> names;  // row-major, lowercased; empty for a hole

  // The level at grid cell (x, y), or empty.
  std::string at(int x, int y) const {
    if (x < 0 || y < 0 || x >= width || y >= height) return {};
    return names[static_cast<size_t>(y * width + x)];
  }
  // The cell of a level name (any case). False when it is not on the map.
  bool find(const std::string& name, int& x, int& y) const;
};

// Parses a GRMAP001 file. False (with `error`) when the signature or the
// size is missing, or no level names can be found or rebuilt.
bool read_gmap(std::string_view data, Gmap& out, std::string& error);

}  // namespace Quattro::Files
