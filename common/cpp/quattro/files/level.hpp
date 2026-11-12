// Levels as the 6.x program holds them: a 64 x 64 board of tile ids per
// layer, links, chests and signs.
//
// Readers, from Graal_analysis formats/level-binary.md,
// formats/level-binary-client.md and protocol/v5x-clients.md:
// - GR-V1.03 and GR-V1.04: 13-bit codes, least significant bit first; a
//   code with 0x1000 set is a run (count = code & 0xFF, double when 0x100
//   is set). Then links (#), baddies (3-byte records to FF FF FF), NPCs (#),
//   chests (#), signs (to an empty line), and GR-V1.04's optional HEIGHTS.
// - GR-V1.05: the same, but after the magic comes a GCHAR layer count and
//   one board per layer.
// - The board packet (PLO 101): 4096 little-endian 16-bit tile ids.
// 6.03r7 reads GR-V1.03 to 1.05 only; 6.01r1 and 6.00 also read 1.00 to
// 1.02, which this reader accepts with their code widths.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace Quattro::Files {

constexpr int kBoardSide = 64;
constexpr int kBoardTiles = kBoardSide * kBoardSide;

using Board = std::array<uint16_t, kBoardTiles>;

struct Link {
  std::string dest;
  int x = 0, y = 0, w = 0, h = 0;
  std::string newx, newy;  // numbers or "playerx"/"playery" expressions
};

struct Chest {
  int x = 0, y = 0, item = 0, sign = 0;
};

struct Sign {
  int x = 0, y = 0;
  std::string encoded;  // the sign alphabet bytes, not decoded here
};

struct Level {
  std::string magic;
  std::vector<Board> layers;  // layer 0 is the ground
  std::vector<Link> links;
  std::vector<Chest> chests;
  std::vector<Sign> signs;

  uint16_t tile(int x, int y, size_t layer = 0) const {
    if (layer >= layers.size() || x < 0 || y < 0 || x >= kBoardSide || y >= kBoardSide) return 0;
    return layers[layer][static_cast<size_t>(y * kBoardSide + x)];
  }
};

// Parses a level file. False (with `error`) on an unknown magic or a
// board that ends early.
bool read_level(std::string_view data, Level& out, std::string& error);

// PLO 101: replaces layer 0 (creating it when the level has none).
bool apply_board_packet(std::string_view body, Level& level, std::string& error);

// Writes a GR-V1.03 board stream with single runs only (for tests and
// local levels; the original writer also emits double runs).
std::string write_board_stream(const Board& board);

// Where tile `t` sits in a 2048 x 512 tile sheet, in tiles.
inline void tile_sheet_pos(uint16_t t, int& col, int& row) {
  col = (t % 16) + (t / 512) * 16;
  row = (t / 16) % 32;
}

}  // namespace Quattro::Files
