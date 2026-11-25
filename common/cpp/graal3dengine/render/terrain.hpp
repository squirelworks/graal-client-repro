// The 5.12's streamed terrain (Graal_analysis torque/terrain-512.md).
//
// A TerrainBlock ghost carries only settings; the heights, materials and
// holes arrive as 256 chunks of 16 by 16 squares in TerrainChunkEvents,
// each a zlib stream, and the client keeps every chunk in a per-server
// cache folder (levels3d/heights/<server>/heights<x>-<y>.dat, with the
// material names in heights.info, one per line). The grid is 256 by 256
// squares centred on the origin: its corner is at (-128, -128) squares.
//
// The rebuild's own (no lab check yet): the terrain is drawn with each
// square's primary material only (no blending), each material texture
// repeating every kTerrainTextureSquares squares, and the grid wraps at
// its far edges as stock Torque's does.
#pragma once

#include "mesh.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace graal3d::render {

constexpr int kTerrainSize = 256;       // squares per side
constexpr int kTerrainChunkSize = 16;   // squares per chunk side
constexpr int kTerrainChunks = 16;      // chunks per side
constexpr int kTerrainTextureSquares = 8;  // rebuild's own: squares per texture repeat

struct Terrain {
  bool present = false;
  float squareSize = 8;  // metres per square
  bool repeat = false;
  // Per grid point, row-major (y * 256 + x): the stored 16-bit height (the
  // decoded value shifted up 2 bits; 32 stored = 1 m), the primary
  // material id, and the hole flag.
  std::vector<uint16_t> heights = std::vector<uint16_t>(kTerrainSize * kTerrainSize, 0);
  std::vector<uint8_t> material = std::vector<uint8_t>(kTerrainSize * kTerrainSize, 0);
  std::vector<uint8_t> hole = std::vector<uint8_t>(kTerrainSize * kTerrainSize, 0);
  std::vector<std::string> materials;  // texture names by material id (heights.info)
  int chunksLoaded = 0;

  float heightMetres(int x, int y) const;
};

// Applies one inflated chunk at chunk (cx, cy). Returns false (and
// changes nothing) when cx or cy is out of range; data that runs short
// reads as zeros (the rebuild's bit reader).
bool applyTerrainChunk(Terrain& t, int cx, int cy, const uint8_t* data, size_t size);

// Inflates a chunk's zlib stream and applies it. A corrupt or truncated
// stream applies as all zeros (height 0, material 0), as the 5.12 does.
bool applyCompressedTerrainChunk(Terrain& t, int cx, int cy, const uint8_t* data, size_t size);

// heights.info: one texture name per line (a comma does not separate).
std::vector<std::string> parseHeightsInfo(const std::string& text);

// Loads heights.info and every heights<x>-<y>.dat in `dir`. Returns the
// number of chunk files loaded.
int loadTerrainCache(const std::string& dir, Terrain& t);

// The terrain as a shape in world space: one mesh, material i naming
// materials[i]'s texture. Holes are left out.
Shape terrainShape(const Terrain& t);

}  // namespace graal3d::render
