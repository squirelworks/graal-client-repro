// One frame of the 3D world: the sky box, then every object's shape lit
// by the sun and fogged toward the sky's fog colour.
//
// Rebuild choices, to be checked side by side with a real 5.12 in the lab:
// - Nothing past the sky's visible distance is drawn (1000 units without a
//   Sky); fog rises linearly from half that distance to all of it.
// - The sky box faces: front +y, right +x, back -y, left -x, top +z,
//   bottom -z, each seen upright from inside; the top and bottom have
//   their top edge toward +y. The box is not fogged.
// - Lighting per vertex: ambient + colour * max(0, n . -direction),
//   clamped; without a Sun everything is fully lit.
// - A textured material draws its texture as is; an untextured one its
//   diffuse colour.
#pragma once

#include "raster.hpp"
#include "resources.hpp"
#include "scene.hpp"

namespace graal3d::render {

struct DrawStats {
  int objectsDrawn = 0;
  int objectsMissing = 0;  // shape not here or not readable
  long triangles = 0;
};

DrawStats drawScene(Frame frame, const Scene& scene, Resources& resources);

}  // namespace graal3d::render
