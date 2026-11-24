// What the renderer draws, built from the ghosts the link holds.
//
// A protocol-24 world is its ghosts (Graal_analysis torque/udp-session.md
// section 8): each GameObject with a shape, the client's Camera, a Sun and
// a Sky. The 5.x client draws its 3D view only through a Camera: with just
// the control object the window stays black (the Seihai gserver's lab
// 2026-11-20, real 5.12 on Windows 10).
#pragma once

#include "math.hpp"
#include "raster.hpp"
#include "../src/world.hpp"

#include <string>
#include <vector>

namespace graal3d::render {

struct SceneObject {
  int ghost = -1;
  std::string shape;
  M4 transform;
};

struct SunLight {
  bool present = false;
  V3 direction{0, 0, -1};  // the way the light travels
  float color[3] = {1, 1, 1};
  float ambient[3] = {0, 0, 0};
};

struct SkyBox {
  bool present = false;
  std::string textures[6];  // front, right, back, left, top, bottom
  float visibleDistance = 0;
  float fogColor[3] = {0, 0, 0};
};

struct Scene {
  bool hasCamera = false;
  View view;
  SunLight sun;
  SkyBox sky;
  std::vector<SceneObject> objects;
};

// `cameraGhost` is the ghost the server named as the camera (-1 for none);
// `fovDegrees` the game section's field of view (0: not sent, 90 used).
Scene sceneFromGhosts(const GhostTable& ghosts, int cameraGhost, float fovDegrees);

// The rotation the wire gives an object, as a matrix (clients' sign rule).
M4 objectTransform(const GameObjectState& o);

}  // namespace graal3d::render
