// The 3D view of the Graal3D world this client is ghosted.
//
// While the server names a Camera, the world is drawn by the 5.12 repro's
// renderer (common/cpp/graal3dengine/render): the sky, the shapes in
// levels3d/, the streamed terrain, water, name tags, with the lab's
// lighting and movement. Without a Camera the view is black, as the 5.12's
// is until the server names one.
#pragma once

#include <map>
#include <memory>
#include <string>
#include <vector>

#include "../../../common/torque/gui/image.hpp"
#include "../../../common/cpp/graal3dengine/render/motion.hpp"
#include "../../../common/cpp/graal3dengine/render/resources.hpp"
#include "../../../common/cpp/graal3dengine/render/terrain.hpp"
#include "link.hpp"
#include "renderer.hpp"
#include "world.hpp"

namespace Frank {

struct View3DStats {
  int objects = 0;  // GameObject and Camera ghosts drawn
  bool control = false;  // the control object was among them
  long triangles = 0;
};

// What the world renderer keeps between frames.
struct World3D {
  graal3d::render::Resources resources;
  graal3d::render::MotionTracker motion;
  graal3d::render::StreamedTerrain terrain;
  bool rooted = false;
  std::vector<std::string> roots;  // resource folders; "levels3d" when empty
  // The backend that draws (renderer.hpp); the software one when unset.
  std::unique_ptr<SceneRenderer> renderer;
};

// Draws `link`'s world over all of `frame` with the 5.12 renderer, the
// name tags in the tag colour. False when the server has named no Camera:
// the frame is black, as on the 5.12. `now` is in seconds.
bool draw_world3d(Torque::Gui::Image& frame, const graal3d::Link& link, World3D& world, double now,
                  View3DStats* stats = nullptr);
// The same from a ghost table: the camera and control ghosts, the field of
// view (0: 90) and the session's terrain chunks.
bool draw_world3d(Torque::Gui::Image& frame, const graal3d::GhostTable& ghosts, int camera, int control, int fov,
                  const std::map<int, std::string>& chunks, int chunkCount, World3D& world, double now,
                  View3DStats* stats = nullptr);

// The player's draw distance: `visibledistance3D` in a 5.12-style
// game_config.txt (key=value lines, the key in any case); 0 when absent.
float visible_distance_from_config(const std::string& text);
// Reads the first of `paths` that sets it and gives it to the renderer
// (1000 when none does, at most 2400, as the 5.12). Returns the value used.
float load_visible_distance(const std::vector<std::string>& paths);

// Draws `text` in the UI font with a one-pixel shadow, its top-left at
// (x, y), on its own patch of `frame`.
void draw_text(Torque::Gui::Image& frame, int x, int y, const std::string& text, Torque::Gui::Color color,
               bool bold);

// Copies `inset` into the bottom-left of `frame`, scaled down by `div`,
// with a one-pixel frame (the 6.x HUD and chat stay in view in 3D mode).
void draw_inset(Torque::Gui::Image& frame, const Torque::Gui::Image& inset, int div);

}  // namespace Frank
