// Fonts made from a TrueType file when an install ships no `.gft` cache.
//
// Stock TGE 1.2 looks for `<face>_<size>.gft` in the font cache folder and,
// when it is missing, builds the font from the system's own face and writes
// the cache. The Mac 3.153 install ships no cache at all, so every font it
// draws comes from that path (its `fontcache/` folder starts empty). This
// rebuild does the same in memory, with stb_truetype
// (common/cpp/third_party/stb), for characters 32 to 255 (Latin-1).
//
// Rebuild policy, not read from the original:
// - The em size in pixels is the Torque size times `em_scale`. The 3.153
//   Tiger capture's text is three quarters of the size its profiles name
//   (Arial 20 "Welcome to Graal!" and Arial 14 labels both measure so), so
//   the 3.153 host passes 0.75. The line height is the font's ascent plus
//   descent at that size, and the baseline is the ascent.
// - Glyph coverage is stb_truetype's antialiased 8-bit rendering.
// - Which file stands for a face: see find_system_font.
#pragma once

#include "gft.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace Torque::Gui {

// Builds a font of Torque size `size` from a TrueType file's bytes. On failure
// `out` is unchanged and `error` names the problem.
bool gft_from_truetype(const std::vector<std::uint8_t>& ttf, int size, double em_scale, GftFont& out,
                       std::string& error);

// The TrueType file that stands for a Torque face name ("Arial",
// "Arial Bold"), or "" when none is found. The face's own file wins (the
// Mac's Arial, Windows' arial.ttf); else a face with the same metrics
// (Liberation Sans for Arial, Liberation Sans Bold for Arial Bold); else
// DejaVu Sans. Searched in the usual font folders of Linux, macOS and
// Windows, and in `extra_dirs` first.
std::string find_system_font(const std::string& face, const std::vector<std::string>& extra_dirs = {});

}  // namespace Torque::Gui
