// gui-inspect: look at owner-supplied 3.04 GUI files without running a client.
//
//   gui-inspect font  FILE.gft                 header, sheets, mapped characters
//   gui-inspect array FILE.png                 separator colour and cells
//   gui-inspect text  FILE.gft TEXT OUT.png    draw TEXT white on black
//   gui-inspect match FILE.gft TEXT SHOT.png X Y
//       Draw TEXT with the line top at (X, Y) of a screenshot and print the
//       two fractions over the text box:
//         mask   pixels where the glyph mask (coverage above 100) agrees with
//                the screenshot thresholded at the midpoint of the box's
//                darkest and brightest luminance;
//         exact  pixels within one level per channel of the text composited
//                by Canvas::draw_text, in the box's brightest colour, over a
//                flat fill of its darkest colour. Only meaningful where the
//                screenshot background behind the text is flat.
#include "bitmap_array.hpp"
#include "canvas.hpp"
#include "gft.hpp"
#include "image.hpp"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>

using namespace Torque::Gui;

namespace {

int usage() {
  std::cerr << "usage: gui-inspect font FILE.gft\n"
               "       gui-inspect array FILE.png\n"
               "       gui-inspect text FILE.gft TEXT OUT.png\n"
               "       gui-inspect match FILE.gft TEXT SHOT.png X Y\n"
               "       gui-inspect compare A.png B.png X Y W H\n";
  return 2;
}

bool load_font(const std::string& path, GftFont& font) {
  std::vector<std::uint8_t> bytes;
  std::string error;
  if (!read_file(path, bytes, error) || !load_gft(bytes, font, error)) {
    std::cerr << path << ": " << error << '\n';
    return false;
  }
  return true;
}

bool load_image(const std::string& path, Image& image) {
  std::vector<std::uint8_t> bytes;
  std::string error;
  if (!read_file(path, bytes, error) || !decode_png(bytes, image, error)) {
    std::cerr << path << ": " << error << '\n';
    return false;
  }
  return true;
}

int luminance(const Color& c) { return c.r + c.g + c.b; }

}  // namespace

int main(int argc, char** argv) {
  if (argc < 3) return usage();
  const std::string command = argv[1];

  if (command == "font" && argc == 3) {
    GftFont font;
    if (!load_font(argv[2], font)) return 1;
    int mapped = 0;
    for (unsigned c = 0; c < 256; ++c) mapped += font.glyph(static_cast<unsigned char>(c)) != nullptr;
    std::printf("version %u height %u baseline %u glyphs %zu mapped %d sheets %zu\n", font.version,
                font.height, font.baseline, font.glyphs.size(), mapped, font.sheets.size());
    for (std::size_t i = 0; i < font.sheets.size(); ++i)
      std::printf("sheet %zu %dx%d\n", i, font.sheets[i].width, font.sheets[i].height);
    return 0;
  }

  if (command == "array" && argc == 3) {
    Image image;
    if (!load_image(argv[2], image)) return 1;
    BitmapArray array = split_bitmap_array(image);
    const Color& s = array.separator;
    std::printf("size %dx%d separator %d %d %d %d cells %zu bands %zu\n", image.width, image.height,
                s.r, s.g, s.b, s.a, array.cells.size(), array.bands.size());
    for (std::size_t b = 0; b < array.bands.size(); ++b) {
      std::printf("band %zu:", b);
      for (const Rect& r : array.bands[b]) std::printf(" %d,%d %dx%d", r.x, r.y, r.width, r.height);
      std::printf("\n");
    }
    return 0;
  }

  if (command == "text" && argc == 5) {
    GftFont font;
    if (!load_font(argv[2], font)) return 1;
    const std::string text = argv[3];
    Canvas canvas(std::max(1, font.text_width(text)), int(font.height));
    canvas.draw_text(font, 0, 0, text, {255, 255, 255, 255});
    std::string error;
    if (!write_file(argv[4], encode_png(canvas.surface()), error)) {
      std::cerr << error << '\n';
      return 1;
    }
    return 0;
  }

  if (command == "match" && argc == 7) {
    GftFont font;
    Image shot;
    if (!load_font(argv[2], font) || !load_image(argv[4], shot)) return 1;
    const std::string text = argv[3];
    const int x0 = std::atoi(argv[5]), y0 = std::atoi(argv[6]);
    const int w = font.text_width(text), h = int(font.height);
    if (w <= 0 || x0 < 0 || y0 < 0 || x0 + w > shot.width || y0 + h > shot.height) {
      std::cerr << "text box outside screenshot\n";
      return 1;
    }
    Canvas mask(w, h, {0, 0, 0, 255});
    mask.draw_text(font, 0, 0, text, {255, 255, 255, 255});
    int lo = 765, hi = 0;
    Color dark, bright;
    for (int y = 0; y < h; ++y)
      for (int x = 0; x < w; ++x) {
        const Color& c = shot.at(x0 + x, y0 + y);
        int l = luminance(c);
        if (l < lo) { lo = l; dark = c; }
        if (l > hi) { hi = l; bright = c; }
      }
    Canvas composed(w, h, dark);
    composed.draw_text(font, 0, 0, text, bright);
    const double threshold = (lo + hi) / 2.0;
    int agree = 0, exact = 0;
    for (int y = 0; y < h; ++y)
      for (int x = 0; x < w; ++x) {
        const Color& s = shot.at(x0 + x, y0 + y);
        bool ink = mask.surface().at(x, y).r > 100;
        bool lit = luminance(s) > threshold;
        agree += ink == lit;
        const Color& c = composed.surface().at(x, y);
        exact += std::abs(c.r - s.r) <= 1 && std::abs(c.g - s.g) <= 1 && std::abs(c.b - s.b) <= 1;
      }
    std::printf("mask %.4f exact %.4f\n", double(agree) / (w * h), double(exact) / (w * h));
    return 0;
  }
  if (command == "compare" && argc == 8) {
    // Share of pixels in a box where two images agree within one level per
    // channel (the rendered menu against the stage 0 screenshot).
    Image a, b;
    if (!load_image(argv[2], a) || !load_image(argv[3], b)) return 1;
    const int x0 = std::atoi(argv[4]), y0 = std::atoi(argv[5]);
    const int w = std::atoi(argv[6]), h = std::atoi(argv[7]);
    if (w <= 0 || h <= 0 || x0 < 0 || y0 < 0 || x0 + w > std::min(a.width, b.width) ||
        y0 + h > std::min(a.height, b.height)) {
      std::cerr << "box outside the images\n";
      return 1;
    }
    long exact = 0;
    for (int y = y0; y < y0 + h; ++y)
      for (int x = x0; x < x0 + w; ++x) {
        const Color &p = a.at(x, y), &q = b.at(x, y);
        exact += std::abs(p.r - q.r) <= 1 && std::abs(p.g - q.g) <= 1 && std::abs(p.b - q.b) <= 1;
      }
    std::printf("exact %.4f\n", double(exact) / (double(w) * h));
    return 0;
  }
  return usage();
}
