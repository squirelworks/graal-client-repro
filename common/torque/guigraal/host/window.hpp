#pragma once

// A plain desktop window that shows a canvas image and reports keys and
// clicks in the console engine's terms. X11 on Linux; other systems are
// not done yet (README.md, "Not yet").

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

class Window {
 public:
  static std::unique_ptr<Window> open(const std::string& title, int width, int height, std::string& error);
  virtual ~Window() = default;
  // Everything that happened since the last call.
  virtual std::vector<WindowEvent> pump() = 0;
  virtual void present(const Gui::Image& image) = 0;
};

} // namespace Torque
