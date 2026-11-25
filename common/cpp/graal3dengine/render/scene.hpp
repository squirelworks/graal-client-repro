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

constexpr uint16_t kGameObjectEditorFlag = 0x04;

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
  // The second option: entry 5 drawn as the floor (lab; the third option
  // showed nothing).
  bool drawBottom = false;
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

// A WaterBlock's surface (terrain-512.md section 5): a flat rectangle at
// the block's top (its position plus its scale's z), over its scale's x
// and y, turned by its rotation. The
// 5.12 takes the scale only from 1024 up; a smaller block draws nothing
// (lab). Drawn with its surface texture at its opacity: the rebuild's own,
// with no waves, reflection or shore.
struct WaterSurface {
  M4 transform;
  float width = 0, depth = 0;
  std::string texture;
  float opacity = 1;
  float waveMagnitude = 0;  // the surface rises and falls (waveHeight)
};

// How far the water surface is off its rest height at world (x, y) at
// `seconds` (lab fit, real 5.12: a 5 x 5 grid at magnitude 1, r.m.s.
// error 0.005; Graal_analysis torque/terrain-512.md section 5): two equal
// waves, one along world x and one along world y, crests travelling toward
// -x and -y,
//   0.25 m (sin(w t + k x + phase) + sin(w t + k y + phase)),
// w about 0.984 rad/s (6.4 s), wavelength 2 pi / k about 126 units (a finer
// scan is queued). The phase is the rebuild's own (0).
constexpr float kWaveOmega = 0.984f;       // radians a second
constexpr float kWaveLength = 126.0f;      // world units
float waveHeight(float magnitude, double seconds, float x = 0, float y = 0);

struct Scene {
  bool hasCamera = false;
  double time = 0;  // seconds, for the water's waves
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

// The transform the wire gives a shape, and a camera (math.hpp: the two
// turn opposite ways).
M4 objectTransform(const GameObjectState& o);
M4 cameraTransform(const GameObjectState& o);

}  // namespace graal3d::render
