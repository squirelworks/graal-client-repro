// Replicator ground cover (Graal_analysis torque/replicators-512.md, the
// real 5.12): copies of a DynamicShapeReplicator's shapes on 8-unit cells
// in a (2r+1)^2 block around the control object, a cell growing only when
// its corner lies in the world-space x/y box. Each cell's count comes from
// stock Torque's R250 stream seeded with seed + 256 (cy & 255) + (cx & 255).
//
// The rebuild's own until a lab check: how each copy is placed in its cell
// (x, y, shape, scale and turn drawn in that order from the same stream),
// the slope test against the terrain normal, no terrain alignment, cover
// only on terrain, and at most kMaxReplicas copies in all.
#pragma once

#include <cstdint>

#include "resources.hpp"
#include "scene.hpp"
#include "terrain.hpp"

namespace graal3d::render {

constexpr float kReplicatorCell = 8.0f;
constexpr int kMaxReplicas = 20000;

// Stock Torque's R250 (MRandomR250): a 250-word shift register seeded
// from a Park-Miller stream.
class R250 {
 public:
  explicit R250(int32_t seed);
  uint32_t next();
  float unit() { return float(next() & 0x7FFFFFFF) / 2147483648.0f; }  // [0, 1)

 private:
  uint32_t buf_[250];
  int index_ = 0;
};

// The count a cell grows (min and max already clamped as the client does).
int replicatorCellCount(int32_t seed, int cx, int cy, int minObjects, int maxObjects);

// Adds the cover of every DynamicShapeReplicator in `ghosts` to `scene`
// around `control` (world), on `terrain`. Returns the copies added.
int scatterReplicators(Scene& scene, const GhostTable& ghosts, const Terrain& terrain, const V3& control,
                       Resources& res);

// Where `ghost` stands in `scene` (after applyMotion): the position its
// object or name tag was given. False when it has neither.
bool scenePositionOf(const Scene& scene, int ghost, V3& out);

}  // namespace graal3d::render
