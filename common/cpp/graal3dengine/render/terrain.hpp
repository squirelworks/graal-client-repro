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
#include <map>
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
  // A blended square: its second material and the primary's share a
  // (primary alpha a * 16, secondary 255 - a * 16), kept with the larger
  // share as primary as the client keeps it. blendShare 0: no blend.
  std::vector<uint8_t> secondary = std::vector<uint8_t>(kTerrainSize * kTerrainSize, 0);
  std::vector<uint8_t> blendShare = std::vector<uint8_t>(kTerrainSize * kTerrainSize, 0);
  // The client's stamp of each chunk (index y * 16 + x), 0 for none.
  std::vector<uint32_t> stamps = std::vector<uint32_t>(kTerrainChunks * kTerrainChunks, 0);
  std::vector<std::string> materials;  // texture names by material id (heights.info)
  int chunksLoaded = 0;

  float heightMetres(int x, int y) const;
};

// Applies one inflated chunk at chunk (cx, cy). Returns false (and
// changes nothing) when cx or cy is out of range; data that runs short
// reads as zeros (the rebuild's bit reader).
// Also records the chunk's stamp, as the client computes it.
bool applyTerrainChunk(Terrain& t, int cx, int cy, const uint8_t* data, size_t size);

// The chunk as the 5.12 re-encodes it before saving and stamping it
// (terrain-512.md section 3): mode 2, only the material ids used, ascending,
// deltas from its own two-pass writer, each clamped.
std::vector<uint8_t> encodeTerrainChunk(const Terrain& t, int cx, int cy);

// The 5.12's stamp of re-encoded chunk bytes: CRC-32 (start 0xFFFFFFFF)
// with no final inversion.
uint32_t terrainStamp(const std::vector<uint8_t>& plain);

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

// The streamed terrain as a renderer keeps it between frames: the cache
// folder's chunks with the session's over them, and its mesh. Rebuilt
// only when the settings, the cache folder or the number of chunks the
// session has received change.
struct StreamedTerrain {
  Terrain terrain;
  Shape shape;
  int builtChunkCount = -1;
  std::string builtCacheDir;
  float builtSquareSize = -1;
  bool builtRepeat = false;
};

// `cacheDir` is the folder holding heights.info ("" for none); `chunks`
// the session's chunks by index (y * 16 + x), `chunkCount` how many it
// has received. Returns true when it rebuilt.
bool updateStreamedTerrain(StreamedTerrain& st, float squareSize, bool repeat, const std::string& cacheDir,
                           const std::map<int, std::string>& chunks, int chunkCount);

}  // namespace graal3d::render
