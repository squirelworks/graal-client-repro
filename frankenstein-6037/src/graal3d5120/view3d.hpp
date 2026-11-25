// The 3D view of the Graal3D world this client is ghosted.
//
// While the server names a Camera, the world is drawn by the 5.12 repro's
// renderer (common/cpp/graal3dengine/render): the sky, the shapes in
// levels3d/, the streamed terrain, water, name tags, with the lab's
// lighting and movement. Without a Camera, the Frankenstein draws its own
// stand-in: the sky's fog colour, a ground grid at z = 0 and each
// GameObject as a box, seen from behind the control object.
#pragma once

#include <map>
#include <string>
#include <vector>

#include "../../../common/torque/gui/image.hpp"
#include "../../../common/cpp/graal3dengine/render/motion.hpp"
#include "../../../common/cpp/graal3dengine/render/resources.hpp"
#include "../../../common/cpp/graal3dengine/render/terrain.hpp"
#include "link.hpp"
#include "world.hpp"

namespace Frank {

struct View3DStats {
  int objects = 0;  // GameObject and Camera ghosts drawn
  bool control = false;  // the control object was among them
};

// What the world renderer keeps between frames.
struct World3D {
  graal3d::render::Resources resources;
  graal3d::render::MotionTracker motion;
  graal3d::render::StreamedTerrain terrain;
  bool rooted = false;
  std::vector<std::string> roots;  // resource folders; "levels3d" when empty
};

// Draws `link`'s world over all of `frame` with the 5.12 renderer, the
// name tags in the tag colour. False (nothing drawn) when the server has
// named no Camera. `now` is in seconds.
bool draw_world3d(Torque::Gui::Image& frame, const graal3d::Link& link, World3D& world, double now,
                  View3DStats* stats = nullptr);
// The same from a ghost table: the camera and control ghosts, the field of
// view (0: 90) and the session's terrain chunks.
bool draw_world3d(Torque::Gui::Image& frame, const graal3d::GhostTable& ghosts, int camera, int control, int fov,
                  const std::map<int, std::string>& chunks, int chunkCount, World3D& world, double now,
                  View3DStats* stats = nullptr);

// Draws the stand-in view over all of `frame`. `control` is the control object's
// ghost index (-1: none); `control_at` is where its movement has taken it.
View3DStats draw_view3d(Torque::Gui::Image& frame, const graal3d::GhostTable& ghosts, int control,
                        const graal3d::Vec3& control_at);

// Copies `inset` into the bottom-left of `frame`, scaled down by `div`,
// with a one-pixel frame (the 6.x HUD and chat stay in view in 3D mode).
void draw_inset(Torque::Gui::Image& frame, const Torque::Gui::Image& inset, int div);

}  // namespace Frank
