#pragma once

// A plain desktop window that shows a canvas image and reports keys and
// clicks in the console engine's terms. X11 on Linux (window_x11.cpp),
// Win32 on Windows (window_win32.cpp), Cocoa on macOS (window_cocoa.mm).

#include <memory>
#include <string>
#include <vector>

#include "../../console/engine/engine.hpp"
#include "../../gui/image.hpp"

namespace Torque {

struct WindowEvent {
  enum class Kind { key, click, close } kind = Kind::key;
  InputEvent key;                 // Kind::key, Torque key names
  int x = 0, y = 0;               // Kind::click, window pixels
  bool double_click = false;
};

// The Torque name of an unshifted punctuation key ("comma" for ','), empty
// for anything else. Each window maps letters, digits and named keys itself.
inline std::string punctuation_key_name(char c) {
  switch (c) {
    case ',': return "comma";
    case '.': return "period";
    case '/': return "slash";
    case '\\': return "backslash";
    case ';': return "semicolon";
    case '\'': return "apostrophe";
    case '[': return "lbracket";
    case ']': return "rbracket";
    case '-': return "minus";
    case '=': return "equals";
    case '`': return "tilde";
    default: return std::string();
  }
}

// Tell the player why the program cannot start: a message box on Windows
// and macOS, nothing more on X11 (the console line is enough there).
void show_error(const std::string& title, const std::string& text);

class Window {
 public:
  static std::unique_ptr<Window> open(const std::string& title, int width, int height, std::string& error);
  virtual ~Window() = default;
  // Everything that happened since the last call.
  virtual std::vector<WindowEvent> pump() = 0;
  virtual void present(const Gui::Image& image) = 0;
};

} // namespace Torque
