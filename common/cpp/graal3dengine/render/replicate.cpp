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

// Uniform between two bounds, a minimum above its maximum swapped first.
float ranged(float lo, float hi, float t) { return lo <= hi ? lerp(lo, hi, t) : lerp(hi, lo, t); }

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

// The ground under (x, y) as the 5.12 finds it: a ray down from z 2000 to
// -2000 that must hit inside the box's z range and no steeper than the
// slope limit (Graal_analysis PR #931, replicators-512.md).
bool groundAt(const ReplicatorState& s, const Terrain& terrain, float x, float y, float& z, V3& n);

bool slopeAllowed(const ReplicatorState& s, const V3& n) {
  if (s.allowedSlope <= 0) return true;
  return std::acos(std::clamp(n.z, -1.0f, 1.0f)) <= float(s.allowedSlope) * 3.14159265f / 180.0f;
}

bool groundAt(const ReplicatorState& s, const Terrain& terrain, float x, float y, float& z, V3& n) {
  if (!terrainHeightAt(terrain, x, y, z, &n)) return false;
  if (z > 2000 || z < -2000) return false;
  if (z < float(s.boxMin[2]) || z > float(s.boxMax[2])) return false;
  return slopeAllowed(s, n);
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
      if (names.empty() || std::none_of(names.begin(), names.end(), [&](const std::string& n) { return res.shape(n) != nullptr; }))
        continue;
      forEachCell(s, kMaxShapeCount, control, [&](R250& r, float wx, float wy, int count) {
        for (int k = 0; k < count; ++k) {
          if (added >= kMaxReplicas) return false;
          // Within half a cell of the corner, then the ground ray; only a
          // copy that lands draws the rest: the shape (from the whole list),
          // turn z, y, x, then scale z, y, x (replicators-512.md).
          const float px = wx + (r.unit() - 0.5f) * kReplicatorCell, py = wy + (r.unit() - 0.5f) * kReplicatorCell;
          float z;
          V3 n;
          if (!groundAt(s, terrain, px, py, z, n)) continue;
          const std::string& shape = names[r.next() % names.size()];
          V3 turn, scale;
          turn.z = ranged(s.rotateMin.z, s.rotateMax.z, r.unit());
          turn.y = ranged(s.rotateMin.y, s.rotateMax.y, r.unit());
          turn.x = ranged(s.rotateMin.x, s.rotateMax.x, r.unit());
          scale.z = ranged(s.scaleMin.z, s.scaleMax.z, r.unit());
          scale.y = ranged(s.scaleMin.y, s.scaleMax.y, r.unit());
          scale.x = ranged(s.scaleMin.x, s.scaleMax.x, r.unit());
          if (!res.shape(shape)) continue;  // a name we cannot load still takes its draws
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
    // Grass (Graal_analysis PR #931, #964): short upright billboards
    // standing on the ground and facing the camera, textured from the
    // names in shapefiles, all in one mesh.
    const V3 camera = scene.hasCamera ? scene.view.cameraToWorld.point({0, 0, 0}) : control;
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
      // A regular sub-grid, not random places: cols x rows pieces, each
      // dimension at most 16 (replicators-512.md), so 5 draws 4.
      if (count <= 0) return true;
      const int cols = std::clamp(int(std::sqrt(double(count))), 1, 16);
      const int rows = std::min(16, count / cols);
      for (int k = 0; k < cols * rows; ++k) {
        if (added >= kMaxReplicas) return false;
        const float px = wx + (float(k % cols) / float(cols) - 0.5f) * kReplicatorCell;
        const float py = wy + (float(k / cols) / float(rows) - 0.5f) * kReplicatorCell;
        const int mat = int(r.next() % names.size());
        float sx = lerp(s.scaleMin.x, s.scaleMax.x, r.unit()), sy = lerp(s.scaleMin.y, s.scaleMax.y, r.unit());
        if (!(std::isfinite(sx) && sx > 0)) sx = 1;
        if (!(std::isfinite(sy) && sy > 0)) sy = 1;
        const float turn = lerp(s.rotateMin.z, s.rotateMax.z, r.unit()) * 3.14159265f / 180.0f;
        float z;
        V3 n;
        if (!groundAt(s, terrain, px, py, z, n)) continue;
        (void)turn;  // drawn, but a billboard faces the camera (Graal_analysis PR #964)
        // A short upright piece standing on the ground, turned about z to
        // face the camera.
        const float halfWidth = kGrassWidth * 0.5f * sx, height = kGrassHeight * sy;
        float fx = camera.x - px, fy = camera.y - py;
        const float len = std::sqrt(fx * fx + fy * fy);
        if (len > 1e-4f) {
          fx /= len;
          fy /= len;
        } else {
          fx = 0;
          fy = -1;
        }
        const float rx = -fy, ry = fx;  // across the view
        const uint32_t base = uint32_t(mesh.vertices.size());
        const float corners[4][2] = {{-1, 0}, {1, 0}, {1, 1}, {-1, 1}};
        for (const auto& k2 : corners) {
          Vertex v;
          v.position = {px + rx * halfWidth * k2[0], py + ry * halfWidth * k2[0], z + s.offsetZ + height * k2[1]};
          v.normal = {fx, fy, 0};
          v.u = k2[0] > 0 ? 1.0f : 0.0f;
          v.v = k2[1] > 0 ? 0.0f : 1.0f;  // the texture's top at the top
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
