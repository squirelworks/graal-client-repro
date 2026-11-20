#include "world.hpp"

#include <cstring>

namespace graal3d {

namespace {

Vec3 readVec(BitReader& r) {
  Vec3 v;
  v.x = r.f32();
  v.y = r.f32();
  v.z = r.f32();
  return v;
}

void writeVec(BitWriter& w, const Vec3& v) {
  w.f32(v.x);
  w.f32(v.y);
  w.f32(v.z);
}

bool isMovement(const std::string& t) { return t == "interpolate" || t == "list" || t == "rigid"; }

float asFloat(uint32_t u) {
  float f;
  static_assert(sizeof f == sizeof u, "f32");
  std::memcpy(&f, &u, sizeof f);
  return f;
}

void readMovement(BitReader& r, const std::string& type, MovementData& m) {
  if (type == "list") {
    m.list.clear();
    while (r.flag() && !r.overrun()) {
      std::array<uint32_t, 8> e{};
      for (auto& v : e) v = r.u32();
      m.list.push_back(e);
    }
    if (!m.list.empty()) m.position = listEntryPosition(m.list.back());
  } else {
    m.position = readVec(r);
    for (auto& q : m.rotation) q = static_cast<uint8_t>(r.bits(8));
    for (auto& v : m.vectors) v = static_cast<uint16_t>(r.bits(9));
    m.flag = r.flag();
  }
}

void writeMovement(BitWriter& w, const std::string& type, const MovementData& m) {
  if (type == "list") {
    if (m.list.empty()) {
      // One entry at the current position.
      w.flag(true);
      writeVec(w, m.position);
      for (int i = 0; i < 5; ++i) w.u32(0);
    }
    for (const auto& e : m.list) {
      w.flag(true);
      for (auto v : e) w.u32(v);
    }
    w.flag(false);
  } else {
    writeVec(w, m.position);
    for (auto q : m.rotation) w.bits(q, 8);
    for (auto v : m.vectors) w.bits(v & 0x1FF, 9);
    w.flag(m.flag);
  }
}

}  // namespace

bool readGameObjectUpdate(BitReader& r, GameObjectState& o, uint32_t* sections) {
  uint32_t got = 0;
  auto has = [&](int section) {
    const bool b = r.flag();
    if (b) got |= 1u << (section - 1);
    return b;
  };
  if (has(1)) o.name = r.pstring();
  if (has(2)) o.velocity = readVec(r);
  if (has(3)) o.shape = r.pstring();
  if (has(4)) o.skin = r.pstring();
  if (has(5)) {
    o.position = readVec(r);
    o.axis = readVec(r);
    o.angle = r.f32();
    o.hasTransform = true;
  }
  if (has(6)) {
    const std::string type = r.pstring();
    // A new movetype makes a new movement object; the old data goes.
    if (type != o.movetype) {
      o.hasMovementData = false;
      o.movement = MovementData();
    }
    o.movetype = type;
    o.hasMovement = isMovement(o.movetype);
  }
  // Section 7's flag is always on the wire; its data only while the object
  // has a movement object.
  if (r.flag() && o.hasMovement) {
    got |= 1u << 6;
    readMovement(r, o.movetype, o.movement);
    o.hasMovementData = true;
    ++o.movementSerial;
  }
  if (has(8)) {
    const uint32_t len = r.bits(14);  // the shape object's own data
    r.seek(r.pos() + len);
  }
  if (has(9)) o.chat = r.pstring();
  if (has(10)) o.scriptClasses = r.pstring();
  if (has(11))
    for (auto& a : o.attr)
      if (r.flag()) a = r.pstring();
  if (has(12)) {
    o.nickname = r.pstring();
    for (auto& c : o.nickColor) c = static_cast<uint8_t>(r.bits(8));
  }
  if (has(13)) o.flags = static_cast<uint16_t>(r.bits(16));
  if (sections) *sections = got;
  return !r.overrun();
}

void writeGameObjectUpdate(BitWriter& w, const GameObjectState& o, uint32_t s) {
  auto on = [&](int section) { return (s >> (section - 1)) & 1; };
  if (w.flag(on(1))) w.pstring(o.name);
  if (w.flag(on(2))) writeVec(w, o.velocity);
  if (w.flag(on(3))) w.pstring(o.shape);
  if (w.flag(on(4))) w.pstring(o.skin);
  if (w.flag(on(5))) {
    writeVec(w, o.position);
    writeVec(w, o.axis);
    w.f32(o.angle);
  }
  if (w.flag(on(6))) w.pstring(o.movetype);
  if (w.flag(on(7) && o.hasMovement && o.hasMovementData)) writeMovement(w, o.movetype, o.movement);
  w.flag(false);  // no shape data
  if (w.flag(on(9))) w.pstring(o.chat);
  if (w.flag(on(10))) w.pstring(o.scriptClasses);
  if (w.flag(on(11)))
    for (const auto& a : o.attr)
      if (w.flag(!a.empty())) w.pstring(a);
  if (w.flag(on(12))) {
    w.pstring(o.nickname);
    for (auto c : o.nickColor) w.bits(c, 8);
  }
  if (w.flag(on(13))) w.bits(o.flags, 16);
}

Vec3 listEntryPosition(const std::array<uint32_t, 8>& e) {
  Vec3 v;
  v.x = asFloat(e[0]);
  v.y = asFloat(e[1]);
  v.z = asFloat(e[2]);
  return v;
}

bool readCameraUpdate(BitReader& r, CameraState& c) {
  if (!readGameObjectUpdate(r, c.object)) return false;
  if (r.flag()) c.mode = static_cast<int>(r.bits(1));
  if (r.flag()) c.followGhost = r.flag() ? static_cast<int>(r.bits(12)) : -1;
  return !r.overrun();
}

bool readSunUpdate(BitReader& r, SunState& s) {
  if (!r.flag()) return !r.overrun();
  s.init = true;
  s.name = r.pstring();
  s.direction = readVec(r);
  for (auto& f : s.color) f = r.f32();
  for (auto& f : s.ambient) f = r.f32();
  return !r.overrun();
}

bool readSkyUpdate(BitReader& r, SkyState& s) {
  const bool init = r.flag();
  if (init) {
    s.init = true;
    s.name = r.pstring();
  }
  if (r.flag()) {
    s.visibleDistance = r.f32();
    s.textures = r.pstring();
  }
  if (init) s.fogColor = readVec(r);
  return !r.overrun();
}

}  // namespace graal3d
