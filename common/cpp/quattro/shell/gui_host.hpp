// The GS2 GUI on the Quattro window: the control tree of common/cpp/gs2
// (gui.hpp, B4) drawn on the software canvas, fed with the window's keys
// and mouse, and the StartScript_* shell scripts read from the player's
// own program file.
//
// The original draws its GUI in RenderGUI after the world passes, through
// OpenGL; GuiGraalCtrl is where the world shows. Here the world is drawn
// into a GuiGraalCtrl's rectangle when the content has one, and over the
// whole window when no GUI content is up yet.
#pragma once

#include "../../../torque/gui/canvas.hpp"
#include "../../gs2/gui.hpp"
#include "../../gs2/gui_draw.hpp"
#include "../draw/window.hpp"

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace Quattro::Shell {

// gs2::gui::Painter on a Torque::Gui::Canvas. Bitmaps are looked up by the
// name the script gives in each of `dirs` (and with ".png" added when the
// name has no extension); text uses the built-in UI font (a stand-in for
// the player's TrueType faces).
class CanvasPainter : public gs2::gui::Painter {
 public:
  CanvasPainter(Torque::Gui::Canvas& canvas, std::vector<std::string> dirs);
  ~CanvasPainter() override;

  void setClip(const gs2::gui::Rect& r) override;
  void fill(const gs2::gui::Rect& r, gs2::gui::Color c) override;
  void text(int x, int y, const std::string& s, const std::string& font, int size, gs2::gui::Color c) override;
  int textWidth(const std::string& s, const std::string& font, int size) override;
  int fontHeight(const std::string& font, int size) override;
  bool bitmapSize(const std::string& file, int& w, int& h) override;
  std::vector<gs2::gui::Rect> cells(const std::string& file) override;
  void bitmap(const std::string& file, const gs2::gui::Rect& src, const gs2::gui::Rect& dst) override;
  void engineControl(const gs2::gui::Control& c, const gs2::gui::Rect& r) override;

  // Called for GuiShowImgCtrl, GuiGraalCtrl and GuiGraal3DCtrl.
  std::function<void(const gs2::gui::Control&, const gs2::gui::Rect&)> on_engine_control;
  // Ends the clip set by the last setClip.
  void reset_clip();

 private:
  struct Entry {
    bool ok = false;
    Torque::Gui::Image image;
    bool split = false;
    std::vector<gs2::gui::Rect> cells;
  };
  Entry& load(const std::string& file);

  Torque::Gui::Canvas& canvas_;
  std::vector<std::string> dirs_;
  std::map<std::string, Entry> cache_;
  bool clipped_ = false;
};

// Is this a control the engine draws itself?
bool is_engine_control(const gs2::gui::Control& c);

class GuiHost {
 public:
  explicit GuiHost(gs2::Machine& m);

  gs2::gui::Screen& screen() { return screen_; }

  // Finds the StartScript_* streams in the player's program file and gives
  // each to a universe variable of its name (queuing `created`). Returns
  // how many were attached.
  int load_start_scripts(const std::string& program_path, std::string& error);

  // Makes MainMenuGui2D the content once a script has made it.
  void pick_content();
  bool has_content() const { return screen_.content() != nullptr; }
  // The first GuiGraalCtrl under the content, or null.
  gs2::gui::ControlPtr playfield() const;

  // Window input. Returns true when the GUI took it.
  bool input(const Draw::InputEvent& e);

 private:
  gs2::gui::Screen screen_;
};

}  // namespace Quattro::Shell
