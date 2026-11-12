// Checks for the profile reader and the stock control renderer. Every input
// is built here: the bitmap arrays and the font are small synthetic images
// written to a temporary install folder, and the control tree is created
// on the console engine directly. No original Graal file is used; the 3.04
// main menu is checked against the stage 0 screenshot by tests/lab_check.sh.
#include "../canvas.hpp"
#include "../profile.hpp"
#include "../render.hpp"
#include "../../console/engine/engine.hpp"

#include <filesystem>
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

void test_renderer() {
  Install install;
  const fs::path& root = install.root;
  put(root / "common/ui/cache/Arial_14.gft", font_fixture());
  put(root / "common/ui/themes/default/btn.png", encode_png(make_array(12, 3, 2)));
  put(root / "common/ui/themes/default/edit.png", encode_png(make_array(3, 3, 2, true)));
  put(root / "common/ui/themes/default/themed.png", encode_png(make_array(12, 3, 2)));
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

  // The same content on a wider canvas: the label moves with its left sizing.
  Canvas wide(50, 30, {0, 0, 0, 255});
  renderer.render(wide, content);
  require(same(wide.surface().at(30, 16), 255, 255, 0), "horizSizing left follows the canvas width");
}

}  // namespace

int main() {
  test_parsers();
  test_layout_rules();
  test_smooth_stretch();
  test_cell_trim();
  test_renderer();
  if (failures) {
    std::cerr << failures << " check(s) failed\n";
    return 1;
  }
  std::cout << "render tests passed\n";
  return 0;
}
