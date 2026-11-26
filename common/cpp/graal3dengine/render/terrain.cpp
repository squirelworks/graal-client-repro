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
  uint8_t sec[kTerrainChunkSize][kTerrainChunkSize] = {};
  uint8_t share[kTerrainChunkSize][kTerrainChunkSize] = {};
  if (n > 1) {
    const int w = choiceBits(n);
    for (int y = 0; y < kTerrainChunkSize; ++y)
      for (int x = 0; x < kTerrainChunkSize; ++x) {
        const bool blend = r.flag();
        const int primary = int(r.bits(w));
        mat[y][x] = uint8_t(primary < n ? ids[primary] : 0);
        if (blend) {
          const int second = int(r.bits(w));
          int a = int(r.bits(4));
          uint8_t other = uint8_t(second < n ? ids[second] : 0);
          // The larger alpha is primary: a * 16 against 255 - a * 16.
          if (a * 16 < 255 - a * 16) {
            std::swap(mat[y][x], other);
            a = (255 - a * 16) / 16;
          }
          sec[y][x] = other;
          share[y][x] = uint8_t(a);
        }
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
      t.secondary[at] = sec[y][x];
      t.blendShare[at] = share[y][x];
      if (mode == 2) t.hole[at] = uint8_t(holes[y][x]);
      else if (mode == 1) t.hole[at] = 0;
    }
  t.stamps[size_t(cy * kTerrainChunks + cx)] = terrainStamp(encodeTerrainChunk(t, cx, cy));
  return true;
}

std::vector<uint8_t> encodeTerrainChunk(const Terrain& t, int cx, int cy) {
  if (cx < 0 || cy < 0 || cx >= kTerrainChunks || cy >= kTerrainChunks) return {};
  const int n = kTerrainChunkSize;
  auto at = [&](int x, int y) { return size_t(cy * n + y) * kTerrainSize + size_t(cx * n + x); };
  auto h = [&](int x, int y) { return int(t.heights[at(x, y)] >> 2); };
  auto clamp = [](int v) { return v < -127 ? -127 : (v > 127 ? 127 : v); };
  int d[16][16] = {};
  for (int x = 1; x < n; ++x) d[0][x] = clamp(h(x, 0) - h(x - 1, 0));
  for (int y = 1; y < n; ++y) {
    d[y][0] = clamp(h(0, y) - h(0, y - 1));
    for (int x = 1; x < n; ++x) d[y][x] = clamp(h(x, y) - (h(x, y - 1) + h(x - 1, y)) / 2);
  }
  for (int y = n - 1; y >= 1; --y)
    for (int x = n - 1; x >= 1; --x) d[y][x] = clamp(d[y][x] - (d[y - 1][x] + d[y][x - 1]) / 2);
  BitWriter w;
  w.bits(2, 8);
  w.bits(uint32_t(h(0, 0)), 16);
  for (auto& row : d)
    for (int v : row) w.bits(uint32_t(v) & 0xFF, 8);
  bool used[32] = {};
  for (int y = 0; y < n; ++y)
    for (int x = 0; x < n; ++x) {
      used[t.material[at(x, y)] & 31] = true;
      if (t.blendShare[at(x, y)]) used[t.secondary[at(x, y)] & 31] = true;
    }
  int index[32] = {}, count = 0;
  for (int i = 0; i < 32; ++i)
    if (used[i]) index[i] = count++;
  w.bits(uint32_t(count), 6);
  for (int i = 0; i < 32; ++i)
    if (used[i]) w.bits(uint32_t(i), 5);
  if (count > 1) {
    const int bits = choiceBits(count);
    for (int y = 0; y < n; ++y)
      for (int x = 0; x < n; ++x) {
        const size_t a = at(x, y);
        const bool blend = t.blendShare[a] != 0;
        w.flag(blend);
        w.bits(uint32_t(index[t.material[a] & 31]), bits);
        if (blend) {
          w.bits(uint32_t(index[t.secondary[a] & 31]), bits);
          w.bits(t.blendShare[a] & 15u, 4);
        }
      }
  }
  for (int y = 0; y < n; ++y)
    for (int x = 0; x < n; ++x) w.flag(t.hole[at(x, y)] != 0);
  const std::string b = w.bytes();
  return std::vector<uint8_t>(b.begin(), b.end());
}

uint32_t terrainStamp(const std::vector<uint8_t>& plain) {
  return uint32_t(crc32(0, plain.data(), uInt(plain.size()))) ^ 0xFFFFFFFFu;
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

bool terrainHeightAt(const Terrain& t, float x, float y, float& z, V3* normal) {
  const float sq = t.squareSize > 0 ? t.squareSize : 8.0f;
  const float gx = x / sq + 128.0f, gy = y / sq + 128.0f;
  if (!(gx >= 0 && gy >= 0 && gx < kTerrainSize && gy < kTerrainSize)) return false;
  const int ix = int(gx), iy = int(gy);
  if (t.hole[size_t(iy) * kTerrainSize + size_t(ix)]) return false;
  const float fx = gx - float(ix), fy = gy - float(iy);
  const float ha = t.heightMetres(ix, iy), hb = t.heightMetres(ix + 1, iy), hc = t.heightMetres(ix + 1, iy + 1),
              hd = t.heightMetres(ix, iy + 1);
  // The same split as terrainShape: a-b-d / b-c-d on odd squares, a-b-c /
  // a-c-d on even ones (corners a (0,0), b (1,0), c (1,1), d (0,1)).
  float dzdx, dzdy;
  if ((ix ^ iy) & 1) {
    if (fx + fy <= 1) {
      z = ha + (hb - ha) * fx + (hd - ha) * fy;
      dzdx = hb - ha;
      dzdy = hd - ha;
    } else {
      z = hc + (hd - hc) * (1 - fx) + (hb - hc) * (1 - fy);
      dzdx = hc - hd;
      dzdy = hc - hb;
    }
  } else if (fx >= fy) {
    z = ha + (hb - ha) * fx + (hc - hb) * fy;
    dzdx = hb - ha;
    dzdy = hc - hb;
  } else {
    z = ha + (hc - hd) * fx + (hd - ha) * fy;
    dzdx = hc - hd;
    dzdy = hd - ha;
  }
  if (normal) *normal = normalize(V3{-dzdx / sq, -dzdy / sq, 1});
  return true;
}

Shape terrainShape(const Terrain& t) {
  Shape shape;
  shape.kind = Shape::kTerrain;
  const int n = kTerrainSize;
  const float sq = t.squareSize > 0 ? t.squareSize : 8.0f;
  const float corner = -128.0f * sq;
  // A material per id named in heights.info (or used by a square), then
  // the black base.
  size_t ids = t.materials.size();
  for (size_t i = 0; i < t.material.size(); ++i) {
    ids = std::max(ids, size_t(t.material[i]) + 1);
    if (t.blendShare[i]) ids = std::max(ids, size_t(t.secondary[i]) + 1);
  }
  for (size_t id = 0; id < ids; ++id) {
    Material m;
    m.name = id < t.materials.size() ? t.materials[id] : std::string();
    m.texture = m.name;
    m.alphaTest = false;
    shape.materials.push_back(m);
  }
  const int base = int(shape.materials.size());
  {
    Material black;
    black.name = "terrain base";
    for (float& c : black.color) c = 0;
    black.alphaTest = false;
    shape.materials.push_back(black);
  }
  // The grid of points is 257 by 257, the last row and column wrapping to
  // the first. One texture repeat covers kTerrainTextureSquares squares,
  // image columns toward +x and rows toward +y (terrain-512.md, batch K).
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
      const uint32_t a = idx(x, y), b = idx(x + 1, y), c = idx(x + 1, y + 1), d = idx(x, y + 1);
      // Stock Torque alternates the split by square.
      if ((x ^ y) & 1) {
        mesh.triangles.push_back({{a, b, d}, base});
        mesh.triangles.push_back({{b, c, d}, base});
      } else {
        mesh.triangles.push_back({{a, b, c}, base});
        mesh.triangles.push_back({{a, c, d}, base});
      }
    }
  computeNormals(mesh);
  if (mesh.triangles.empty()) {
    shape.computeBounds();
    return shape;
  }
  // Each point carries its square's material (the point's square: the one
  // it is the low corner of, wrapping at the far edges), and the weights
  // interpolate across the squares, so an edge fades over one square with
  // its half-way line half a square before the boundary. A blended square
  // gives its primary a / 16 and its secondary the rest (batch K).
  std::vector<float> weights(ids * mesh.vertices.size(), 0.0f);
  for (int y = 0; y <= n; ++y)
    for (int x = 0; x <= n; ++x) {
      const size_t at = size_t(y % n) * size_t(n) + size_t(x % n);
      const size_t vi = idx(x, y);
      const int share = t.blendShare[at];
      const float wp = share ? float(share) / 16.0f : 1.0f;
      weights[size_t(t.material[at]) * mesh.vertices.size() + vi] += wp;
      if (share) weights[size_t(t.secondary[at]) * mesh.vertices.size() + vi] += 1.0f - wp;
    }
  for (size_t id = 0; id < ids; ++id) {
    const float* w = &weights[id * mesh.vertices.size()];
    Mesh layer;
    layer.name = "terrain " + std::to_string(id);
    for (const Triangle& tri : mesh.triangles)
      if (w[tri.v[0]] > 0 || w[tri.v[1]] > 0 || w[tri.v[2]] > 0) layer.triangles.push_back({{tri.v[0], tri.v[1], tri.v[2]}, int(id)});
    if (layer.triangles.empty()) continue;
    layer.vertices = mesh.vertices;
    layer.weight.assign(w, w + mesh.vertices.size());
    shape.meshes.push_back(std::move(layer));
  }
  shape.meshes.insert(shape.meshes.begin(), std::move(mesh));
  shape.computeBounds();
  return shape;
}

bool updateStreamedTerrain(StreamedTerrain& st, float squareSize, bool repeat, const std::string& cacheDir,
                           const std::map<int, std::string>& chunks, int chunkCount) {
  if (st.builtChunkCount == chunkCount && st.builtCacheDir == cacheDir && st.builtSquareSize == squareSize &&
      st.builtRepeat == repeat)
    return false;
  st.terrain = Terrain();
  st.terrain.squareSize = squareSize;
  st.terrain.repeat = repeat;
  if (!cacheDir.empty()) loadTerrainCache(cacheDir, st.terrain);
  for (const auto& [i, bytes] : chunks)
    applyCompressedTerrainChunk(st.terrain, i % kTerrainChunks, i / kTerrainChunks,
                                reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
  st.shape = terrainShape(st.terrain);
  st.builtChunkCount = chunkCount;
  st.builtCacheDir = cacheDir;
  st.builtSquareSize = squareSize;
  st.builtRepeat = repeat;
  return true;
}

}  // namespace graal3d::render
