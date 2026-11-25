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

void applyMotion(Scene& scene, const GhostTable& ghosts, MotionTracker& motion, double now) {
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
}

}  // namespace graal3d::render
