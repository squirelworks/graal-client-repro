// The engine's show-images (GuiShowImgCtrl) on the launcher's slots: the
// character a show-image plays its `ani` with, and its emitter's particles.
//
// The 4.04r2 main menu has four (StartAni1 a walking character with the
// script's `actor` head, body and attrs; StartAni2 the lamps; StartAni4 a
// smoke emitter; StartAni6 a monster). A gani is drawn by the Quattro
// program's actor pass (common/cpp/quattro/draw/world.cpp) into an image
// the size of the control, from the player's own files, and handed to the
// launcher with DrawGraphics. The launcher keeps a 2D matrix slot but does
// not apply it, so a particle is turned, scaled and tinted here and drawn
// as a plain picture: blended by its alpha whatever its mode (rebuild
// limit: the launcher has no additive or subtractive draw).
#pragma once

#include "graalengine.h"
#include "gui_draw.hpp"

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace Quattro::Draw {
class Assets;
class WorldRenderer;
}  // namespace Quattro::Draw

namespace graalengine {

class ShowImgPainter {
 public:
  explicit ShowImgPainter(const std::string& installDir);
  ~ShowImgPainter();

  // One 50 ms frame: ganis step on.
  void tick() { ++frame_; }
  int frame() const { return frame_; }

  // A GuiShowImgCtrl with an `ani`: its character, `offsetx`/`offsety` in.
  // False when it has none or the gani is not in the install.
  bool drawControl(const gs2::gui::Control& c, const gs2::gui::Rect& r);
  // One particle (Painter::sprite).
  void sprite(const std::string& file, double x, double y, double rotation, double sx, double sy,
              const double* rgba, int mode);

 private:
  struct Tex {
    std::vector<uint32_t> pixels;
    graal_texture tex{};
    std::string ani;
    int start = 0;
  };
  std::unique_ptr<Quattro::Draw::Assets> assets_;
  std::unique_ptr<Quattro::Draw::WorldRenderer> renderer_;
  std::map<const gs2::gui::Control*, Tex> controls_;
  Tex particle_;
  int frame_ = 0;
};

}  // namespace graalengine
