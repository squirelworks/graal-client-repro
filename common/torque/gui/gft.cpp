#include "gft.hpp"

namespace Torque::Gui {

namespace {
std::uint32_t le32(const std::uint8_t* p) {
  return std::uint32_t(p[0]) | (std::uint32_t(p[1]) << 8) | (std::uint32_t(p[2]) << 16) |
         (std::uint32_t(p[3]) << 24);
}
}  // namespace

const GftGlyph* GftFont::glyph(unsigned char c) const {
  std::uint16_t index = char_map[c];
  if (index == kGftNoGlyph || index >= glyphs.size()) return nullptr;
  return &glyphs[index];
}

int GftFont::text_width(std::string_view text) const {
  int width = 0;
  for (char c : text)
    if (const GftGlyph* g = glyph(static_cast<unsigned char>(c))) width += g->x_advance;
  return width;
}

std::uint8_t GftFont::coverage(const GftGlyph& g, int gx, int gy) const {
  if (gx < 0 || gy < 0 || gx >= g.width || gy >= g.height || g.sheet >= sheets.size()) return 0;
  return sheets[g.sheet].at(g.x + gx, g.y + gy).r;
}

bool load_gft(const std::vector<std::uint8_t>& bytes, GftFont& out, std::string& error) {
  auto fail = [&](const std::string& message) { error = message; return false; };
  const std::size_t size = bytes.size();
  const std::uint8_t* data = bytes.data();
  if (size > kMaxGftBytes) return fail("file too large");
  if (size < 16) return fail("truncated header");

  GftFont font;
  font.version = le32(data);
  font.height = le32(data + 4);
  font.baseline = le32(data + 8);
  std::uint32_t count = le32(data + 12);
  if (font.version != 1) return fail("unsupported version");
  if (font.height == 0 || font.height > 255 || font.baseline > font.height)
    return fail("bad height or baseline");
  if (count > kMaxGftGlyphs) return fail("too many glyphs");

  std::size_t pos = 16;
  if ((size - pos) / 9 < count) return fail("truncated glyph table");
  font.glyphs.resize(count);
  for (auto& g : font.glyphs) {
    const std::uint8_t* p = data + pos;
    g.sheet = p[0];
    g.reserved = p[1];
    g.x = p[2];
    g.y = p[3];
    g.width = p[4];
    g.height = p[5];
    g.x_origin = static_cast<std::int8_t>(p[6]);
    g.y_origin = static_cast<std::int8_t>(p[7]);
    g.x_advance = p[8];
    pos += 9;
  }

  if (size - pos < 4) return fail("truncated sheet count");
  std::uint32_t sheet_count = le32(data + pos);
  pos += 4;
  if (sheet_count > kMaxGftSheets) return fail("too many sheets");
  for (std::uint32_t i = 0; i < sheet_count; ++i) {
    Image sheet;
    std::size_t used = 0;
    std::string png_error;
    if (!decode_png(data + pos, size - pos, sheet, png_error, &used))
      return fail("sheet " + std::to_string(i) + ": " + png_error);
    font.sheets.push_back(std::move(sheet));
    pos += used;
  }

  if (size - pos != 512) return fail(size - pos < 512 ? "truncated character map" : "bytes after character map");
  for (std::size_t c = 0; c < 256; ++c) {
    std::uint16_t index = std::uint16_t(data[pos + 2 * c] | (data[pos + 2 * c + 1] << 8));
    if (index != kGftNoGlyph && index >= count) return fail("character map points past glyph table");
    font.char_map[c] = index;
  }

  for (std::size_t i = 0; i < font.glyphs.size(); ++i) {
    const GftGlyph& g = font.glyphs[i];
    if (g.width == 0 || g.height == 0) continue;
    if (g.sheet >= font.sheets.size()) return fail("glyph " + std::to_string(i) + " names a missing sheet");
    const Image& sheet = font.sheets[g.sheet];
    if (g.x + g.width > sheet.width || g.y + g.height > sheet.height)
      return fail("glyph " + std::to_string(i) + " lies outside its sheet");
  }
  out = std::move(font);
  return true;
}

std::string gft_cache_name(std::string_view face, int size) {
  return std::string(face) + "_" + std::to_string(size) + ".gft";
}

}  // namespace Torque::Gui
