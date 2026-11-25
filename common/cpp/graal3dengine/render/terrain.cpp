#include "terrain.hpp"

#include "../src/bits.hpp"

#include <zlib.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <map>

namespace fs = std::filesystem;

namespace graal3d::render {

float Terrain::heightMetres(int x, int y) const {
  x &= kTerrainSize - 1;
  y &= kTerrainSize - 1;
  return float(heights[size_t(y) * kTerrainSize + size_t(x)]) / 32.0f;
}

namespace {

// Bits for one of n choices: n rounded up to a power of two, then log2.
int choiceBits(int n) {
  int w = 0;
  while ((1 << w) < n) ++w;
  return w;
}

}  // namespace

bool applyTerrainChunk(Terrain& t, int cx, int cy, const uint8_t* data, size_t size) {
  if (cx < 0 || cy < 0 || cx >= kTerrainChunks || cy >= kTerrainChunks) return false;
  BitReader r(std::string(reinterpret_cast<const char*>(data), size));
  const int mode = int(r.bits(8));
  const int16_t h0 = int16_t(r.bits(16));
  int8_t d[kTerrainChunkSize][kTerrainChunkSize];
  for (auto& row : d)
    for (int8_t& v : row) v = int8_t(r.bits(8));
  // Heights: 16-bit arithmetic, 8-bit signed deltas, "/2" toward zero
  // (terrain-512.md section 2).
  int16_t h[kTerrainChunkSize][kTerrainChunkSize];
  h[0][0] = h0;
  for (int x = 1; x < kTerrainChunkSize; ++x) h[0][x] = int16_t(h[0][x - 1] + d[0][x]);
  for (int y = 1; y < kTerrainChunkSize; ++y) h[y][0] = int16_t(h[y - 1][0] + d[y][0]);
  for (int y = 1; y < kTerrainChunkSize; ++y)
    for (int x = 1; x < kTerrainChunkSize; ++x) {
      d[y][x] = int8_t(d[y][x] + (d[y - 1][x] + d[y][x - 1]) / 2);
      h[y][x] = int16_t((h[y - 1][x] + h[y][x - 1]) / 2 + d[y][x]);
    }
  // Materials: N ids, then per square a primary (and maybe a blend).
  const int n = int(r.bits(6));
  int ids[64] = {};
  for (int i = 0; i < n; ++i) ids[i] = int(r.bits(5));
  uint8_t mat[kTerrainChunkSize][kTerrainChunkSize] = {};
  if (n > 1) {
    const int w = choiceBits(n);
    for (int y = 0; y < kTerrainChunkSize; ++y)
      for (int x = 0; x < kTerrainChunkSize; ++x) {
        const bool blend = r.flag();
        const int primary = int(r.bits(w));
        if (blend) {
          r.bits(w);  // secondary
          r.bits(4);  // its share
        }
        mat[y][x] = uint8_t(primary < n ? ids[primary] : 0);
      }
  } else if (n == 1) {
    for (auto& row : mat)
      for (uint8_t& m : row) m = uint8_t(ids[0]);
  }
  int holes[kTerrainChunkSize][kTerrainChunkSize] = {};
  if (mode == 2)
    for (auto& row : holes)
      for (int& v : row) v = r.flag() ? 1 : 0;
  for (int y = 0; y < kTerrainChunkSize; ++y)
    for (int x = 0; x < kTerrainChunkSize; ++x) {
      const size_t at = size_t(cy * kTerrainChunkSize + y) * kTerrainSize + size_t(cx * kTerrainChunkSize + x);
      t.heights[at] = uint16_t(uint16_t(h[y][x]) << 2);
      t.material[at] = mat[y][x];
      if (mode == 2) t.hole[at] = uint8_t(holes[y][x]);
      else if (mode == 1) t.hole[at] = 0;
    }
  return true;
}

bool applyCompressedTerrainChunk(Terrain& t, int cx, int cy, const uint8_t* data, size_t size) {
  std::vector<uint8_t> out(4096);
  uLongf outSize = uLongf(out.size());
  if (uncompress(out.data(), &outSize, data, uLong(size)) != Z_OK) {
    // Applied as all zeros: height 0, material 0 (terrain-512.md, lab).
    std::vector<uint8_t> zeros(1 + 2 + 256 + 1, 0);
    return applyTerrainChunk(t, cx, cy, zeros.data(), zeros.size());
  }
  return applyTerrainChunk(t, cx, cy, out.data(), outSize);
}

std::vector<std::string> parseHeightsInfo(const std::string& text) {
  std::vector<std::string> names;
  std::string line;
  for (size_t i = 0; i <= text.size(); ++i) {
    if (i == text.size() || text[i] == '\n') {
      if (!line.empty() && line.back() == '\r') line.pop_back();
      if (!line.empty() || i < text.size()) names.push_back(line);
      line.clear();
      if (names.size() >= 32) break;
    } else {
      line += text[i];
    }
  }
  while (!names.empty() && names.back().empty()) names.pop_back();
  return names;
}

int loadTerrainCache(const std::string& dir, Terrain& t) {
  // Lower-case base name -> path, so the folder's case does not matter.
  std::map<std::string, fs::path> files;
  std::error_code ec;
  for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) {
    std::string name = it->path().filename().string();
    for (char& c : name) c = char(std::tolower(static_cast<unsigned char>(c)));
    files[name] = it->path();
  }
  auto read = [](const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), {});
  };
  if (auto it = files.find("heights.info"); it != files.end()) {
    const std::vector<uint8_t> b = read(it->second);
    t.materials = parseHeightsInfo(std::string(b.begin(), b.end()));
  }
  int loaded = 0;
  for (int cy = 0; cy < kTerrainChunks; ++cy)
    for (int cx = 0; cx < kTerrainChunks; ++cx) {
      auto it = files.find("heights" + std::to_string(cx) + "-" + std::to_string(cy) + ".dat");
      if (it == files.end()) continue;
      const std::vector<uint8_t> b = read(it->second);
      if (b.size() > (1u << 20)) continue;
      applyCompressedTerrainChunk(t, cx, cy, b.data(), b.size());
      ++loaded;
    }
  if (loaded) t.present = true;
  t.chunksLoaded = loaded;
  return loaded;
}

Shape terrainShape(const Terrain& t) {
  Shape shape;
  const int n = kTerrainSize;
  const float sq = t.squareSize > 0 ? t.squareSize : 8.0f;
  const float corner = -128.0f * sq;
  // One mesh, so lighting is smooth across material edges; a material per
  // id named in heights.info (or used by a square).
  size_t ids = t.materials.size();
  for (uint8_t m : t.material) ids = std::max(ids, size_t(m) + 1);
  for (size_t id = 0; id < ids; ++id) {
    Material m;
    m.name = id < t.materials.size() ? t.materials[id] : std::string();
    m.texture = m.name;
    m.alphaTest = false;
    shape.materials.push_back(m);
  }
  // The grid of points is 257 by 257, the last row and column wrapping to
  // the first.
  const float uvStep = 1.0f / float(kTerrainTextureSquares);
  Mesh mesh;
  mesh.name = "terrain";
  mesh.vertices.reserve(size_t(n + 1) * size_t(n + 1));
  for (int y = 0; y <= n; ++y)
    for (int x = 0; x <= n; ++x) {
      Vertex v;
      v.position = {corner + float(x) * sq, corner + float(y) * sq, t.heightMetres(x, y)};
      v.u = float(x) * uvStep;
      v.v = float(y) * uvStep;
      mesh.vertices.push_back(v);
    }
  auto idx = [&](int x, int y) { return uint32_t(y * (n + 1) + x); };
  for (int y = 0; y < n; ++y)
    for (int x = 0; x < n; ++x) {
      const size_t at = size_t(y) * size_t(n) + size_t(x);
      if (t.hole[at]) continue;
      const int mi = t.material[at];
      const uint32_t a = idx(x, y), b = idx(x + 1, y), c = idx(x + 1, y + 1), d = idx(x, y + 1);
      // Stock Torque alternates the split by square.
      if ((x ^ y) & 1) {
        mesh.triangles.push_back({{a, b, d}, mi});
        mesh.triangles.push_back({{b, c, d}, mi});
      } else {
        mesh.triangles.push_back({{a, b, c}, mi});
        mesh.triangles.push_back({{a, c, d}, mi});
      }
    }
  computeNormals(mesh);
  if (!mesh.triangles.empty()) shape.meshes.push_back(std::move(mesh));
  shape.computeBounds();
  return shape;
}

}  // namespace graal3d::render
