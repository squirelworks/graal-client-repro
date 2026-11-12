// Independent checks for the GUI foundations. Every fixture is written by
// hand here: PNG chunks use stored (uncompressed) deflate blocks, so no
// encoder under test produces the input. No original Graal file is used;
// the owner-supplied 3.04 files are checked by tests/lab_check.sh instead.
#include "../bitmap_array.hpp"
#include "../canvas.hpp"
#include "../gft.hpp"
#include "../image.hpp"

#include <zlib.h>

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

using namespace Torque::Gui;
using Bytes = std::vector<std::uint8_t>;

namespace {

int failures = 0;
void require(bool condition, const char* message) {
  if (!condition) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}

void be32(Bytes& out, std::uint32_t v) {
  for (int s = 24; s >= 0; s -= 8) out.push_back(std::uint8_t(v >> s));
}
void le32(Bytes& out, std::uint32_t v) {
  for (int s = 0; s < 32; s += 8) out.push_back(std::uint8_t(v >> s));
}
void chunk(Bytes& out, const char* type, const Bytes& body) {
  be32(out, std::uint32_t(body.size()));
  std::size_t start = out.size();
  out.insert(out.end(), type, type + 4);
  out.insert(out.end(), body.begin(), body.end());
  be32(out, crc32(crc32(0, nullptr, 0), out.data() + start, uInt(body.size() + 4)));
}
// zlib stream holding one stored deflate block.
Bytes stored(const Bytes& raw) {
  Bytes z = {0x78, 0x01, 0x01};
  std::uint16_t n = std::uint16_t(raw.size());
  z.insert(z.end(), {std::uint8_t(n), std::uint8_t(n >> 8), std::uint8_t(~n), std::uint8_t(~n >> 8)});
  z.insert(z.end(), raw.begin(), raw.end());
  be32(z, adler32(adler32(0, nullptr, 0), raw.data(), uInt(raw.size())));
  return z;
}
Bytes png(std::uint32_t w, std::uint32_t h, int depth, int type, const Bytes& raw,
          const Bytes& plte = {}, const Bytes& trns = {}, int interlace = 0) {
  Bytes out = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
  Bytes ihdr;
  be32(ihdr, w);
  be32(ihdr, h);
  ihdr.insert(ihdr.end(), {std::uint8_t(depth), std::uint8_t(type), 0, 0, std::uint8_t(interlace)});
  chunk(out, "IHDR", ihdr);
  if (!plte.empty()) chunk(out, "PLTE", plte);
  if (!trns.empty()) chunk(out, "tRNS", trns);
  chunk(out, "IDAT", stored(raw));
  chunk(out, "IEND", {});
  return out;
}
bool same(const Color& c, int r, int g, int b, int a) {
  return c.r == r && c.g == g && c.b == b && c.a == a;
}
bool rejects(const Bytes& bytes) {
  Image image(1, 1, {9, 9, 9, 9});
  std::string error;
  bool ok = decode_png(bytes, image, error);
  return !ok && !error.empty() && image.width == 1 && same(image.at(0, 0), 9, 9, 9, 9);
}

void test_png() {
  // 3x3 gray, rows filtered sub / paeth / up+avg checked by hand.
  Bytes filtered = png(3, 2, 8, 0, {1, 10, 5, 5, 4, 1, 1, 1});
  Image image;
  std::string error;
  require(decode_png(filtered, image, error), "gray PNG decodes");
  require(image.width == 3 && image.height == 2, "gray size");
  require(same(image.at(0, 0), 10, 10, 10, 255) && same(image.at(2, 0), 20, 20, 20, 255), "sub filter");
  require(image.at(0, 1).r == 11 && image.at(1, 1).r == 16 && image.at(2, 1).r == 21, "paeth filter");

  Bytes avg = png(2, 3, 8, 0, {0, 100, 50, 3, 0, 0, 2, 1, 2});
  require(decode_png(avg, image, error), "avg/up PNG decodes");
  require(image.at(0, 1).r == 50 && image.at(1, 1).r == 50, "average filter");
  require(image.at(0, 2).r == 51 && image.at(1, 2).r == 52, "up filter");

  // 2-bit palette: indices 2,1,0 packed high bits first; tRNS on two entries.
  Bytes pal = png(3, 1, 2, 3, {0, 0x90}, {255, 0, 0, 0, 255, 0, 0, 0, 255}, {255, 128});
  require(decode_png(pal, image, error), "palette PNG decodes");
  require(same(image.at(0, 0), 0, 0, 255, 255), "palette index 2");
  require(same(image.at(1, 0), 0, 255, 0, 128), "palette index 1 with tRNS alpha");
  require(same(image.at(2, 0), 255, 0, 0, 255), "palette index 0 with tRNS alpha");

  // 4-bit gray scales to 8 bits.
  require(decode_png(png(2, 1, 4, 0, {0, 0xf5}), image, error), "4-bit gray decodes");
  require(image.at(0, 0).r == 255 && image.at(1, 0).r == 85, "4-bit gray scaling");

  // 16-bit RGB keeps the high byte; a matching tRNS key is transparent.
  Bytes rgb16 = png(2, 1, 16, 2, {0, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 1, 2, 3, 4, 5, 6},
                    {}, {0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc});
  require(decode_png(rgb16, image, error), "16-bit RGB decodes");
  require(same(image.at(0, 0), 0x12, 0x56, 0x9a, 0), "16-bit RGB keyed pixel");
  require(same(image.at(1, 0), 1, 3, 5, 255), "16-bit RGB opaque pixel");

  require(decode_png(png(1, 1, 8, 6, {0, 1, 2, 3, 4}), image, error), "RGBA decodes");
  require(same(image.at(0, 0), 1, 2, 3, 4), "RGBA value");
  require(decode_png(png(1, 1, 8, 4, {0, 7, 8}), image, error), "gray-alpha decodes");
  require(same(image.at(0, 0), 7, 7, 7, 8), "gray-alpha value");

  // Back-to-back streams report how much each one used.
  Bytes two = filtered;
  two.insert(two.end(), avg.begin(), avg.end());
  std::size_t used = 0;
  require(decode_png(two.data(), two.size(), image, error, &used) && used == filtered.size(),
          "consumed length of a packed stream");
  require(rejects(two), "bytes after IEND rejected by the whole-file reader");

  Bytes bad_crc = filtered;
  bad_crc[30] ^= 1;
  require(rejects(bad_crc), "bad CRC rejected");
  require(rejects(png(1, 1, 8, 0, {0, 1}, {}, {}, 1)), "interlaced rejected");
  require(rejects(png(1, 1, 8, 0, {0, 1, 2})), "extra image data rejected");
  require(rejects(png(1, 1, 8, 0, {0})), "short image data rejected");
  require(rejects(png(1, 1, 8, 0, {5, 1})), "unknown filter rejected");
  require(rejects(png(1, 1, 3, 0, {0, 0})), "bad depth rejected");
  require(rejects(png(2, 1, 8, 3, {0, 0, 1}, {1, 2, 3})), "palette index out of range rejected");
  require(rejects(png(1, 1, 8, 3, {0, 0})), "palette image without PLTE rejected");
  require(rejects(png(0, 1, 8, 0, {})), "zero width rejected");
  {
    Bytes unknown = png(1, 1, 8, 0, {0, 1});
    Bytes head(unknown.begin(), unknown.begin() + 33);  // signature and IHDR
    chunk(head, "QUUX", {1});                           // critical: first letter upper case
    head.insert(head.end(), unknown.begin() + 33, unknown.end());
    require(rejects(head), "unknown critical chunk rejected");
    Bytes ancillary(unknown.begin(), unknown.begin() + 33);
    chunk(ancillary, "quux", {1});
    ancillary.insert(ancillary.end(), unknown.begin() + 33, unknown.end());
    require(decode_png(ancillary, image, error), "unknown ancillary chunk skipped");
  }
  for (std::size_t n = 0; n < filtered.size(); ++n)
    if (!rejects(Bytes(filtered.begin(), filtered.begin() + n))) {
      require(false, "truncated PNG accepted");
      break;
    }
}

// Sheet: 4x3 gray. Glyph 'A' covers x 1..2 on all three rows.
Bytes sheet() {
  return png(4, 3, 8, 0, {0, 0, 255, 0, 0, 0, 0, 255, 128, 0, 0, 0, 0, 255, 0});
}
Bytes gft_fixture() {
  Bytes out;
  le32(out, 1);  // version
  le32(out, 4);  // height
  le32(out, 3);  // baseline
  le32(out, 2);  // glyphs
  out.insert(out.end(), {0, 0, 0, 0, 0, 0, 0, 0, 2});           // space: advance 2
  out.insert(out.end(), {0, 0, 1, 0, 2, 3, 0xff, 3, 3});        // A: x origin -1
  le32(out, 1);  // sheets
  Bytes s = sheet();
  out.insert(out.end(), s.begin(), s.end());
  for (int c = 0; c < 256; ++c) {
    std::uint16_t v = c == ' ' ? 0 : c == 'A' ? 1 : 0xffff;
    out.push_back(std::uint8_t(v));
    out.push_back(std::uint8_t(v >> 8));
  }
  return out;
}
bool gft_rejects(const Bytes& bytes) {
  GftFont font;
  font.height = 77;
  std::string error;
  return !load_gft(bytes, font, error) && !error.empty() && font.height == 77;
}

void test_gft() {
  Bytes bytes = gft_fixture();
  GftFont font;
  std::string error;
  require(load_gft(bytes, font, error), "fixture font loads");
  require(font.version == 1 && font.height == 4 && font.baseline == 3, "header fields");
  require(font.glyphs.size() == 2 && font.sheets.size() == 1, "glyph and sheet counts");
  const GftGlyph* a = font.glyph('A');
  require(a && a->x == 1 && a->width == 2 && a->height == 3 && a->x_origin == -1 &&
              a->y_origin == 3 && a->x_advance == 3, "glyph fields, signed x origin");
  require(font.glyph('B') == nullptr && font.glyph(0) == nullptr, "unmapped characters");
  require(font.text_width("A A") == 8 && font.text_width("ABA") == 6, "text width skips missing glyphs");
  require(a && font.coverage(*a, 1, 1) == 128 && font.coverage(*a, 2, 0) == 0, "coverage");
  require(gft_cache_name("Arial Bold", 14) == "Arial Bold_14.gft", "cache file name");

  Bytes bad = bytes;
  bad[0] = 2;
  require(gft_rejects(bad), "version 2 rejected");
  bad = bytes;
  bad[8] = 5;
  require(gft_rejects(bad), "baseline below line rejected");
  bad = bytes;
  bad[16 + 9 + 4] = 3;  // width 3 from x 1 ends exactly at the 4-pixel sheet edge
  require(!gft_rejects(bad), "glyph touching the sheet edge accepted");
  bad[16 + 9 + 4] = 4;
  require(gft_rejects(bad), "glyph outside its sheet rejected");
  bad = bytes;
  bad[16 + 9] = 1;
  require(gft_rejects(bad), "glyph on a missing sheet rejected");
  bad = bytes;
  bad[bytes.size() - 512 + 2 * 'A'] = 2;
  require(gft_rejects(bad), "character map past glyph table rejected");
  bad = bytes;
  bad.push_back(0);
  require(gft_rejects(bad), "trailing byte rejected");
  for (std::size_t n = 0; n < bytes.size(); ++n)
    if (!gft_rejects(Bytes(bytes.begin(), bytes.begin() + n))) {
      require(false, "truncated font accepted");
      break;
    }
}

void test_bitmap_array() {
  const Color s{255, 0, 255, 255}, p{10, 20, 30, 255}, t{0, 0, 0, 0};
  Image image(7, 7, p);
  for (int x = 0; x < 7; ++x) image.at(x, 0) = image.at(x, 4) = s;  // separator rows
  for (int y = 1; y < 4; ++y) image.at(3, y) = s;                   // column split in band 1
  image.at(5, 1) = s;                                               // stray separator pixel
  image.at(0, 2) = t;
  for (int y = 5; y < 7; ++y) image.at(6, y) = s;                   // margin in band 2
  BitmapArray array = split_bitmap_array(image);
  require(array.separator == s, "separator is the top-left pixel");
  require(array.bands.size() == 2, "two bands");
  require(array.cells.size() == 3, "three cells");
  require(array.cells.size() == 3 && array.cells[0] == Rect{0, 1, 3, 3} &&
              array.cells[1] == Rect{4, 1, 3, 3} && array.cells[2] == Rect{0, 5, 6, 2},
          "cell rectangles");
  require(split_bitmap_array(Image()).cells.empty(), "empty image has no cells");
  require(split_bitmap_array(Image(3, 3, s)).cells.empty(), "all-separator image has no cells");
}

void test_canvas() {
  const Color black{0, 0, 0, 255}, red{255, 0, 0, 255};
  Canvas canvas(8, 4, black);
  canvas.fill_rect({-2, -2, 4, 4}, {0, 0, 255, 128});
  require(same(canvas.surface().at(1, 1), 0, 0, 128, 255), "fill blends and clips at the edge");
  require(same(canvas.surface().at(2, 2), 0, 0, 0, 255), "fill stays inside its rectangle");

  canvas.clear(black);
  canvas.push_clip({2, 0, 3, 4});
  canvas.fill_rect({0, 0, 8, 1}, red);
  require(same(canvas.surface().at(1, 0), 0, 0, 0, 255) && same(canvas.surface().at(2, 0), 255, 0, 0, 255) &&
              same(canvas.surface().at(5, 0), 0, 0, 0, 255), "clip limits fill");
  canvas.push_clip({4, 0, 4, 4});
  require(canvas.clip() == Rect{4, 0, 1, 4}, "nested clip intersects");
  canvas.pop_clip();
  canvas.pop_clip();
  canvas.pop_clip();
  require(canvas.clip() == Rect{0, 0, 8, 4}, "surface clip is never popped");

  canvas.clear(black);
  canvas.frame_rect({1, 1, 3, 3}, red);
  require(same(canvas.surface().at(1, 1), 255, 0, 0, 255) && same(canvas.surface().at(3, 3), 255, 0, 0, 255) &&
              same(canvas.surface().at(2, 2), 0, 0, 0, 255), "frame leaves the inside");

  Image src(2, 2);
  src.at(0, 0) = {1, 0, 0, 255};
  src.at(1, 0) = {2, 0, 0, 255};
  src.at(0, 1) = {3, 0, 0, 255};
  src.at(1, 1) = {4, 0, 0, 0};
  canvas.clear(black);
  canvas.blit(src, -1, 0);
  require(canvas.surface().at(0, 0).r == 2 && canvas.surface().at(0, 1).r == 0, "blit clips and skips clear pixels");
  canvas.blit(src, {-1, -1, 3, 3}, 4, 0);
  require(canvas.surface().at(5, 1).r == 1, "blit keeps alignment when the source rect is cut");

  canvas.clear(black);
  canvas.stretch_blit(src, {0, 0, 2, 1}, {0, 0, 4, 2});
  require(canvas.surface().at(1, 1).r == 1 && canvas.surface().at(2, 0).r == 2 &&
              canvas.surface().at(3, 1).r == 2, "nearest-neighbour stretch");
  canvas.clear(black);
  canvas.tile_blit(src, {0, 0, 2, 1}, {1, 1, 5, 2});
  require(canvas.surface().at(1, 2).r == 1 && canvas.surface().at(4, 1).r == 2 &&
              canvas.surface().at(5, 2).r == 1 && canvas.surface().at(6, 1).r == 0 &&
              canvas.surface().at(1, 3).r == 0, "tiles repeat and stop at the rectangle");

  GftFont font;
  std::string error;
  require(load_gft(gft_fixture(), font, error), "font for text");
  canvas.clear(black);
  int end = canvas.draw_text(font, 2, 0, " A", red);
  require(end == 7, "pen advances");
  // Pen at 4 after the space; x origin -1 puts the glyph at column 3.
  require(same(canvas.surface().at(3, 0), 255, 0, 0, 255) && same(canvas.surface().at(3, 1), 255, 0, 0, 255),
          "full-coverage glyph pixels");
  require(same(canvas.surface().at(4, 1), 128, 0, 0, 255), "partial coverage blends");
  require(same(canvas.surface().at(4, 0), 0, 0, 0, 255) && same(canvas.surface().at(4, 2), 255, 0, 0, 255),
          "glyph rows sit on the baseline");

  Image back;
  require(decode_png(encode_png(canvas.surface()), back, error) && back.pixels == canvas.surface().pixels,
          "canvas capture round-trips through PNG");
}

}  // namespace

int main() {
  test_png();
  test_gft();
  test_bitmap_array();
  test_canvas();
  if (failures) {
    std::cerr << failures << " check(s) failed\n";
    return 1;
  }
  std::cout << "gui tests passed\n";
  return 0;
}
