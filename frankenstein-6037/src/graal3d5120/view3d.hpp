// A plain 3D view of the Graal3D world this client is ghosted.
//
// The 5.12 repro reads the world (ghosts, the control object, sun and sky)
// but draws none of it yet: the Torque renderer (terrain, interiors, DTS
// shapes) is still to come (common/cpp/graal3dengine, "Not yet"). Until it
// is, the Frankenstein draws its own stand-in: the sky's fog colour, a
// ground grid at z = 0 and each GameObject as a box, seen from behind the
// control object. Nothing here is the original's look.
#pragma once

#include "../../../common/torque/gui/image.hpp"
#include "world.hpp"

namespace Frank {

struct View3DStats {
  int objects = 0;  // GameObject and Camera ghosts drawn
  bool control = false;  // the control object was among them
};

// Draws the view over all of `frame`. `control` is the control object's
// ghost index (-1: none); `control_at` is where its movement has taken it.
View3DStats draw_view3d(Torque::Gui::Image& frame, const graal3d::GhostTable& ghosts, int control,
                        const graal3d::Vec3& control_at);

// Copies `inset` into the bottom-left of `frame`, scaled down by `div`,
// with a one-pixel frame (the 6.x HUD and chat stay in view in 3D mode).
void draw_inset(Torque::Gui::Image& frame, const Torque::Gui::Image& inset, int div);

}  // namespace Frank
