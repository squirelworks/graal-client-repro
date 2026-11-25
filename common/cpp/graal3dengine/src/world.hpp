// The objects the 3D server ghosts to the client, as far as protocols 21
// and 24 describe them (Graal_analysis torque/udp-session.md §8).
#pragma once

#include "bits.hpp"

#include <array>
#include <map>
#include <string>
#include <vector>

namespace graal3d {

struct Vec3 {
  float x = 0, y = 0, z = 0;
};

// Section 7, the movement data of an object whose movetype made a
// movement object (torque/udp-session.md §8; the lab run of
// protocol/lab-appe-hosta-2026-11-20d.md, E#505). `interpolate` and
// `rigid` carry one target: a position (3 x f32), a rotation (4 x 8 bits;
// the lab server's identity rotation is 127, 127, 127, 255), six 9-bit
// vector parts and a flag. `list` carries entries of 8 x 32 bits; the
// first three are the position (f32), the other five were zeros in the
// lab and are kept as read.
struct MovementData {
  Vec3 position;
  uint8_t rotation[4] = {127, 127, 127, 255};
  uint16_t vectors[6] = {0, 0, 0, 0, 0, 0};
  bool flag = false;
  std::vector<std::array<uint32_t, 8>> list;
};

// The thirteen sections of a GameObject update, kept as the last values
// seen. `has*` say a section has arrived at least once.
struct GameObjectState {
  std::string name;
  Vec3 scale;  // section 2: the shape's scale (lab T3D-015; 0, 0, 0 = unset)
  std::string shape, skin;
  Vec3 position, axis{0, 0, 1};
  float angle = 0;
  std::string movetype;
  bool hasMovement = false;  // movetype interpolate, list or rigid
  MovementData movement;     // section 7, the last one read
  bool hasMovementData = false;
  uint32_t movementSerial = 0;  // counts the section 7 payloads read
  std::string chat, scriptClasses;
  std::array<std::string, 8> attr;
  std::string nickname;
  uint8_t nickColor[4] = {255, 255, 255, 255};
  uint16_t flags = 0;
  bool hasTransform = false;
};

// Reads one GameObject update into `o` (the section flags, then each
// payload that is present). False when the stream ran out. `sections`,
// when given, gets the sections the update carried (bit 0 = section 1).
bool readGameObjectUpdate(BitReader& r, GameObjectState& o, uint32_t* sections = nullptr);
// Writes the sections of `o` named by `sections` (bit 0 = section 1).
// Section 7 goes out only while `o` has a movement object and data.
void writeGameObjectUpdate(BitWriter& w, const GameObjectState& o, uint32_t sections);

struct CameraState {
  GameObjectState object;
  int mode = 0;
  int followGhost = -1;
};
bool readCameraUpdate(BitReader& r, CameraState& c);

struct SunState {
  std::string name;
  Vec3 direction;
  float color[4] = {0, 0, 0, 0}, ambient[4] = {0, 0, 0, 0};
  bool init = false;
};
bool readSunUpdate(BitReader& r, SunState& s);

// Sky: the reader's whole shape (torque/udp-session.md section 8); every
// part after the name is guarded, so a later update carries only what is
// set. The three unnamed bools and the solid colour are kept by position,
// as the Seihai gserver's `skyoptions` sends them.
struct SkyFogVolume {
  float values[6] = {0, 0, 0, 0, 0, 0};
  uint8_t flag = 0;
};
struct SkyCloudLayer {
  std::string texture;
  float height = 0, speed = 0;
};
struct SkyState {
  std::string name;
  float visibleDistance = 0;
  std::string textures;  // front, right, back, left, top, bottom
  Vec3 fogColor;
  std::vector<SkyFogVolume> fogVolumes;
  uint8_t options[3] = {0, 0, 0};  // the three 8-bit bools, in wire order
  Vec3 solidColor;
  SkyCloudLayer clouds[3];
  Vec3 windVelocity;
  bool init = false;
};
// Fog volumes accepted in one Sky update (rebuild policy).
constexpr uint32_t kMaxSkyFogVolumes = 64;
bool readSkyUpdate(BitReader& r, SkyState& s);

// TerrainBlock (Graal_analysis torque/terrain-512.md section 1): settings
// only, every update one guarded block. The heights arrive as
// TerrainChunkEvents.
struct TerrainBlockState {
  bool init = false;
  std::string name;
  uint32_t squareSize = 0;  // metres per square (servers send 8)
  bool repeat = false;
};
bool readTerrainBlockUpdate(BitReader& r, TerrainBlockState& t);

// WaterBlock (terrain-512.md section 5): only the name is guarded; every
// update carries the whole block.
struct WaterBlockState {
  bool init = false;
  std::string name;
  Vec3 position;
  float rotation[4] = {0, 0, 0, 1};  // quaternion x, y, z, w
  Vec3 scale;                         // extent in metres from the corner at position (any size, lab)
  std::string textures[5];            // surface, specular mask, env over, env under, shore
  std::string submergeTextures[2];
  uint32_t liquidType = 0;
  float density = 0, viscosity = 0, waveMagnitude = 0, opacity = 0, envMapIntensity = 0;
  bool removeWetEdges = false, useDepthMask = false;
  float shading[12] = {};
  float specularColor[4] = {0, 0, 0, 0};
  float specularPower = 0;
  bool ignoreTerrain = false;
};
bool readWaterBlockUpdate(BitReader& r, WaterBlockState& w);

// The position a `list` entry carries (its first three values as f32).
Vec3 listEntryPosition(const std::array<uint32_t, 8>& entry);

// One ghost: its class (by name) and the state of the classes this
// rebuild reads. Others are kept by class name only.
struct Ghost {
  std::string className;
  GameObjectState object;  // GameObject and Camera
  CameraState camera;
  SunState sun;
  SkyState sky;
  TerrainBlockState terrain;
  WaterBlockState water;
  int updates = 0;
};

using GhostTable = std::map<int, Ghost>;

}  // namespace graal3d
