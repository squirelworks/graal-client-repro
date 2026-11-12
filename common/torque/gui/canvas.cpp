#include "canvas.hpp"

#include <algorithm>

namespace Torque::Gui {

Rect intersect(const Rect& a, const Rect& b) {
  int left = std::max(a.x, b.x), top = std::max(a.y, b.y);
  int right = std::min(a.x + a.width, b.x + b.width);
  int bottom = std::min(a.y + a.height, b.y + b.height);
  if (right <= left || bottom <= top) return {left, top, 0, 0};
  return {left, top, right - left, bottom - top};
}

namespace {
std::uint8_t mix(int src, int dst, int alpha) {
  return std::uint8_t((src * alpha + dst * (255 - alpha) + 127) / 255);
}
bool inside(const Rect& r, int x, int y) {
  return x >= r.x && y >= r.y && x < r.x + r.width && y < r.y + r.height;
}
}  // namespace

Canvas::Canvas(int width, int height, Color clear_color)
    : surface_(std::max(width, 0), std::max(height, 0), clear_color),
      clips_{{0, 0, std::max(width, 0), std::max(height, 0)}} {}

void Canvas::push_clip(const Rect& rect) { clips_.push_back(intersect(clips_.back(), rect)); }

void Canvas::pop_clip() {
  if (clips_.size() > 1) clips_.pop_back();
}

void Canvas::clear(Color color) { std::fill(surface_.pixels.begin(), surface_.pixels.end(), color); }

void Canvas::blend_pixel(int x, int y, Color c) {
  if (!inside(clip(), x, y) || c.a == 0) return;
  Color& d = surface_.at(x, y);
  if (c.a == 255) { d = c; return; }
  d = {mix(c.r, d.r, c.a), mix(c.g, d.g, c.a), mix(c.b, d.b, c.a), mix(255, d.a, c.a)};
}

void Canvas::fill_rect(const Rect& rect, Color color) {
  Rect r = intersect(rect, clip());
  for (int y = r.y; y < r.y + r.height; ++y)
    for (int x = r.x; x < r.x + r.width; ++x) blend_pixel(x, y, color);
}

void Canvas::frame_rect(const Rect& rect, Color color) {
  if (rect.empty()) return;
  fill_rect({rect.x, rect.y, rect.width, 1}, color);
  if (rect.height > 1) fill_rect({rect.x, rect.y + rect.height - 1, rect.width, 1}, color);
  if (rect.height > 2) {
    fill_rect({rect.x, rect.y + 1, 1, rect.height - 2}, color);
    if (rect.width > 1) fill_rect({rect.x + rect.width - 1, rect.y + 1, 1, rect.height - 2}, color);
  }
}

void Canvas::blit(const Image& image, const Rect& src, int x, int y) {
  Rect s = intersect(src, {0, 0, image.width, image.height});
  if (s.empty()) return;
  // Keep the destination aligned with the requested source origin.
  x += s.x - src.x;
  y += s.y - src.y;
  Rect d = intersect({x, y, s.width, s.height}, clip());
  for (int dy = d.y; dy < d.y + d.height; ++dy)
    for (int dx = d.x; dx < d.x + d.width; ++dx)
      blend_pixel(dx, dy, image.at(s.x + dx - x, s.y + dy - y));
}

void Canvas::blit(const Image& image, int x, int y) { blit(image, {0, 0, image.width, image.height}, x, y); }

void Canvas::stretch_blit(const Image& image, const Rect& src, const Rect& dst) {
  Rect s = intersect(src, {0, 0, image.width, image.height});
  if (s.empty() || dst.empty() || !(s == src)) return;
  Rect d = intersect(dst, clip());
  for (int dy = d.y; dy < d.y + d.height; ++dy) {
    int sy = s.y + int((long long)(dy - dst.y) * s.height / dst.height);
    for (int dx = d.x; dx < d.x + d.width; ++dx) {
      int sx = s.x + int((long long)(dx - dst.x) * s.width / dst.width);
      blend_pixel(dx, dy, image.at(sx, sy));
    }
  }
}

void Canvas::tile_blit(const Image& image, const Rect& src, const Rect& dst) {
  Rect s = intersect(src, {0, 0, image.width, image.height});
  if (s.empty() || dst.empty() || !(s == src)) return;
  push_clip(dst);
  for (int y = dst.y; y < dst.y + dst.height; y += s.height)
    for (int x = dst.x; x < dst.x + dst.width; x += s.width) blit(image, s, x, y);
  pop_clip();
}

int Canvas::draw_text(const GftFont& font, int x, int y, std::string_view text, Color color) {
  for (char ch : text) {
    const GftGlyph* g = font.glyph(static_cast<unsigned char>(ch));
    if (!g) continue;
    const int left = x + g->x_origin;
    const int top = y + int(font.baseline) - g->y_origin;
    for (int gy = 0; gy < g->height; ++gy)
      for (int gx = 0; gx < g->width; ++gx) {
        int cover = font.coverage(*g, gx, gy);
        if (!cover) continue;
        Color c = color;
        c.a = std::uint8_t((color.a * cover + 127) / 255);
        blend_pixel(left + gx, top + gy, c);
      }
    x += g->x_advance;
  }
  return x;
}

}  // namespace Torque::Gui
