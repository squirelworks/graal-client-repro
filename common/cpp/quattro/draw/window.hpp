// The program's window. The original presents through OpenGL in a
// TWindow (Linux: X11 with Xcursor and XF86VidMode). The rebuild presents
// its software frame with plain Xlib on Linux, and has a headless window
// for tests and lab runs that only keeps the last frame.
#pragma once

#include "../../../torque/gui/image.hpp"

#include <deque>
#include <memory>
#include <string>

namespace Quattro::Draw {

enum class Key { NoKey, Left, Right, Up, Down, Escape, Close, A, S, D };

// Input for the GUI: keys by their Torque names ("a", "enter", "left"),
// with the typed character, and mouse presses in window pixels.
struct InputEvent {
  enum Type { KeyDown, KeyUp, MouseDown } type = KeyDown;
  std::string key;
  int ch = 0;
  std::string mods;  // "shift", "ctrl", "alt", space separated
  int x = 0, y = 0, clicks = 1;
};

class Window {
 public:
  virtual ~Window() = default;
  virtual void set_title(const std::string& title) = 0;
  virtual void present(const Torque::Gui::Image& frame) = 0;
  // Returns the next pending key, or Key::NoKey. Close is the window's close
  // button.
  virtual Key poll_key() = 0;
  virtual bool held(Key k) const = 0;
  virtual const std::string& title() const = 0;
  // The next GUI input event; false when there is none. Collected by the
  // same pump as poll_key, so call it after poll_key in a tick.
  virtual bool poll_input(InputEvent&) { return false; }
};

// A window that draws nothing and remembers the last frame.
class HeadlessWindow : public Window {
 public:
  void set_title(const std::string& t) override { title_ = t; }
  void present(const Torque::Gui::Image& frame) override { last_ = frame; ++frames_; }
  Key poll_key() override { return Key::NoKey; }
  bool held(Key) const override { return false; }
  const std::string& title() const override { return title_; }
  bool poll_input(InputEvent& e) override {
    if (input_.empty()) return false;
    e = input_.front();
    input_.pop_front();
    return true;
  }
  // Tests queue input here.
  void push_input(const InputEvent& e) { input_.push_back(e); }
  const Torque::Gui::Image& last() const { return last_; }
  int frames() const { return frames_; }

 private:
  std::string title_;
  std::deque<InputEvent> input_;
  Torque::Gui::Image last_;
  int frames_ = 0;
};

// An X11 window of `w` x `h`, or nullptr when there is no display (or the
// program was built without X11).
std::unique_ptr<Window> open_x11_window(int w, int h, const std::string& title);

}  // namespace Quattro::Draw
