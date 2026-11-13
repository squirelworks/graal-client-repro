// Checks for the profile reader and the stock control renderer. Every input
// is built here: the bitmap arrays and the font are small synthetic images
// written to a temporary install folder, and the control tree is created
// on the console engine directly. No original Graal file is used; the 3.04
// main menu is checked against the stage 0 screenshot by tests/lab_check.sh.
#include "../canvas.hpp"
#include "../profile.hpp"
#include "../jpeg.hpp"
#include "../mouse.hpp"
#include "../render.hpp"
#include "../system_font.hpp"
#include "../../console/engine/engine.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <iostream>
#include <random>
#include <string>
#include <vector>

using namespace Torque;
using namespace Torque::Gui;
namespace fs = std::filesystem;
using Bytes = std::vector<std::uint8_t>;

namespace {

int failures = 0;
void require(bool condition, const std::string& message) {
  if (!condition) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}
bool same(const Color& c, int r, int g, int b, int a = 255) {
  return c.r == r && c.g == g && c.b == b && c.a == a;
}
std::string show(const Color& c) {
  return std::to_string(c.r) + " " + std::to_string(c.g) + " " + std::to_string(c.b) + " " + std::to_string(c.a);
}

void le32(Bytes& out, std::uint32_t v) {
  for (int s = 0; s < 32; s += 8) out.push_back(std::uint8_t(v >> s));
}

const Color kSep{255, 0, 255, 255};

// A bitmap array of `bands` x `per_band` cells of `cell` x `cell` pixels,
// one pixel of separator between cells and a separator row on top (the
// top-left pixel names the separator). Cell (b, c) is colour_of(b, c).
Color colour_of(int band, int col) { return {std::uint8_t(band * 20), std::uint8_t(col * 80), 100, 255}; }
Image make_array(int bands, int per_band, int cell, bool hole_centre = false) {
  Image image(per_band * (cell + 1) - 1, bands * (cell + 1), kSep);
  for (int b = 0; b < bands; ++b)
    for (int c = 0; c < per_band; ++c) {
      if (hole_centre && b == 1 && c == 1) continue;
      for (int y = 0; y < cell; ++y)
        for (int x = 0; x < cell; ++x) image.at(c * (cell + 1) + x, 1 + b * (cell + 1) + y) = colour_of(b, c);
    }
  return image;
}

// One-glyph font: 'A' is a solid 2 x 3 block, advance 3, line height 6,
// baseline 4.
Bytes font_fixture() {
  Bytes out;
  le32(out, 1);
  le32(out, 6);
  le32(out, 4);
  le32(out, 1);
  out.insert(out.end(), {0, 0, 0, 0, 2, 3, 0, 3, 3});
  le32(out, 1);
  Image sheet(4, 4, {0, 0, 0, 255});
  for (int y = 0; y < 3; ++y)
    for (int x = 0; x < 2; ++x) sheet.at(x, y) = {255, 255, 255, 255};
  Bytes png = encode_png(sheet);
  out.insert(out.end(), png.begin(), png.end());
  for (int c = 0; c < 256; ++c) {
    std::uint16_t v = c == 'A' ? 0 : 0xffff;
    out.push_back(std::uint8_t(v));
    out.push_back(std::uint8_t(v >> 8));
  }
  return out;
}

void put(const fs::path& path, const Bytes& bytes) {
  fs::create_directories(path.parent_path());
  std::string error;
  if (!write_file(path.string(), bytes, error)) require(false, "write " + path.string() + ": " + error);
}

void test_parsers() {
  require(same(parse_color("1 2 3"), 1, 2, 3, 255), "colour without alpha is opaque");
  require(same(parse_color("224 255 224 128"), 224, 255, 224, 128), "colour with alpha");
  require(same(parse_color("300 -5"), 255, 0, 0, 255), "colour clamps and fills missing parts");
  require(parse_bool("1") && parse_bool("true") && parse_bool("TRUE") && parse_bool("2"), "true values");
  require(!parse_bool("0") && !parse_bool("") && !parse_bool("false"), "false values");
  require(parse_point("5 6").x == 5 && parse_point("5 6").y == 6, "point");
  require(parse_justify("Center") == Justify::center && parse_justify("right") == Justify::right &&
              parse_justify("x") == Justify::left, "justify");

  auto table = [](std::vector<std::pair<std::string, std::string>> rows) -> FieldLookup {
    return [rows](const std::string& n, std::string& v) {
      for (auto& r : rows) if (r.first == n) { v = r.second; return true; }
      return false;
    };
  };
  Profile p = read_profile(table({{"fontColor", "1 2 3"}, {"border", "3"}}),
                           table({{"fontColor", "9 9 9"}, {"fontSize", "20"}, {"bitmap", "./x"}}));
  require(same(p.font_color, 1, 2, 3) && p.border == 3, "own fields win");
  require(p.font_size == 20 && p.bitmap == "./x" && p.bitmap_from_fallback, "fallback fields");
  require(p.font_type == "Arial" && !p.opaque, "built-in defaults");
  p = read_profile(table({{"bitmap", "./y"}}), table({{"bitmap", "./x"}}));
  require(p.bitmap == "./y" && !p.bitmap_from_fallback, "own bitmap");
}

void test_layout_rules() {
  int pos = 31, len = 577;
  resize_axis(Sizing::center, 640, 800, pos, len);
  require(pos == 111 && len == 577, "center: (800 - 577) / 2");
  pos = 10, len = 20;
  resize_axis(Sizing::grow, 100, 150, pos, len);
  require(pos == 10 && len == 70, "width/height grow");
  pos = 10, len = 20;
  resize_axis(Sizing::move, 100, 150, pos, len);
  require(pos == 60 && len == 20, "left/top move");
  pos = 10, len = 20;
  resize_axis(Sizing::keep, 100, 150, pos, len);
  require(pos == 10 && len == 20, "right/bottom keep");
  pos = 10, len = 20;
  resize_axis(Sizing::relative, 100, 200, pos, len);
  require(pos == 20 && len == 40, "relative scales");
  require(parse_horiz_sizing("width") == Sizing::grow && parse_vert_sizing("top") == Sizing::move &&
              parse_horiz_sizing("") == Sizing::keep, "sizing names");
  // The stage 0 measurements: an 18-row label in a 14-row font starts 3
  // rows down, a 23-row label in a 19-row font 3, a 25-row button 6.
  require(text_line_top(18, 14) == 3 && text_line_top(23, 19) == 3 && text_line_top(25, 14) == 6,
          "text line top");
}

void test_smooth_stretch() {
  // The left edge of the 3.04 start-screen button: a 5-row piece whose rows
  // are 95, 95, 64, 64, 64 (green channel) is drawn 15 rows tall, and the
  // stage 0 screenshot shows 95 x3, 89, 83, 76, 70, 64 x8.
  Image piece(1, 5);
  const int rows[5] = {95, 95, 64, 64, 64};
  for (int y = 0; y < 5; ++y) piece.at(0, y) = {0, std::uint8_t(rows[y]), 0, 255};
  Canvas canvas(1, 15, {0, 0, 0, 255});
  canvas.smooth_stretch_blit(piece, {0, 0, 1, 5}, {0, 0, 1, 15});
  const int want[15] = {95, 95, 95, 89, 83, 76, 70, 64, 64, 64, 64, 64, 64, 64, 64};
  bool ok = true;
  for (int y = 0; y < 15; ++y) ok = ok && canvas.surface().at(0, y).g == want[y];
  require(ok, "smooth stretch reproduces the stage 0 button edge");

  // A kept axis copies texels; a two-texel span is not inset.
  Image two(2, 1);
  two.at(0, 0) = {0, 0, 0, 255};
  two.at(1, 0) = {200, 0, 0, 255};
  Canvas wide(4, 2, {9, 9, 9, 255});
  wide.smooth_stretch_blit(two, {0, 0, 2, 1}, {0, 0, 4, 1});
  require(wide.surface().at(0, 0).r == 0 && wide.surface().at(1, 0).r == 50 &&
              wide.surface().at(2, 0).r == 150 && wide.surface().at(3, 0).r == 200,
          "two-texel span stretched with clamped ends");
  wide.smooth_stretch_blit(two, {0, 0, 2, 1}, {0, 1, 2, 1});
  require(wide.surface().at(0, 1).r == 0 && wide.surface().at(1, 1).r == 200, "kept axis is exact");
}

void test_cell_trim() {
  // A separator row, then one 4-row band: a 2 x 4 cell beside a cell that
  // is only 2 rows tall.
  Image image(5, 5, kSep);
  for (int y = 1; y < 5; ++y) image.at(0, y) = image.at(1, y) = {1, 2, 3, 255};
  image.at(3, 1) = image.at(4, 1) = image.at(3, 2) = image.at(4, 2) = {4, 5, 6, 255};
  BitmapArray a = split_bitmap_array(image);
  require(a.cells.size() == 2 && a.cells[0] == Rect{0, 1, 2, 4} && a.cells[1] == Rect{3, 1, 2, 2},
          "a short cell drops its separator rows");
}

struct Install {
  fs::path root;
  Install() {
    root = fs::temp_directory_path() / ("tq-render-test-" + std::to_string(std::random_device{}()));
    fs::remove_all(root);
  }
  ~Install() { std::error_code ec; fs::remove_all(root, ec); }
};

SimObject* make(Engine& e, const std::string& cls, const std::string& name, const std::string& source,
                std::vector<std::pair<std::string, std::string>> fields, SimObject* parent = nullptr) {
  SimObject* o = e.create_object(cls, name, parent == nullptr);
  o->source = source;
  for (auto& f : fields) o->set_field(f.first, f.second);
  if (parent) e.add_to_set(parent, o);
  return o;
}

// A 16 x 8 baseline JPEG of one colour (200 30 40), written for this test
// by a stock encoder at quality 95.
const std::uint8_t kJpeg[] = {
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
    0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x02, 0x01, 0x01, 0x01, 0x01, 0x01, 0x02,
    0x01, 0x01, 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x04, 0x03, 0x02, 0x02, 0x02, 0x02, 0x05, 0x04,
    0x04, 0x03, 0x04, 0x06, 0x05, 0x06, 0x06, 0x06, 0x05, 0x06, 0x06, 0x06, 0x07, 0x09, 0x08, 0x06,
    0x07, 0x09, 0x07, 0x06, 0x06, 0x08, 0x0b, 0x08, 0x09, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x06, 0x08,
    0x0b, 0x0c, 0x0b, 0x0a, 0x0c, 0x09, 0x0a, 0x0a, 0x0a, 0xff, 0xdb, 0x00, 0x43, 0x01, 0x02, 0x02,
    0x02, 0x02, 0x02, 0x02, 0x05, 0x03, 0x03, 0x05, 0x0a, 0x07, 0x06, 0x07, 0x0a, 0x0a, 0x0a, 0x0a,
    0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a,
    0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a,
    0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0xff, 0xc0,
    0x00, 0x11, 0x08, 0x00, 0x08, 0x00, 0x10, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11,
    0x01, 0xff, 0xc4, 0x00, 0x1f, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
    0x0a, 0x0b, 0xff, 0xc4, 0x00, 0xb5, 0x10, 0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05,
    0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7d, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21,
    0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23,
    0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17,
    0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a,
    0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a,
    0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a,
    0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99,
    0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7,
    0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5,
    0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1,
    0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa, 0xff, 0xc4, 0x00, 0x1f, 0x01, 0x00, 0x03,
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
    0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0xff, 0xc4, 0x00, 0xb5, 0x11, 0x00,
    0x02, 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05, 0x04, 0x04, 0x00, 0x01, 0x02, 0x77, 0x00,
    0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13,
    0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0, 0x15,
    0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26, 0x27,
    0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88,
    0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,
    0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4,
    0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9,
    0xfa, 0xff, 0xda, 0x00, 0x0c, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3f, 0x00, 0xf9,
    0x1e, 0x8a, 0x28, 0xaf, 0xc7, 0xcf, 0xf5, 0x40, 0xff, 0xd9,
};

void test_jpeg() {
  Image image;
  std::string error;
  require(decode_jpeg(kJpeg, sizeof kJpeg, image, error), "JPEG decodes: " + error);
  require(image.width == 16 && image.height == 8, "JPEG size");
  if (image.width == 16 && image.height == 8) {
    const Color c = image.at(7, 3);
    require(std::abs(c.r - 200) <= 4 && std::abs(c.g - 30) <= 4 && std::abs(c.b - 40) <= 4 && c.a == 255,
            "JPEG colour, got " + show(c));
  }
  Image untouched(1, 1, {1, 2, 3, 255});
  require(!decode_jpeg(kJpeg, 20, untouched, error) && same(untouched.at(0, 0), 1, 2, 3),
          "a cut JPEG fails and leaves the image");
}

// Fonts from a TrueType file: uses whatever face find_system_font picks on
// this machine (Liberation Sans or DejaVu Sans on Linux), and skips when
// there is none.
void test_truetype() {
  GftFont font;
  std::string error;
  require(!gft_from_truetype({1, 2, 3}, 14, 1.0, font, error), "not a TrueType font is refused");
  const std::string path = find_system_font("Arial");
  if (path.empty()) { std::cout << "no TrueType face found; font check skipped\n"; return; }
  std::ifstream in(path, std::ios::binary);
  const std::vector<std::uint8_t> ttf((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  require(gft_from_truetype(ttf, 20, 0.75, font, error), "font from " + path + ": " + error);
  // 20 x 0.75 = 15 pixels to the em: ascent plus descent is a bit more.
  require(font.height >= 14 && font.height <= 20 && font.baseline > 0 && font.baseline < font.height,
          "line height and baseline at em 15, got " + std::to_string(font.height));
  const std::uint16_t a = font.char_map['A'], space = font.char_map[' '];
  require(a != kGftNoGlyph && space != kGftNoGlyph, "'A' and space have glyphs");
  if (a == kGftNoGlyph || space == kGftNoGlyph) return;
  const GftGlyph& g = font.glyphs[a];
  // The box can be up to three pixels wider than the advance (Arial's A has
  // a negative left bearing, and antialiasing widens it).
  require(g.width > 4 && g.height > 4 && g.x_advance > 4 && g.x_advance + 3 >= g.width,
          "'A' has a box and an advance, got " + std::to_string(g.width) + " wide, advance " +
              std::to_string(g.x_advance));
  require(font.glyphs[space].width == 0 && font.glyphs[space].x_advance > 0, "space is advance only");
  bool inked = false;
  const Image& sheet = font.sheets[g.sheet];
  for (int y = 0; y < g.height; ++y)
    for (int x = 0; x < g.width; ++x) inked = inked || sheet.at(g.x + x, g.y + y).r > 128;
  require(inked, "'A' has coverage on its sheet");
}

void test_renderer() {
  Install install;
  const fs::path& root = install.root;
  put(root / "common/ui/cache/Arial_14.gft", font_fixture());
  put(root / "common/ui/themes/default/btn.png", encode_png(make_array(12, 3, 2)));
  put(root / "common/ui/themes/default/edit.png", encode_png(make_array(3, 3, 2, true)));
  put(root / "common/ui/themes/default/themed.png", encode_png(make_array(12, 3, 2)));
  put(root / "common/ui/themes/default/scroll.png", encode_png(make_array(17, 3, 2)));
  // A plain background with one trailing byte after IEND, as the 3.04
  // graalDarkButton.png has.
  Bytes back = encode_png(Image(2, 2, {7, 8, 9, 255}));
  back.push_back(0);
  put(root / "game/ui/back.png", back);

  Engine e;
  e.files.root = root.string();
  e.files.prefs_dir = (root / "prefs").string();
  register_classes_304(e);
  const std::string profiles = "common/ui/defaultProfiles.cs";
  make(e, "GuiControlProfile", "GuiDefaultProfile", profiles,
       {{"fontColor", "0 0 0"}, {"fillColor", "0 128 0"}, {"fontType", "Arial"}, {"fontSize", "14"}});
  make(e, "GuiControlProfile", "ButtonProfile", profiles,
       {{"bitmap", "./themes/default/btn"}, {"hasBitmapArray", "1"}, {"fontColor", "255 0 0"},
        {"fontColorNA", "0 0 255"}, {"justify", "center"}});
  make(e, "GuiControlProfile", "ThemedProfile", profiles, {{"bitmap", "./themed"}, {"hasBitmapArray", "1"}});
  make(e, "GuiControlProfile", "EditProfile", profiles,
       {{"bitmap", "./themes/default/edit"}, {"hasBitmapArray", "1"}, {"opaque", "1"},
        {"fillColor", "0 200 0"}, {"fontColor", "255 255 255"}, {"textOffset", "1 0"}});
  make(e, "GuiControlProfile", "PopUpProfile", profiles,
       {{"bitmap", "./themes/default/scroll"}, {"opaque", "1"}, {"fillColor", "0 200 0"}});
  make(e, "GuiControlProfile", "LabelProfile", profiles,
       {{"fontColor", "255 255 0"}, {"autoSizeWidth", "1"}, {"autoSizeHeight", "1"}});
  make(e, "GuiControlProfile", "ContentProfile", profiles, {{"opaque", "1"}, {"fillColor", "10 10 10"}});

  const std::string gui = "game/ui/test.gui";
  SimObject* content = make(e, "GuiChunkedBitmapCtrl", "TestGui", gui,
                            {{"profile", "ContentProfile"}, {"position", "0 0"}, {"extent", "40 30"},
                             {"bitmap", "./back"}, {"tile", "1"}});
  make(e, "GuiButtonCtrl", "Button", gui,
       {{"profile", "ButtonProfile"}, {"position", "2 2"}, {"extent", "10 8"}, {"text", "A"}}, content);
  make(e, "GuiButtonCtrl", "Dead", gui,
       {{"profile", "ButtonProfile"}, {"position", "14 2"}, {"extent", "10 8"}, {"active", "0"}}, content);
  make(e, "GuiButtonCtrl", "Themed", gui,
       {{"profile", "ThemedProfile"}, {"position", "26 2"}, {"extent", "10 8"}}, content);
  make(e, "GuiTextEditCtrl", "Edit", gui,
       {{"profile", "EditProfile"}, {"position", "2 12"}, {"extent", "12 8"}, {"text", "A"}}, content);
  make(e, "GuiTextCtrl", "Label", gui,
       {{"profile", "LabelProfile"}, {"position", "20 12"}, {"extent", "1 1"}, {"text", "AA"},
        {"horizSizing", "left"}}, content);
  make(e, "GuiPopUpMenuCtrl", "PopUp", gui,
       {{"profile", "PopUpProfile"}, {"position", "26 21"}, {"extent", "12 8"}}, content);
  make(e, "GuiTextCtrl", "Hidden", gui,
       {{"profile", "LabelProfile"}, {"position", "2 22"}, {"extent", "20 8"}, {"text", "A"}, {"visible", "0"}},
       content);

  Canvas canvas(40, 30, {0, 0, 0, 255});
  Renderer renderer(e);
  renderer.render(canvas, content);
  const Image& s = canvas.surface();
  for (const auto& n : renderer.notes) std::cerr << "note: " << n << '\n';
  require(renderer.notes.empty(), "no missing files");

  require(same(s.at(0, 0), 7, 8, 9) && same(s.at(39, 29), 7, 8, 9), "chunked bitmap tiles a PNG with a trailing byte");
  // Button: corners and edges from the first nine cells, label centred.
  require(same(s.at(2, 2), 0, 0, 100) && same(s.at(11, 2), 0, 160, 100) && same(s.at(2, 9), 40, 0, 100) &&
              same(s.at(11, 9), 40, 160, 100), "button corners are cells 0, 2, 6 and 8");
  require(same(s.at(6, 2), 0, 80, 100) && same(s.at(2, 5), 20, 0, 100), "button edges are cells 1 and 3");
  // Label 'A' (3 wide) centred in 10: x = 2 + 3; 8 rows, 6-row font: top 2 + (8 - 4) / 2 = 4,
  // glyph top = 4 + baseline 4 - y origin 3 = 5.
  require(same(s.at(5, 5), 255, 0, 0) && same(s.at(6, 7), 255, 0, 0) && same(s.at(7, 5), 20, 80, 100),
          "button label centred in the font colour, got " + show(s.at(5, 5)));
  require(same(s.at(14, 2), 180, 0, 100) && same(s.at(18, 5), 200, 80, 100),
          "inactive button uses the fourth cell set");
  require(renderer.profile_bitmap_path(e.find_object("Themed")) == "common/ui/themes/default/themed",
          "profile bitmap falls back to the theme folder");
  require(same(s.at(26, 2), 0, 0, 100), "theme-relative bitmap drawn");
  // Text edit: eight cells, the box filled first, centre left to the fill.
  require(same(s.at(2, 12), 0, 0, 100) && same(s.at(13, 19), 40, 160, 100), "text edit corners");
  require(same(s.at(8, 16), 0, 200, 0) || same(s.at(8, 16), 255, 255, 255), "text edit centre is the fill");
  require(same(s.at(5, 15), 255, 255, 255), "text edit text after the left piece and text offset, got " +
                                                show(s.at(5, 15)));
  // Label: auto-sized to "AA" (6 wide, 10 tall), then moved by horizSizing
  // left (no resize here: the canvas is the content's own size).
  require(same(s.at(20, 16), 255, 255, 0) && same(s.at(23, 16), 255, 255, 0), "auto-sized label draws both glyphs");
  require(same(s.at(2, 25), 7, 8, 9), "invisible control not drawn");
  // Pop-up, no hasBitmapArray: frame from cells 42 to 50, arrow cell 39 at
  // the right inside the frame, vertically centred (51 cells, colours wrap).
  require(same(s.at(26, 21), 24, 0, 100) && same(s.at(37, 28), 64, 160, 100), "pop-up frame corners, got " +
                                                                                show(s.at(26, 21)));
  require(same(s.at(34, 24), 4, 0, 100) && same(s.at(35, 25), 4, 0, 100), "pop-up arrow, got " + show(s.at(34, 24)));
  require(same(s.at(30, 24), 44, 80, 100), "pop-up middle is the frame's centre cell");

  // The same content on a wider canvas: the label moves with its left sizing.
  Canvas wide(50, 30, {0, 0, 0, 255});
  renderer.render(wide, content);
  require(same(wide.surface().at(30, 16), 255, 255, 0), "horizSizing left follows the canvas width");

  // A pop-up opens on a click, its list draws over everything below it (or
  // above when it does not fit), and a click on a row picks that entry.
  SimObject* popup = e.find_object("PopUp");
  e.call_method(popup, "add", {"A", "7"});
  e.call_method(popup, "add", {"AA", "8"});
  Canvas tall(40, 60, {0, 0, 0, 255});
  renderer.render(tall, content);
  mouse_click(e, renderer, 30, 24, false);
  require(renderer.open_popup == popup->id, "a click opens the pop-up");
  renderer.render(tall, content);
  const Rect list = renderer.popup_list;
  require(list.y == 29 && list.height == 2 * renderer.popup_row_height + 2, "the list draws below the pop-up");
  mouse_click(e, renderer, list.x + 3, list.y + 1 + renderer.popup_row_height + 1, false);
  require(renderer.open_popup == 0 && popup->field("selected") == "8" && popup->field("text") == "AA",
          "a click on the second row selects it and closes the list");
  mouse_click(e, renderer, 30, 24, false);
  renderer.render(tall, content);
  mouse_click(e, renderer, 1, 1, false);
  require(renderer.open_popup == 0 && popup->field("selected") == "8", "a click outside closes it unchanged");

  // ML text: tags are read or dropped, never drawn. "<just:right>A" puts the
  // glyph at the right edge; "<font:x>" draws nothing.
  SimObject* ml = make(e, "GuiMLTextCtrl", "Ml", gui,
                       {{"profile", "LabelProfile"}, {"position", "0 40"}, {"extent", "40 20"},
                        {"text", "<font:Arial:14><just:right>A"}}, content);
  renderer.render(tall, content);
  const Image& t = tall.surface();
  int lit_left = 0, lit_right = 0;
  for (int y = 40; y < 60; ++y)
    for (int x = 0; x < 40; ++x)
      if (same(t.at(x, y), 255, 255, 0)) (x < 30 ? lit_left : lit_right)++;
  require(lit_left == 0 && lit_right > 0, "ML text: tags are not drawn and <just:right> aligns right");
  (void)ml;
}

}  // namespace

int main() {
  test_parsers();
  test_layout_rules();
  test_smooth_stretch();
  test_cell_trim();
  test_renderer();
  test_jpeg();
  test_truetype();
  if (failures) {
    std::cerr << failures << " check(s) failed\n";
    return 1;
  }
  std::cout << "render tests passed\n";
  return 0;
}
