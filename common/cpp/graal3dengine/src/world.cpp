#include "world.hpp"

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

}  // namespace

bool readGameObjectUpdate(BitReader& r, GameObjectState& o) {
  if (r.flag()) o.name = r.pstring();
  if (r.flag()) o.velocity = readVec(r);
  if (r.flag()) o.shape = r.pstring();
  if (r.flag()) o.skin = r.pstring();
  if (r.flag()) {
    o.position = readVec(r);
    o.axis = readVec(r);
    o.angle = r.f32();
    o.hasTransform = true;
  }
  if (r.flag()) {
    o.movetype = r.pstring();
    o.hasMovement = isMovement(o.movetype);
  }
  // Section 7's flag is always on the wire; its data only while the object
  // has a movement object.
  if (r.flag() && o.hasMovement) {
    if (o.movetype == "list") {
      while (r.flag() && !r.overrun())
        for (int i = 0; i < 8; ++i) r.u32();
    } else {
      for (int i = 0; i < 3; ++i) r.u32();
      for (int i = 0; i < 4; ++i) r.bits(8);
      for (int i = 0; i < 6; ++i) r.bits(9);
      r.flag();
    }
  }
  if (r.flag()) {
    const uint32_t len = r.bits(14);  // the shape object's own data
    r.seek(r.pos() + len);
  }
  if (r.flag()) o.chat = r.pstring();
  if (r.flag()) o.scriptClasses = r.pstring();
  if (r.flag())
    for (auto& a : o.attr)
      if (r.flag()) a = r.pstring();
  if (r.flag()) {
    o.nickname = r.pstring();
    for (auto& c : o.nickColor) c = static_cast<uint8_t>(r.bits(8));
  }
  if (r.flag()) o.flags = static_cast<uint16_t>(r.bits(16));
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
  w.flag(false);  // no movement data from this client
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
