// The program's window. The original presents through OpenGL in a
// TWindow (Linux: X11 with Xcursor and XF86VidMode). The rebuild presents
// its software frame with plain Xlib on Linux, GDI on Windows and AppKit on
// macOS, and has a headless window for tests and lab runs that only keeps
// the last frame.
#pragma once

#include "../../../torque/gui/image.hpp"

#include <deque>
#include <memory>
#include <string>

namespace Quattro::Draw {

enum class Key { NoKey, Left, Right, Up, Down, Escape, Close, A, S, D, Q, Tab };

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

// A Cocoa window on macOS (draw/window_cocoa.mm), or nullptr. Built only
// with QUATTRO_COCOA. The other two are for the window test.
std::unique_ptr<Window> open_cocoa_window(int w, int h, const std::string& title);
bool cocoa_shown_pixel(Window& w, int x, int y, unsigned char rgb[3]);
long cocoa_window_number(Window& w);
// Window test only: post a key (macOS virtual key code, its characters) to
// the window's queue, close it, or take its focus away.
void cocoa_post_key(Window& w, unsigned short code, const std::string& chars, bool down, bool repeat = false);
void cocoa_post_close(Window& w);
void cocoa_post_resign(Window& w);

// The platform window: Win32 on Windows, Cocoa on macOS, X11 where
// available on other Unix systems. Returns nullptr if the native window
// cannot be created.
std::unique_ptr<Window> open_window(int w, int h, const std::string& title);

}  // namespace Quattro::Draw
