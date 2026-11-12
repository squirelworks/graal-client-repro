#pragma once

// Mouse clicks on the drawn control tree (rebuild policy until a 3.04
// capture of clicks exists; README.md, "Mouse"). The renderer's last layout
// says what is under the pointer.

#include <cstdint>
#include <string>
#include <vector>

#include "render.hpp"

namespace Torque {
class Engine;
}

namespace Torque::Gui {

// One left click at (x, y) in canvas pixels. A button runs its `command`
// and then its script onAction (a check box flips its value first); a text
// edit becomes the first responder; a text list selects the row (onSelect)
// and a double click runs its `altCommand`. Returns what took the click, as
// "Class Name" for the log, or "" when nothing did.
std::string mouse_click(Engine& engine, Renderer& renderer, int x, int y, bool double_click);

}  // namespace Torque::Gui
