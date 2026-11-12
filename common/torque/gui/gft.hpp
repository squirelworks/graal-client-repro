// Reader for the 3.04 `.gft` font caches (common/ui/cache/<face>_<size>.gft).
//
// Layout, all integers little-endian. The header fields are from
// Graal_analysis torque/study-torque-clients.md section 4; the rest was
// read from the 14 shipped caches in the lab and checked by drawing text
// against the 3.04 stage 0 screenshot (see README.md):
//
//   u32 version            always 1
//   u32 height             line height in pixels
//   u32 baseline           pixels from the top of the line to the baseline
//   u32 glyph count        224 in every shipped cache (characters 32..255)
//   glyph count * 9 bytes:
//       u8 sheet           index of the glyph sheet holding the glyph
//       u8 reserved        0 in every shipped cache
//       u8 x, u8 y         top-left of the glyph on its sheet
//       u8 width, u8 height
//       s8 x origin        pen-relative left edge
//       s8 y origin        rows from the top of the glyph to the baseline
//       u8 x advance       pen advance after the glyph
//   u32 sheet count        1, or 2 for Arial 36
//   sheet count PNG streams, back to back; 8-bit gray, gray = coverage
//   256 * u16 character map: glyph index per character, 0xFFFF = none
//
// Validation limits and the rejection of trailing bytes are rebuild policy.
#pragma once

#include "image.hpp"

#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace Torque::Gui {

struct GftGlyph {
  std::uint8_t sheet = 0;
  std::uint8_t reserved = 0;
  std::uint8_t x = 0, y = 0;
  std::uint8_t width = 0, height = 0;
  std::int8_t x_origin = 0;
  std::int8_t y_origin = 0;
  std::uint8_t x_advance = 0;
};

constexpr std::uint16_t kGftNoGlyph = 0xffff;

struct GftFont {
  std::uint32_t version = 0;
  std::uint32_t height = 0;
  std::uint32_t baseline = 0;
  std::vector<GftGlyph> glyphs;
  std::vector<Image> sheets;  // gray level in r, g and b is glyph coverage
  std::array<std::uint16_t, 256> char_map{};

  // Glyph for a character, or nullptr when the cache has none.
  const GftGlyph* glyph(unsigned char c) const;
  // Sum of x advances. Characters without a glyph add nothing.
  int text_width(std::string_view text) const;
  // Coverage 0..255 of a glyph pixel (gx, gy inside the glyph box).
  std::uint8_t coverage(const GftGlyph& glyph, int gx, int gy) const;
};

constexpr std::size_t kMaxGftBytes = std::size_t(16) * 1024 * 1024;
constexpr std::uint32_t kMaxGftGlyphs = 65535;
constexpr std::uint32_t kMaxGftSheets = 256;

// Parses a whole cache file. On failure `out` is unchanged.
bool load_gft(const std::vector<std::uint8_t>& bytes, GftFont& out, std::string& error);

// File name of a cache: face, underscore, pixel size (the `%s%s_%d.gft`
// pattern in torque/engine-and-formats.md, without the directory prefix).
std::string gft_cache_name(std::string_view face, int size);

}  // namespace Torque::Gui
