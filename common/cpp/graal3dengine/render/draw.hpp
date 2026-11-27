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
//   draws at a quarter, a .dts and a .dif black. Terrain draws at full
//   light without a Sun and is shaded by a fixed light with one
//   (T3D-162). .dts, .dif and .ft otherwise draw at full light;
//   .dif lightmaps are not drawn (the client showed none).
// - A textured material draws its texture as is; an untextured one its
//   diffuse colour.
// - Name tags (scene.cpp: only on objects with a movetype; the real 5.12
//   shows none on a static object): each tagged object's nickname is placed centred just above
//   its shape's bounds (2 m above its origin with no shape), its chat one
//   line above that. Tags are not hidden behind other objects and are
//   left out past the visible distance or off screen.
#pragma once
#include <functional>
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
// colour (lab batch 2, real 4.20r8 and 5.12 under Mesa, 2026-11-26). Off
// for 5.x.
inline bool gShapeTexturesWhite = false;
// 4.20r8 textures its terrain only when heights.info names the texture
// with its .png extension (from the second visit); a bare name, as the
// 5.12 takes, stays white. Its terrain is never shaded, Sun or not, though
// a Sun lights its shapes (lab batch L).
inline bool gTerrainNeedsPngName = false;
inline bool gTerrainShading = true;
// Sets the per-build switches from the engine's build string ("4.20r8",
// "5.12", ...). Only 4.20 is measured; other builds keep the 5.12's look.
// 4.20r8 also takes a replicator's ghost and grows no cover under GDI or
// Mesa (PR #951, lab batch 1).
inline bool gReplicatorCover = true;
inline void setClientBuild(const std::string& build) {
  const bool v420 = build.rfind("4.20", 0) == 0;
  gShapeTexturesWhite = v420;
  gTerrainNeedsPngName = v420;
  gTerrainShading = !v420;
  gReplicatorCover = !v420;
}
constexpr float kNoSunLight = 0.25f;  // a .3ds without a Sun
// Terrain with a Sun (T3D-162, real 5.12 under Mesa): one fixed light
// toward about (-0.683, -0.683, 0.259) (azimuth 225, about 15 degrees up),
// whatever the Sun's direction; the Sun only switches it on. Brightness
// min(cap, ambient + diffuse * max(0, n . l)), as fitted in the lab.
// Without a Sun the terrain draws unshaded at full light.
constexpr float kTerrainAmbient = 0.615f;
constexpr float kTerrainDiffuse = 0.96f;
constexpr float kTerrainLightCap = 0.99f;
constexpr float kFixedLightFloor = 0.85f;
// The two fixed light directions (toward the light): the .3ds light from
// about (-x, -y, +z), and the terrain's (T3D-162). Normalised.
inline V3 fixedLightDirection() { return normalize(V3{-1, -1, 1}); }
inline V3 terrainLightDirection() { return normalize(V3{-0.683f, -0.683f, 0.259f}); }

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

// The pieces of drawScene another backend shares (the Frankenstein
// 6.037's OpenGL renderer draws the same frame through the GPU), so both
// make the same choices.
//
// The clear colour: the Sky's fog colour, black without a Sky.
uint32_t sceneFogColor(const Scene& scene);
// A vertex's light for a shape of `kind` (draw.hpp's lighting rules), from
// its normal turned into the world (not normalised).
float vertexLight(Shape::Kind kind, bool sun, const V3& worldNormal);
// What a triangle of `material` in `mesh` of `shape` draws with: its
// texture (looked up, so asked for when missing, unless `named` is false),
// colour, alpha test and, for a terrain layer, the additive weight map.
// `fogColor` from sceneFogColor.
RasterState materialState(const Shape& shape, const Mesh& mesh, const Material& material, Resources& resources,
                          bool named, uint32_t fogColor);
// The sky box's and a water block's triangles in world space, in the
// order drawScene draws them, with their states.
using TriangleSink = std::function<void(const RasterVertex&, const RasterVertex&, const RasterVertex&,
                                        const RasterState&)>;
void skyBoxTriangles(const Scene& scene, Resources& resources, float farPlane, uint32_t fogColor,
                     const TriangleSink& sink);
// Returns the number of triangles.
int waterTriangles(const WaterSurface& water, double seconds, uint32_t fogColor, Resources& resources,
                   const TriangleSink& sink);

}  // namespace graal3d::render
