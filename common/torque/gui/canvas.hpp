// Software GuiCanvas surface.
//
// A plain RGBA8 frame buffer with a clip stack and the drawing primitives
// the stock controls need: filled and framed rectangles, bitmap blits
// (straight, stretched and tiled) and `.gft` text. It has no window, no
// OpenGL device and no console object; the later GuiCanvas sim object
// owns one of these and presents it through the host. 3.04 draws through
// OpenGL (Graal_analysis torque/study-torque-clients.md section 3), so the
// pixels here are the rebuild's own rasterisation, checked against the
// stage 0 screenshot rather than taken from the original renderer.
//
// Blending is straight-alpha "source over": out = src * a + dst * (1 - a),
// rounded to nearest. Text is drawn by scaling the colour's alpha by the
// glyph coverage. These are rebuild policy.
#pragma once

#include "bitmap_array.hpp"
#include "gft.hpp"
#include "image.hpp"

#include <string_view>
#include <vector>

namespace Torque::Gui {

Rect intersect(const Rect& a, const Rect& b);

class Canvas {
 public:
  Canvas(int width, int height, Color clear = {0, 0, 0, 255});

  int width() const { return surface_.width; }
  int height() const { return surface_.height; }
  const Image& surface() const { return surface_; }

  // The clip starts as the whole surface. push_clip intersects with the
  // current clip; pop_clip restores the previous one and never pops the
  // surface clip.
  void push_clip(const Rect& rect);
  void pop_clip();
  const Rect& clip() const { return clips_.back(); }

  void clear(Color color);  // ignores the clip
  void blend_pixel(int x, int y, Color color);
  void fill_rect(const Rect& rect, Color color);
  void frame_rect(const Rect& rect, Color color);  // one-pixel outline

  // Draw `src` (a region of `image`) with its top-left at (x, y).
  void blit(const Image& image, const Rect& src, int x, int y);
  void blit(const Image& image, int x, int y);
  // Nearest-neighbour scale of `src` to fill `dst`.
  void stretch_blit(const Image& image, const Rect& src, const Rect& dst);
  // Repeat `src` from the top-left of `dst`, cut at its right and bottom.
  void tile_blit(const Image& image, const Rect& src, const Rect& dst);

  // Draws `text` with the top of the line at (x, y). Returns the pen x
  // after the last character. Characters with no glyph are skipped.
  int draw_text(const GftFont& font, int x, int y, std::string_view text, Color color);

 private:
  Image surface_;
  std::vector<Rect> clips_;
};

}  // namespace Torque::Gui
