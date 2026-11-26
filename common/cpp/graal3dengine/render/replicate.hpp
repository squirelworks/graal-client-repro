// Replicator ground cover (Graal_analysis torque/replicators-512.md, the
// real 5.12): copies of a DynamicShapeReplicator's shapes on 8-unit cells
// in a (2r+1)^2 block around the control object, a cell growing only when
// its corner lies in the world-space x/y box. Each cell's count comes from
// stock Torque's R250 stream seeded with seed + 256 (cy & 255) + (cx & 255).
//
// DynamicGrass and DynamicGrassReplicator grow over the same cells: flat
// square cards about 0.6 across lying on the ground, each at its own random
// yaw (not the shaperotate range; PR #973),
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
// Not modelled: on the real 5.12 a replicator with radius 1, one object a
// cell and scale 1 all together grows nothing, though any one of those
// alone grows (PR #973; the reason is not known yet).
//
// The rebuild's own until a lab check: an animated shape's extra draw
// (r mod 64 + 1) is not taken, as no shape here animates yet; which draw
// gives a grass card's yaw, and its lift; no terrain alignment; cover only on terrain (interiors, statics and
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
// A grass card's side before its x and y scale: about 0.6 (an overhead
// ruler, Graal_analysis PR #973). Cards lie flat; kGrassMaxTilt is kept for
// a lab that sees them tilt. The lift against depth fighting is ours.
constexpr float kGrassCard = 0.6f;
constexpr float kGrassMaxTilt = 0.0f;
constexpr float kGrassLift = 0.02f;

// Stock Torque's R250 (MRandomR250): a 250-word shift register seeded
// from a Park-Miller stream.
class R250 {
 public:
  explicit R250(int32_t seed);
  // randI: the updated word shifted right once (31 bits), as stock Torque.
  uint32_t next();
  // The 5.12's copy offset: next() / 2^31, in [0, 1) (lab 15 fit).
  float unit() { return float(double(next()) / 2147483648.0); }

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
