// One frame of the 3D world: the sky box, then every object's shape lit
// lit as the 5.12 lights it (only the sky takes the fog).
//
// Rebuild choices, to be checked side by side with a real 5.12 in the lab:
// - Objects and water are never fogged (lab fog run under Mesa: cubes out
//   to 800 m drawn untinted; the Sky's visible distance changed nothing).
//   They are cut at the client's own draw distance, visibledistance3D in
//   game_config.txt: 1000 by default, at most 2400 (T3D-075, Graal_analysis
//   PR #962). The far plane is gVisibleDistance3D.
// - The sky (lab T3D-046, real 5.12): entries 0 to 3 of the sky line draw
//   on -y, +x, +y and -x, each mirrored left to right with up still up;
//   entry 4 on top, its image's top toward +y; entry 5, the floor, only
//   when the Sky's second option is set.
//   Below the horizon is the fog colour, and a band of it fades up
//   from the horizon (its height, kSkyFogBand of the box's half-height,
//   is the rebuild's own). With the first option off, the solid colour
//   fills the faces instead of their images. The box is not otherwise
//   fogged. One face spans the default 90-degree view, as in the client
//   (sky grid S1 under Mesa; its field of view measured 89.4 degrees).
// - Lighting (lighting probe and follow-ups 10 and 11, real 5.12 under
//   Mesa): the Sun's direction, colour and ambient shade nothing, on any
//   kind of shape. A .3ds face is lit by a fixed light from about
//   (-x, -y, +z) in the world: 1.0 facing it, 0.85 facing away (the
//   rebuild's curve: min(1, 0.85 + max(0, n . l))). Without a Sun a .3ds
//   draws at a quarter, a .dts and a .dif black, terrain unchanged.
//   .dts, .dif, .ft and terrain otherwise draw at full light; .dif
//   lightmaps are not drawn (the client showed none).
// - A textured material draws its texture as is; an untextured one its
//   diffuse colour.
// - Name tags (scene.cpp: only on objects with a movetype; the real 5.12
//   shows none on a static object): each tagged object's nickname is placed centred just above
//   its shape's bounds (2 m above its origin with no shape), its chat one
//   line above that. Tags are not hidden behind other objects and are
//   left out past the visible distance or off screen.
#pragma once
#include <string>

#include "raster.hpp"
#include "resources.hpp"
#include "scene.hpp"

namespace graal3d::render {

constexpr float kSkyFogBand = 0.25f;
// A .ft tree GameObject never draws on the real 5.12 (lab: flags 0, 0x08,
// 0x18; defaultLevels 1, 2, 6; the file and its texture download, nothing
// is logged). The tree is still read and grown (read_ft.hpp); a host may
// set this to draw it.
inline bool gDrawFtTrees = false;
// The draw distance: the client's visibledistance3D (T3D-075), 1000 by
// default and clamped to 2400 as the 5.12 clamps it. A host sets it from
// the player's game_config.txt with setVisibleDistance3D.
constexpr float kDefaultVisibleDistance3D = 1000.0f;
constexpr float kMaxVisibleDistance3D = 2400.0f;
inline float gVisibleDistance3D = kDefaultVisibleDistance3D;
// Sets gVisibleDistance3D, clamped to (0, 2400]; returns what it set. A
// value that is not a positive number leaves the default.
inline float setVisibleDistance3D(float d) {
  gVisibleDistance3D = !(d > 0) ? kDefaultVisibleDistance3D : (d > kMaxVisibleDistance3D ? kMaxVisibleDistance3D : d);
  return gVisibleDistance3D;
}
// Per build. 4.20r8 fetches a .3ds material's texture but does not apply
// it: the material draws plain white, while one with no texture draws its
// colour (lab batch 2, real 4.20r8 and 5.12 under Mesa, 2026-11-26). Its
// terrain is white too, as it never asks for heights.info or a terrain
// texture (T3D-117). Off for 5.x.
inline bool gShapeTexturesWhite = false;
// Sets the per-build switches from the engine's build string ("4.20r8",
// "5.12", ...). Only 4.20 is measured; other builds keep the 5.12's look.
// 4.20r8 also takes a replicator's ghost and grows no cover under GDI or
// Mesa (PR #951, lab batch 1).
inline bool gReplicatorCover = true;
inline void setClientBuild(const std::string& build) {
  const bool v420 = build.rfind("4.20", 0) == 0;
  gShapeTexturesWhite = v420;
  gReplicatorCover = !v420;
}
constexpr float kNoSunLight = 0.25f;  // a .3ds without a Sun
constexpr float kFixedLightFloor = 0.85f;

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
