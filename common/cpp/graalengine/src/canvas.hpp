// GuiCanvas and the control base for the 4.x/5.0 engine library.
//
// torque/4208-engine.md, "How the canvas hosts the playfield":
// renderFrame sets the clip to the screen size, fits the main controls,
// checks the hint, forces the cursor on when the application is not
// active, runs the adventure timer, pre-renders, and then (unless asked to
// skip drawing) walks the child list and renders each visible child.
// setContentControl is how a script object becomes the screen.
//
// The control here is deliberately small: a name, a rectangle, a visible
// flag, children and virtual render/input hooks. The GS2 control classes
// (Track B4, common/cpp/gs2) derive from it or wrap it; nothing in this
// library knows about scripts.
#pragma once

#include "graalengine.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace graalengine {

struct InputEvent {
  enum Kind { KeyDown, KeyUp, MouseMove, MouseDown, MouseUp, MouseWheel } kind = KeyDown;
  int vk = 0;       // key events
  int ch = 0;       // key events: the character, 0 for none
  int mods = 0;     // GRAAL_MOD_*
  int x = 0, y = 0; // mouse events, screen pixels
  int button = 0;   // GRAAL_MOUSE_LEFT/MIDDLE/RIGHT
  int clicks = 0;
  int wheel = 0;
};

class Control {
 public:
  explicit Control(std::string name = {}) : name_(std::move(name)) {}
  virtual ~Control() = default;

  const std::string& name() const { return name_; }
  graal_rect& rect() { return rect_; }
  const graal_rect& rect() const { return rect_; }
  bool visible() const { return visible_; }
  void setVisible(bool v) { visible_ = v; }

  void add(std::shared_ptr<Control> child);
  bool remove(const Control* child);
  const std::vector<std::shared_ptr<Control>>& children() const { return children_; }

  // Called by the canvas when this control is made the content: the
  // control takes the whole screen (Torque's content controls are sized
  // to the canvas).
  virtual void resize(int w, int h);

  // Draws this control and then its visible children, each clipped to
  // its own rectangle intersected with the parent's clip.
  void renderTree(const graal_rect& clip);

  // Offers the event to the deepest visible child under the point (mouse)
  // or to this control's children in front-to-back order (keys). Returns
  // true when a control took it.
  bool dispatch(const InputEvent& ev);

 protected:
  virtual void onRender(const graal_rect& /*clip*/) {}
  virtual bool onInput(const InputEvent& /*ev*/) { return false; }

 private:
  std::string name_;
  graal_rect rect_{0, 0, 0, 0};
  bool visible_ = true;
  std::vector<std::shared_ptr<Control>> children_;
};

class Canvas {
 public:
  // The screen size comes from the GetScreenWidth/GetScreenHeight slots
  // each frame; 640 x 480 when the launcher left them empty (the launcher
  // note's default for an empty window rectangle).
  int screenWidth() const;
  int screenHeight() const;

  void setContentControl(std::shared_ptr<Control> content);
  const std::shared_ptr<Control>& content() const { return content_; }

  // Dialogs pushed over the content, drawn after it (Torque's canvas
  // children past the first).
  void pushDialog(std::shared_ptr<Control> dialog);
  bool popDialog(const Control* dialog);

  // Runs once per renderFrame, before drawing: TAdventure::timer's place.
  void setTimer(std::function<void()> timer) { timer_ = std::move(timer); }

  void renderFrame(bool draw);
  void processInputEvent(const InputEvent& ev);

  unsigned frames() const { return frames_; }

 private:
  std::shared_ptr<Control> content_;
  std::vector<std::shared_ptr<Control>> dialogs_;
  std::function<void()> timer_;
  unsigned frames_ = 0;
};

}  // namespace graalengine
