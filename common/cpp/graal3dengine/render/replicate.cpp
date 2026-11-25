#include "replicate.hpp"

#include <algorithm>
#include <cmath>
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

void clampCounts(int& lo, int& hi) {
  lo = std::clamp(lo, 0, 20);
  hi = std::clamp(hi, 0, 20);
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

int replicatorCellCount(int32_t seed, int cx, int cy, int minObjects, int maxObjects) {
  clampCounts(minObjects, maxObjects);
  R250 r(seed + 256 * (cy & 255) + (cx & 255));
  const uint32_t first = r.next();
  return minObjects == maxObjects ? minObjects : minObjects + int(first % uint32_t(maxObjects - minObjects + 1));
}

int scatterReplicators(Scene& scene, const GhostTable& ghosts, const Terrain& terrain, const V3& control,
                       Resources& res) {
  int added = 0;
  for (const auto& [index, g] : ghosts) {
    if (g.className != "DynamicShapeReplicator" || !g.replicator.init) continue;
    const ReplicatorState& s = g.replicator;
    if (s.hide || !s.allowTerrain || !terrain.present) continue;
    std::vector<std::string> shapes;
    for (const std::string& n : splitShapes(s.shapeFiles))
      if (res.shape(n)) shapes.push_back(n);
    if (shapes.empty()) continue;
    int lo = s.minObjects, hi = s.maxObjects;
    clampCounts(lo, hi);
    const int radius = std::clamp(s.radius, 1, 64);
    const int ccx = int(std::floor(control.x / kReplicatorCell)), ccy = int(std::floor(control.y / kReplicatorCell));
    const float slopeLimit = float(s.allowedSlope) * 3.14159265f / 180.0f;
    for (int j = -radius; j <= radius && added < kMaxReplicas; ++j)
      for (int i = -radius; i <= radius && added < kMaxReplicas; ++i) {
        const float wx = float(ccx + i) * kReplicatorCell, wy = float(ccy + j) * kReplicatorCell;
        if (!(float(s.boxMin[0]) <= wx && wx < float(s.boxMax[0]) && float(s.boxMin[1]) <= wy &&
              wy < float(s.boxMax[1])))
          continue;
        const int cx = int(wx / kReplicatorCell), cy = int(wy / kReplicatorCell);  // toward zero
        R250 r(s.seed + 256 * (cy & 255) + (cx & 255));
        const uint32_t first = r.next();
        const int count = lo == hi ? lo : lo + int(first % uint32_t(hi - lo + 1));
        for (int k = 0; k < count && added < kMaxReplicas; ++k) {
          const float px = wx + r.unit() * kReplicatorCell, py = wy + r.unit() * kReplicatorCell;
          const std::string& shape = shapes[r.next() % shapes.size()];
          const V3 scale{lerp(s.scaleMin.x, s.scaleMax.x, r.unit()), lerp(s.scaleMin.y, s.scaleMax.y, r.unit()),
                         lerp(s.scaleMin.z, s.scaleMax.z, r.unit())};
          const V3 turn{lerp(s.rotateMin.x, s.rotateMax.x, r.unit()), lerp(s.rotateMin.y, s.rotateMax.y, r.unit()),
                        lerp(s.rotateMin.z, s.rotateMax.z, r.unit())};
          float z;
          V3 n;
          if (!terrainHeightAt(terrain, px, py, z, &n)) continue;
          if (s.allowedSlope > 0 && std::acos(std::clamp(n.z, -1.0f, 1.0f)) > slopeLimit) continue;
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
      }
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
