// Where a moving GameObject is drawn between server updates.
//
// The lab (Graal_analysis protocol/lab-appe-hosta-2026-11-20d.md, E#505,
// real 5.12): with movetype `list` the client jumps onto each new target;
// with `interpolate` or `rigid` it glides toward each one, running about a
// quarter to a half unit behind a target that steps 0.5 units a second.
// The rebuild glides linearly from where the object is drawn to the new
// target over the time since the previous target (kept between
// kMinGlideSeconds and kMaxGlideSeconds): its own curve, which gives that
// lag at that rate. An object with no movement data is drawn at its
// section 5 position.
#pragma once

#include <map>

#include "scene.hpp"

namespace graal3d::render {

constexpr double kMinGlideSeconds = 0.05;
constexpr double kMaxGlideSeconds = 1.0;

class MotionTracker {
 public:
  // The position to draw `o` (ghost `ghost`) at, at `now` seconds.
  V3 position(int ghost, const GameObjectState& o, double now);
  // Forgets ghosts no longer in `ghosts`.
  void prune(const GhostTable& ghosts);
  size_t size() const { return tracks_.size(); }

 private:
  struct Track {
    V3 from, to;
    double start = 0, duration = 0, lastTarget = 0;
    uint32_t serial = 0;
  };
  std::map<int, Track> tracks_;
};

// Moves each of the scene's objects and tags that has movement data to
// where `motion` draws it. Then, when the camera ghost's mode is 1, turns
// the view to look at the control object (lab T3D-023, real 5.12: mode 1
// looks at the player's own object; mode 0 and the follow index change
// nothing). The point looked at, the object's origin, and the level
// horizon are the rebuild's own.
void applyMotion(Scene& scene, const GhostTable& ghosts, MotionTracker& motion, double now, int cameraGhost = -1,
                 int controlGhost = -1);

}  // namespace graal3d::render
