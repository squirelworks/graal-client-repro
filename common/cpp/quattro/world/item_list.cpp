#include "item_list.hpp"

#include <algorithm>
#include <climits>

namespace Quattro::World {

std::vector<ItemCell> layout_items(const WeaponList& list, int width, int height, const ImageSize& image,
                                   const TextWidth& text, int label_h) {
  std::vector<ItemCell> cells;
  const int right = width - kItemCellsRight, bottom = height - kItemCellsBottom;
  int x = kItemCellsLeft, y = kItemCellsTop, row_h = 0;
  const auto& ws = list.list();
  for (size_t i = 0; i < ws.size(); ++i) {
    if (hidden_weapon(ws[i].name)) continue;
    ItemCell c;
    c.index = static_cast<int>(i);
    auto [iw, ih] = ws[i].image.empty() ? std::pair<int, int>{0, 0} : image(ws[i].image);
    if (iw > 0 && ih > 0) {
      c.image_w = iw;
      c.image_h = ih;
    }
    c.label_w = text(ws[i].name);
    c.w = std::max(c.image_w, c.label_w) + 10;
    c.h = c.image_h + label_h + 15;
    if (x + c.w > right && x > kItemCellsLeft) {
      x = kItemCellsLeft;
      y += row_h;
      row_h = 0;
    }
    if (y + c.h > bottom) break;  // past the bottom: not drawn (no scroll arrows yet)
    c.x = x;
    c.y = y;
    x += c.w;
    row_h = std::max(row_h, c.h);
    cells.push_back(c);
  }
  return cells;
}

int move_in_items(const std::vector<ItemCell>& cells, int selected, int dir) {
  const ItemCell* from = nullptr;
  for (const auto& c : cells)
    if (c.index == selected) from = &c;
  if (!from) return cells.empty() ? -1 : cells.front().index;
  int best = -1, best_edge = INT_MAX;
  for (const auto& c : cells) {
    if (c.index == selected) continue;
    bool across_x = c.x < from->x + from->w && c.x + c.w > from->x;  // overlaps the column
    bool across_y = c.y < from->y + from->h && c.y + c.h > from->y;  // overlaps the row
    int edge = INT_MAX;
    switch (dir & 3) {
      case 0: if (across_x && c.y + c.h <= from->y) edge = from->y - (c.y + c.h); break;
      case 1: if (across_y && c.x + c.w <= from->x) edge = from->x - (c.x + c.w); break;
      case 2: if (across_x && c.y >= from->y + from->h) edge = c.y - (from->y + from->h); break;
      default: if (across_y && c.x >= from->x + from->w) edge = c.x - (from->x + from->w); break;
    }
    if (edge < best_edge) {
      best_edge = edge;
      best = c.index;
    }
  }
  return best;
}

}  // namespace Quattro::World
