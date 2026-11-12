#include "mouse.hpp"

#include "../console/engine/engine.hpp"
#include "profile.hpp"

namespace Torque::Gui {
namespace {

bool active(const SimObject* o) {
  const std::string a = o->field("active");
  return a.empty() || parse_bool(a);
}

std::string label(const SimObject* o) {
  return o->class_name + " " + (o->name.empty() ? std::to_string(o->id) : o->name);
}

}  // namespace

std::string mouse_click(Engine& e, Renderer& r, int x, int y, bool double_click) {
  Rect box;
  std::uint32_t id = r.hit(x, y, &box);
  // The nearest control under the pointer, or a parent of it, that takes clicks.
  for (SimObject* o = id ? e.object(id) : nullptr; o; o = o->group && o->group != o->id ? e.object(o->group) : nullptr) {
    if (is_control_class(e, o, "GuiButtonCtrl") || is_control_class(e, o, "GuiCheckBoxCtrl") ||
        is_control_class(e, o, "GuiRadioCtrl")) {
      if (!active(o)) return label(o);
      if (!is_control_class(e, o, "GuiButtonCtrl"))
        o->set_field("value", parse_bool(o->field("value")) ? "0" : "1");
      const std::string cmd = o->field("command");
      if (!cmd.empty()) e.evaluate(cmd);
      if (e.object(o->id)) e.call_method(o, "onAction", {});
      return label(o);
    }
    if (is_control_class(e, o, "GuiTextEditCtrl") || is_control_class(e, o, "GuiConsoleEditCtrl")) {
      e.first_responder = o->id;
      return label(o);
    }
    if (is_control_class(e, o, "GuiTextListCtrl")) {
      for (const auto& placed : r.layout())
        if (placed.id == o->id) box = placed.rect;
      const int row = (y - box.y) / std::max(1, r.row_height(o));
      if (row >= 0 && static_cast<std::size_t>(row) < o->rows.size()) {
        e.call_method(o, "setSelectedRow", {std::to_string(row)});
        if (double_click) {
          const std::string cmd = o->field("altCommand");
          if (!cmd.empty()) e.evaluate(cmd);
        }
      }
      return label(o);
    }
    if (is_control_class(e, o, "GuiGraalCtrl")) {
      e.first_responder = 0;   // keys go to the pushed maps (moveMap)
      return label(o);
    }
  }
  return std::string();
}

}  // namespace Torque::Gui
