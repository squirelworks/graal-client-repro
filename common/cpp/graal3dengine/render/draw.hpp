// One frame of the 3D world: the sky box, then every object's shape lit
// by the sun and fogged toward the sky's fog colour.
//
// Rebuild choices, to be checked side by side with a real 5.12 in the lab:
// - Nothing past the sky's visible distance is drawn (1000 units without a
//   Sky); fog rises linearly from half that distance to all of it.
// - The sky (lab T3D-046, real 5.12): entries 0 to 3 of the sky line draw
//   on -y, +x, +y and -x, each mirrored left to right with up still up;
//   entry 4 on top, its image's top toward +y; entry 5 is not drawn.
//   Below the horizon is black, and a band of the fog colour fades up
//   from the horizon (its height, kSkyFogBand of the box's half-height,
//   is the rebuild's own). With the first option off, the solid colour
//   fills the faces instead of their images. The box is not otherwise
//   fogged. Open: the client's faces look about twice as magnified, and
//   its visible distance did not change the frame.
// - Lighting per vertex: ambient + colour * max(0, n . -direction),
//   clamped; without a Sun everything is fully lit.
// - A textured material draws its texture as is; an untextured one its
//   diffuse colour.
// - Name tags: each tagged object's nickname is placed centred just above
//   its shape's bounds (2 m above its origin with no shape), its chat one
//   line above that. Tags are not hidden behind other objects and are
//   left out past the visible distance or off screen.
#pragma once

#include "raster.hpp"
#include "resources.hpp"
#include "scene.hpp"

namespace graal3d::render {

constexpr float kSkyFogBand = 0.25f;

// A line of text for the host to draw over the frame, centred on (x, y),
// its baseline at y.
struct Label {
  enum Kind { kNickname, kChat };
  int ghost = -1;
  Kind kind = kNickname;
  float x = 0, y = 0, depth = 0;
  std::string text;
  uint8_t color[4] = {255, 255, 255, 255};
};

struct DrawStats {
  int objectsDrawn = 0;
  int objectsMissing = 0;  // shape not here or not readable
  long triangles = 0;
  std::vector<Label> labels;  // nearest last, so later ones draw on top
};

// The tags' labels in a width by height frame, as drawScene gives them.
std::vector<Label> sceneLabels(const Scene& scene, Resources& resources, int width, int height);

DrawStats drawScene(Frame frame, const Scene& scene, Resources& resources);

}  // namespace graal3d::render
