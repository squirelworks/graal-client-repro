// Replicator ground cover (Graal_analysis torque/replicators-512.md, the
// real 5.12): copies of a DynamicShapeReplicator's shapes on 8-unit cells
// in a (2r+1)^2 block around the control object, a cell growing only when
// its corner lies in the world-space x/y box. Each cell's count comes from
// stock Torque's R250 stream seeded with seed + 256 (cy & 255) + (cx & 255).
//
// DynamicGrass and DynamicGrassReplicator grow over the same cells: cards
// about a metre across lying on the ground, each at its own yaw and tilt,
// textured from the names in shapefiles (an alpha texture draws as soft
// shapes), the count clamped to 0-100 (Graal_analysis PR #931, #964, #968
// under Mesa).
//
// Inside a cell (replicators-512.md, PR #931): a shape copy draws x then y
// from the cell's stream, within half a cell of the corner; grass sits on
// a regular sub-grid of cols = min(16, floor(sqrt(n))) by rows = min(16,
// floor(n / cols)). Each lands where a ray down from z 2000 to -2000 meets
// the ground, inside the box's z range and no steeper than the slope limit.
//
// After the ground ray a shape copy draws, from the same stream: the shape
// (r mod the list's length), turn z, y, x, then scale z, y, x, each
// uniform in its range with a minimum above its maximum swapped; it sits
// at the ground hit plus offsetz (replicators-512.md).
//
// The rebuild's own until a lab check: an animated shape's extra draw
// (r mod 64 + 1) is not taken, as no shape here animates yet; a grass
// piece's size (half a metre times its x/y scale), turn (z only) and lift;
// no terrain alignment; cover only on terrain (interiors, statics and
// water are not tried); and at most kMaxReplicas copies in all.
#pragma once

#include <cstdint>

#include "resources.hpp"
#include "scene.hpp"
#include "terrain.hpp"

namespace graal3d::render {

constexpr float kReplicatorCell = 8.0f;
constexpr int kMaxReplicas = 20000;
// Per-cell count limits: 0-20 for shapes, 0-100 for grass (Graal_analysis
// PR #931).
constexpr int kMaxShapeCount = 20;
constexpr int kMaxGrassCount = 100;
// A grass card's side before its x and y scale: about a metre (PR #968
// close-up); its largest tilt off the ground and its lift against depth
// fighting are the rebuild's own.
constexpr float kGrassCard = 1.0f;
constexpr float kGrassMaxTilt = 30.0f;
constexpr float kGrassLift = 0.02f;

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
int replicatorCellCount(int32_t seed, int cx, int cy, int minObjects, int maxObjects,
                        int limit = kMaxShapeCount);

// Adds the cover of every replicator in `ghosts` to `scene` around
// `control` (world), on `terrain`: a DynamicShapeReplicator's shapes as
// objects, a DynamicGrass or DynamicGrassReplicator's flat pieces as one
// shape held in `scene.owned`. Returns the copies and pieces added.
int scatterReplicators(Scene& scene, const GhostTable& ghosts, const Terrain& terrain, const V3& control,
                       Resources& res);

// Where `ghost` stands in `scene` (after applyMotion): the position its
// object or name tag was given. False when it has neither.
bool scenePositionOf(const Scene& scene, int ghost, V3& out);

}  // namespace graal3d::render
