#include "bitmap_array.hpp"

namespace Torque::Gui {

BitmapArray split_bitmap_array(const Image& image) {
  BitmapArray result;
  if (image.empty()) return result;
  const Color sep = image.at(0, 0);
  result.separator = sep;

  std::vector<bool> separator_row(image.height, true);
  for (int y = 0; y < image.height; ++y)
    for (int x = 0; x < image.width && separator_row[y]; ++x)
      if (image.at(x, y) != sep) separator_row[y] = false;

  int y = 0;
  while (y < image.height) {
    if (separator_row[y]) { ++y; continue; }
    const int top = y;
    while (y < image.height && !separator_row[y]) ++y;
    const int bottom = y;

    std::vector<Rect> band;
    int x = 0;
    auto column_is_separator = [&](int cx) {
      for (int cy = top; cy < bottom; ++cy)
        if (image.at(cx, cy) != sep) return false;
      return true;
    };
    while (x < image.width) {
      if (column_is_separator(x)) { ++x; continue; }
      const int left = x;
      while (x < image.width && !column_is_separator(x)) ++x;
      // A cell shorter than its band keeps only its own rows: separator
      // rows at its top or bottom (within its columns) are cut off.
      auto row_is_separator = [&](int ry) {
        for (int rx = left; rx < x; ++rx)
          if (image.at(rx, ry) != sep) return false;
        return true;
      };
      int cell_top = top, cell_bottom = bottom;
      while (row_is_separator(cell_top)) ++cell_top;        // the band has a non-separator row
      while (row_is_separator(cell_bottom - 1)) --cell_bottom;
      band.push_back({left, cell_top, x - left, cell_bottom - cell_top});
    }
    result.cells.insert(result.cells.end(), band.begin(), band.end());
    result.bands.push_back(std::move(band));
  }
  return result;
}

}  // namespace Torque::Gui
