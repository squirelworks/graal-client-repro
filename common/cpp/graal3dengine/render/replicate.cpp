#include "replicate.hpp"

#include <algorithm>
#include <cmath>
#include <memory>
#include <sstream>

namespace graal3d::render {

namespace {

// Park-Miller minimal standard (Torque's MRandomLCG).
struct ParkMiller {
  int32_t s;
  explicit ParkMiller(int32_t seed) : s(seed == 0 ? 1 : (seed < 0 ? -(seed + 1) + 1 : seed)) {}
  int32_t next() {
    const int32_t hi = s / 127773, lo = s % 127773;
    s = 16807 * lo - 2836 * hi;
    if (s <= 0) s += 2147483647;
    return s;
  }
};

std::vector<std::string> splitShapes(const std::string& list) {
  std::vector<std::string> out;
  std::stringstream ss(list);
  std::string part;
  while (std::getline(ss, part, ',')) {
    const auto a = part.find_first_not_of(" \t"), b = part.find_last_not_of(" \t");
    if (a != std::string::npos) out.push_back(part.substr(a, b - a + 1));
  }
  return out;
}

float lerp(float a, float b, float t) { return a + (b - a) * t; }

void clampCounts(int& lo, int& hi, int limit) {
  lo = std::clamp(lo, 0, limit);
  hi = std::clamp(hi, 0, limit);
  if (lo > hi) hi = lo;  // raising the minimum raises the maximum
}

}  // namespace

R250::R250(int32_t seed) {
  ParkMiller lcg(seed);
  for (uint32_t& w : buf_) w = uint32_t(lcg.next());
  for (uint32_t& w : buf_)
    if (lcg.next() > 0x40000000) w |= 0x80000000u;
  uint32_t msb = 0x80000000u, mask = 0xFFFFFFFFu;
  for (int j = 0; j < 32; ++j) {
    uint32_t& w = buf_[7 * j + 3];
    w = (w & mask) | msb;
    mask >>= 1;
    msb >>= 1;
  }
}

uint32_t R250::next() {
  const int j = index_ >= 147 ? index_ - 147 : index_ + 103;
  const uint32_t n = buf_[index_] ^= buf_[j];
  index_ = index_ + 1 == 250 ? 0 : index_ + 1;
  return n;
}

int replicatorCellCount(int32_t seed, int cx, int cy, int minObjects, int maxObjects, int limit) {
  clampCounts(minObjects, maxObjects, limit);
  R250 r(seed + 256 * (cy & 255) + (cx & 255));
  const uint32_t first = r.next();
  return minObjects == maxObjects ? minObjects : minObjects + int(first % uint32_t(maxObjects - minObjects + 1));
}

namespace {

// Calls `grow(r, wx, wy, count)` for each cell of `s` around `control`
// whose corner is in the box, `r` positioned after the count draw.
template <typename Grow>
void forEachCell(const ReplicatorState& s, int limit, const V3& control, Grow grow) {
  int lo = s.minObjects, hi = s.maxObjects;
  clampCounts(lo, hi, limit);
  const int radius = std::clamp(s.radius, 1, 64);
  const int ccx = int(std::floor(control.x / kReplicatorCell)), ccy = int(std::floor(control.y / kReplicatorCell));
  for (int j = -radius; j <= radius; ++j)
    for (int i = -radius; i <= radius; ++i) {
      const int cx = ccx + i, cy = ccy + j;
      const float wx = float(cx) * kReplicatorCell, wy = float(cy) * kReplicatorCell;
      if (!(float(s.boxMin[0]) <= wx && wx < float(s.boxMax[0]) && float(s.boxMin[1]) <= wy &&
            wy < float(s.boxMax[1])))
        continue;
      R250 r(s.seed + 256 * (cy & 255) + (cx & 255));
      const uint32_t first = r.next();
      const int count = lo == hi ? lo : lo + int(first % uint32_t(hi - lo + 1));
      if (!grow(r, wx, wy, count)) return;
    }
}

bool slopeAllowed(const ReplicatorState& s, const V3& n) {
  if (s.allowedSlope <= 0) return true;
  return std::acos(std::clamp(n.z, -1.0f, 1.0f)) <= float(s.allowedSlope) * 3.14159265f / 180.0f;
}

}  // namespace

int scatterReplicators(Scene& scene, const GhostTable& ghosts, const Terrain& terrain, const V3& control,
                       Resources& res) {
  int added = 0;
  for (const auto& [index, g] : ghosts) {
    const bool shapes = g.className == "DynamicShapeReplicator";
    const bool grass = g.className == "DynamicGrass" || g.className == "DynamicGrassReplicator";
    if ((!shapes && !grass) || !g.replicator.init) continue;
    const ReplicatorState& s = g.replicator;
    if (s.hide || !s.allowTerrain || !terrain.present) continue;
    std::vector<std::string> names = splitShapes(s.shapeFiles);
    if (shapes) {
      names.erase(std::remove_if(names.begin(), names.end(), [&](const std::string& n) { return !res.shape(n); }),
                  names.end());
      if (names.empty()) continue;
      forEachCell(s, kMaxShapeCount, control, [&](R250& r, float wx, float wy, int count) {
        for (int k = 0; k < count; ++k) {
          if (added >= kMaxReplicas) return false;
          const float px = wx + r.unit() * kReplicatorCell, py = wy + r.unit() * kReplicatorCell;
          const std::string& shape = names[r.next() % names.size()];
          const V3 scale{lerp(s.scaleMin.x, s.scaleMax.x, r.unit()), lerp(s.scaleMin.y, s.scaleMax.y, r.unit()),
                         lerp(s.scaleMin.z, s.scaleMax.z, r.unit())};
          const V3 turn{lerp(s.rotateMin.x, s.rotateMax.x, r.unit()), lerp(s.rotateMin.y, s.rotateMax.y, r.unit()),
                        lerp(s.rotateMin.z, s.rotateMax.z, r.unit())};
          float z;
          V3 n;
          if (!terrainHeightAt(terrain, px, py, z, &n) || !slopeAllowed(s, n)) continue;
          const float d2r = 3.14159265f / 180.0f;
          M4 m = M4::translation({px, py, z + s.offsetZ}) * graalRotation({0, 0, 1}, turn.z * d2r) *
                 graalRotation({0, 1, 0}, turn.y * d2r) * graalRotation({1, 0, 0}, turn.x * d2r);
          if (std::isfinite(scale.x) && std::isfinite(scale.y) && std::isfinite(scale.z) &&
              (scale.x != 0 || scale.y != 0 || scale.z != 0))
            m = m * M4::scale(scale);
          SceneObject so;
          so.ghost = -1;  // a copy: not moved as its ghost
          so.shape = shape;
          so.transform = m;
          scene.objects.push_back(so);
          ++added;
        }
        return true;
      });
      continue;
    }
    // Grass (Graal_analysis PR #931): small flat pieces lying on the
    // ground, textured from the names in shapefiles, all in one mesh.
    if (names.empty()) names.push_back("");
    auto shape = std::make_shared<Shape>();
    shape->kind = Shape::k3ds;
    for (const std::string& n : names) {
      Material m;
      m.name = n;
      m.texture = n;
      shape->materials.push_back(m);
    }
    Mesh mesh;
    mesh.name = "grass";
    int pieces = 0;
    forEachCell(s, kMaxGrassCount, control, [&](R250& r, float wx, float wy, int count) {
      for (int k = 0; k < count; ++k) {
        if (added >= kMaxReplicas) return false;
        const float px = wx + r.unit() * kReplicatorCell, py = wy + r.unit() * kReplicatorCell;
        const int mat = int(r.next() % names.size());
        float sx = lerp(s.scaleMin.x, s.scaleMax.x, r.unit()), sy = lerp(s.scaleMin.y, s.scaleMax.y, r.unit());
        if (!(std::isfinite(sx) && sx > 0)) sx = 1;
        if (!(std::isfinite(sy) && sy > 0)) sy = 1;
        const float turn = lerp(s.rotateMin.z, s.rotateMax.z, r.unit()) * 3.14159265f / 180.0f;
        float z;
        V3 n;
        if (!terrainHeightAt(terrain, px, py, z, &n) || !slopeAllowed(s, n)) continue;
        const float hx = kGrassPiece * 0.5f * sx, hy = kGrassPiece * 0.5f * sy;
        const float c = std::cos(turn), sn = std::sin(turn);
        const uint32_t base = uint32_t(mesh.vertices.size());
        const float corners[4][2] = {{-1, -1}, {1, -1}, {1, 1}, {-1, 1}};
        for (const auto& k2 : corners) {
          const float ox = k2[0] * hx, oy = k2[1] * hy;
          const float x = px + ox * c - oy * sn, y = py + ox * sn + oy * c;
          float vz = z;
          terrainHeightAt(terrain, x, y, vz);  // follows the ground; off the grid keeps the centre's height
          Vertex v;
          v.position = {x, y, vz + s.offsetZ + kGrassLift};
          v.normal = n;
          v.u = k2[0] > 0 ? 1.0f : 0.0f;
          v.v = k2[1] > 0 ? 1.0f : 0.0f;
          mesh.vertices.push_back(v);
        }
        mesh.triangles.push_back({{base, base + 1, base + 2}, mat});
        mesh.triangles.push_back({{base, base + 2, base + 3}, mat});
        ++pieces;
        ++added;
      }
      return true;
    });
    if (!pieces) continue;
    shape->meshes.push_back(std::move(mesh));
    shape->computeBounds();
    SceneObject so;
    so.ghost = -1;
    so.shape = "(grass)";
    so.transform = M4::identity();
    so.direct = shape.get();
    scene.owned.push_back(shape);
    scene.objects.push_back(so);
  }
  return added;
}

bool scenePositionOf(const Scene& scene, int ghost, V3& out) {
  if (ghost < 0) return false;
  for (const SceneObject& o : scene.objects)
    if (o.ghost == ghost) {
      out = o.transform.point({0, 0, 0});
      return true;
    }
  for (const SceneTag& t : scene.tags)
    if (t.ghost == ghost) {
      out = t.transform.point({0, 0, 0});
      return true;
    }
  return false;
}

}  // namespace graal3d::render
