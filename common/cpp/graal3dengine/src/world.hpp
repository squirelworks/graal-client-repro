// The objects the 3D server ghosts to the client, as far as protocols 21
// and 24 describe them (Graal_analysis torque/udp-session.md §8).
#pragma once

#include "bits.hpp"

#include <array>
#include <map>
#include <string>

namespace graal3d {

struct Vec3 {
  float x = 0, y = 0, z = 0;
};

// The thirteen sections of a GameObject update, kept as the last values
// seen. `has*` say a section has arrived at least once.
struct GameObjectState {
  std::string name;
  Vec3 velocity;
  std::string shape, skin;
  Vec3 position, axis{0, 0, 1};
  float angle = 0;
  std::string movetype;
  bool hasMovement = false;  // movetype interpolate, list or rigid
  std::string chat, scriptClasses;
  std::array<std::string, 8> attr;
  std::string nickname;
  uint8_t nickColor[4] = {255, 255, 255, 255};
  uint16_t flags = 0;
  bool hasTransform = false;
};

// Reads one GameObject update into `o` (the section flags, then each
// payload that is present). False when the stream ran out.
bool readGameObjectUpdate(BitReader& r, GameObjectState& o);
// Writes the sections of `o` named by `sections` (bit 0 = section 1).
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

// Sky: the name and the material list. The rest of the reader's shape is
// in the note; this rebuild does not draw a sky yet, and the ghost's
// length prefix skips what is not read.
struct SkyState {
  std::string name;
  float visibleDistance = 0;
  std::string textures;  // front, right, back, left, top, bottom
  Vec3 fogColor;
  bool init = false;
};
bool readSkyUpdate(BitReader& r, SkyState& s);

// One ghost: its class (by name) and the state of the classes this
// rebuild reads. Others are kept by class name only.
struct Ghost {
  std::string className;
  GameObjectState object;  // GameObject and Camera
  CameraState camera;
  SunState sun;
  SkyState sky;
  int updates = 0;
};

using GhostTable = std::map<int, Ghost>;

}  // namespace graal3d
