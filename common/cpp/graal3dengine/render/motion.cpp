#include "motion.hpp"

#include <algorithm>

namespace graal3d::render {

namespace {
V3 lerp(const V3& a, const V3& b, float t) { return a + (b - a) * t; }
}  // namespace

V3 MotionTracker::position(int ghost, const GameObjectState& o, double now) {
  const V3 section5{o.position.x, o.position.y, o.position.z};
  if (!o.hasMovement || !o.hasMovementData) {
    tracks_.erase(ghost);
    return section5;
  }
  const V3 target{o.movement.position.x, o.movement.position.y, o.movement.position.z};
  auto it = tracks_.find(ghost);
  if (it == tracks_.end()) {
    Track t;
    t.from = t.to = target;
    t.start = t.lastTarget = now;
    t.serial = o.movementSerial;
    tracks_[ghost] = t;
    return target;
  }
  Track& t = it->second;
  auto at = [&](double when) {
    if (t.duration <= 0 || when >= t.start + t.duration) return t.to;
    return lerp(t.from, t.to, float((when - t.start) / t.duration));
  };
  if (o.movementSerial != t.serial) {
    t.serial = o.movementSerial;
    if (o.movetype == "list") {
      t.from = t.to = target;
      t.duration = 0;
    } else {
      t.from = at(now);
      t.to = target;
      t.duration = std::clamp(now - t.lastTarget, kMinGlideSeconds, kMaxGlideSeconds);
    }
    t.start = t.lastTarget = now;
  }
  return at(now);
}

void MotionTracker::prune(const GhostTable& ghosts) {
  for (auto it = tracks_.begin(); it != tracks_.end();)
    it = ghosts.count(it->first) ? std::next(it) : tracks_.erase(it);
}

void applyMotion(Scene& scene, const GhostTable& ghosts, MotionTracker& motion, double now, int cameraGhost,
                 int controlGhost) {
  motion.prune(ghosts);
  std::map<int, V3> drawn;
  auto place = [&](int ghost, M4& transform) {
    auto g = ghosts.find(ghost);
    if (g == ghosts.end() || g->second.className != "GameObject") return;
    auto d = drawn.find(ghost);
    if (d == drawn.end()) d = drawn.emplace(ghost, motion.position(ghost, g->second.object, now)).first;
    transform.m[0][3] = d->second.x;
    transform.m[1][3] = d->second.y;
    transform.m[2][3] = d->second.z;
  };
  for (SceneObject& o : scene.objects)
    if (o.ghost >= 0) place(o.ghost, o.transform);
  for (SceneTag& t : scene.tags) place(t.ghost, t.transform);

  const auto cam = ghosts.find(cameraGhost);
  const auto ctl = ghosts.find(controlGhost);
  if (!scene.hasCamera || cam == ghosts.end() || cam->second.className != "Camera" || cam->second.camera.mode != 1 ||
      ctl == ghosts.end() || ctl->second.className != "GameObject")
    return;
  M4 at = M4::translation({});
  place(controlGhost, at);
  const V3 target{at.m[0][3], at.m[1][3], at.m[2][3]};
  M4& c = scene.view.cameraToWorld;
  const V3 eye{c.m[0][3], c.m[1][3], c.m[2][3]};
  const V3 d = target - eye;
  if (length(d) < 1e-4f) return;
  const V3 forward = normalize(d);
  V3 right = cross(forward, V3{0, 0, 1});
  right = length(right) < 1e-4f ? V3{1, 0, 0} : normalize(right);
  const V3 up = cross(right, forward);
  const V3 cols[3] = {right, forward, up};
  for (int j = 0; j < 3; ++j) {
    c.m[0][j] = cols[j].x;
    c.m[1][j] = cols[j].y;
    c.m[2][j] = cols[j].z;
  }
}

}  // namespace graal3d::render
