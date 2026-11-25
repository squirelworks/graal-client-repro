// What the renderer draws, built from the ghosts the link holds.
//
// A protocol-24 world is its ghosts (Graal_analysis torque/udp-session.md
// section 8): each GameObject with a shape, the client's Camera, a Sun and
// a Sky. The 5.x client draws its 3D view only through a Camera: with just
// the control object the window stays black (the Seihai gserver's lab
// 2026-11-20, real 5.12 on Windows 10).
#pragma once

#include "math.hpp"
#include "mesh.hpp"
#include "raster.hpp"
#include "../src/world.hpp"

#include <string>
#include <vector>

namespace graal3d::render {

struct SceneObject {
  int ghost = -1;
  std::string shape;
  M4 transform;
  // A shape the caller holds (the streamed terrain); used instead of
  // looking `shape` up when set.
  const Shape* direct = nullptr;
};

// A player's name tag and chat, from a GameObject with a nickname or chat
// (the multi-client view). Drawn over the frame by the host, which has
// the font (drawScene gives each tag's screen position as a Label).
struct SceneTag {
  int ghost = -1;
  std::string shape;  // its shape, for the anchor above it ("" for none)
  M4 transform;
  std::string nickname, chat;
  uint8_t color[4] = {255, 255, 255, 255};
};

struct SunLight {
  bool present = false;
  V3 direction{0, 0, -1};  // the way the light travels
  float color[3] = {1, 1, 1};
  float ambient[3] = {0, 0, 0};
};

struct SkyBox {
  bool present = false;
  std::string textures[6];  // by sky-line entry: -y, +x, +y, -x, up, (bottom, not drawn)
  bool useTextures = true;  // the first option; off: the solid colour fills the sky
  float solidColor[3] = {0, 0, 0};
  float visibleDistance = 0;
  float fogColor[3] = {0, 0, 0};
};

// The TerrainBlock's settings (terrain-512.md section 1). The heights come
// separately (terrain.hpp); a caller adds the terrain's shape as a
// SceneObject with `direct` set.
struct TerrainSettings {
  bool present = false;
  float squareSize = 8;  // the block's own; 0 (a create with init 0) is drawn as 8
  bool repeat = false;
};

// A WaterBlock's surface (terrain-512.md section 5): a flat rectangle from
// its position over its scale's x and y, turned by its rotation. The
// 5.12 takes the scale only from 1024 up; a smaller block draws nothing
// (lab). Drawn with its surface texture at its opacity: the rebuild's own,
// with no waves, reflection or shore.
struct WaterSurface {
  M4 transform;
  float width = 0, depth = 0;
  std::string texture;
  float opacity = 1;
};

struct Scene {
  bool hasCamera = false;
  View view;
  SunLight sun;
  SkyBox sky;
  TerrainSettings terrain;
  std::vector<SceneObject> objects;
  std::vector<WaterSurface> water;
  std::vector<SceneTag> tags;
};

// `cameraGhost` is the ghost the server named as the camera (-1 for none);
// `fovDegrees` the game section's field of view (0: not sent, 90 used).
Scene sceneFromGhosts(const GhostTable& ghosts, int cameraGhost, float fovDegrees);

// The rotation the wire gives an object, as a matrix (clients' sign rule).
M4 objectTransform(const GameObjectState& o);

}  // namespace graal3d::render
