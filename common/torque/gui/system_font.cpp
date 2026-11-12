#include "system_font.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <filesystem>

#define STBTT_STATIC
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

namespace Torque::Gui {

namespace {

constexpr int kSheetSide = 256;  // glyph boxes are u8 positions on a sheet

std::string lowered(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

std::uint32_t be32(const std::uint8_t* p) {
  return std::uint32_t(p[0]) << 24 | std::uint32_t(p[1]) << 16 | std::uint32_t(p[2]) << 8 | p[3];
}

// stb_truetype reads table offsets without checking them against the
// file's size, so the sfnt header and table directory are checked here
// first: a single font (not a collection) whose tables all lie inside the
// bytes. The files come from the system's font folders, not from a server.
bool plausible_sfnt(const std::vector<std::uint8_t>& ttf) {
  if (ttf.size() < 12) return false;
  const std::uint32_t tag = be32(ttf.data());
  if (tag != 0x00010000u && tag != 0x74727565u /* true */) return false;
  const std::size_t tables = std::size_t(ttf[4]) << 8 | ttf[5];
  if (tables == 0 || 12 + tables * 16 > ttf.size()) return false;
  for (std::size_t i = 0; i < tables; ++i) {
    const std::uint8_t* entry = ttf.data() + 12 + i * 16;
    const std::uint64_t offset = be32(entry + 8), length = be32(entry + 12);
    if (offset + length > ttf.size()) return false;
  }
  return true;
}

}  // namespace

bool gft_from_truetype(const std::vector<std::uint8_t>& ttf, int size, double em_scale, GftFont& out,
                       std::string& error) {
  if (size < 4 || size > 200 || em_scale < 0.25 || em_scale > 4) { error = "font size out of range"; return false; }
  stbtt_fontinfo info;
  if (!plausible_sfnt(ttf) || !stbtt_InitFont(&info, ttf.data(), 0)) {
    error = "not a TrueType font";
    return false;
  }
  const float scale = stbtt_ScaleForMappingEmToPixels(&info, static_cast<float>(size * em_scale));
  int ascent = 0, descent = 0, gap = 0;
  stbtt_GetFontVMetrics(&info, &ascent, &descent, &gap);
  const int base = static_cast<int>(std::ceil(ascent * scale));
  const int below = static_cast<int>(std::ceil(-descent * scale));

  GftFont font;
  font.version = 1;
  font.height = static_cast<std::uint32_t>(base + below);
  font.baseline = static_cast<std::uint32_t>(base);
  font.char_map.fill(kGftNoGlyph);
  font.sheets.emplace_back(kSheetSide, kSheetSide, Color{0, 0, 0, 255});
  int pen_x = 0, pen_y = 0, row_height = 0;
  for (int c = 32; c < 256; ++c) {
    const int index = stbtt_FindGlyphIndex(&info, c);
    if (index == 0 && c != 32) continue;
    int advance = 0, bearing = 0;
    stbtt_GetGlyphHMetrics(&info, index, &advance, &bearing);
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    stbtt_GetGlyphBitmapBox(&info, index, scale, scale, &x0, &y0, &x1, &y1);
    const int w = std::max(0, x1 - x0), h = std::max(0, y1 - y0);
    if (w >= kSheetSide || h >= kSheetSide) { error = "glyph too large for a sheet"; return false; }
    if (pen_x + w >= kSheetSide) { pen_x = 0; pen_y += row_height + 1; row_height = 0; }
    if (pen_y + h >= kSheetSide) {
      font.sheets.emplace_back(kSheetSide, kSheetSide, Color{0, 0, 0, 255});
      pen_x = pen_y = row_height = 0;
    }
    GftGlyph g;
    g.sheet = static_cast<std::uint8_t>(font.sheets.size() - 1);
    g.x = static_cast<std::uint8_t>(pen_x);
    g.y = static_cast<std::uint8_t>(pen_y);
    g.width = static_cast<std::uint8_t>(w);
    g.height = static_cast<std::uint8_t>(h);
    g.x_origin = static_cast<std::int8_t>(std::clamp(x0, -128, 127));
    g.y_origin = static_cast<std::int8_t>(std::clamp(-y0, -128, 127));
    g.x_advance = static_cast<std::uint8_t>(std::clamp(static_cast<int>(std::lround(advance * scale)), 0, 255));
    if (w > 0 && h > 0) {
      std::vector<unsigned char> cover(static_cast<std::size_t>(w) * h);
      stbtt_MakeGlyphBitmap(&info, cover.data(), w, h, w, scale, scale, index);
      Image& sheet = font.sheets.back();
      for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
          const std::uint8_t v = cover[static_cast<std::size_t>(y) * w + x];
          sheet.at(pen_x + x, pen_y + y) = Color{v, v, v, 255};
        }
    }
    font.char_map[static_cast<std::size_t>(c)] = static_cast<std::uint16_t>(font.glyphs.size());
    font.glyphs.push_back(g);
    pen_x += w + 1;
    row_height = std::max(row_height, h);
  }
  out = std::move(font);
  return true;
}

std::string find_system_font(const std::string& face, const std::vector<std::string>& extra_dirs) {
  const std::string want = lowered(face);
  const bool bold = want.find("bold") != std::string::npos;
  std::vector<std::string> names;  // file names, best first
  if (want.rfind("arial", 0) == 0) {
    if (bold) names = {"arialbd.ttf", "arial bold.ttf", "liberationsans-bold.ttf"};
    else names = {"arial.ttf", "liberationsans-regular.ttf"};
  } else {
    std::string file = want;
    file.erase(std::remove(file.begin(), file.end(), ' '), file.end());
    names = {file + ".ttf"};
  }
  names.push_back(bold ? "dejavusans-bold.ttf" : "dejavusans.ttf");

  std::vector<std::string> dirs = extra_dirs;
  for (const char* d : {"/usr/share/fonts", "/usr/local/share/fonts", "/Library/Fonts", "/System/Library/Fonts",
                        "/System/Library/Fonts/Supplemental", "C:/Windows/Fonts"})
    dirs.emplace_back(d);
  if (const char* home = std::getenv("HOME")) {
    dirs.push_back(std::string(home) + "/.fonts");
    dirs.push_back(std::string(home) + "/.local/share/fonts");
    dirs.push_back(std::string(home) + "/Library/Fonts");
  }
  // every .ttf under the folders, by lower-case file name (first found wins)
  std::vector<std::pair<std::string, std::string>> found;
  for (const auto& dir : dirs) {
    std::error_code ec;
    if (!std::filesystem::is_directory(dir, ec)) continue;
    for (auto it = std::filesystem::recursive_directory_iterator(dir, ec);
         it != std::filesystem::recursive_directory_iterator(); it.increment(ec)) {
      if (ec) break;
      if (it->is_regular_file(ec)) found.emplace_back(lowered(it->path().filename().string()), it->path().string());
    }
  }
  for (const auto& name : names)
    for (const auto& [file, path] : found)
      if (file == name) return path;
  return std::string();
}

}  // namespace Torque::Gui
