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
  // An open pop-up list takes the click: a row picks that entry (the menu's
  // onSelect, then its command), anywhere else closes the list.
  if (r.open_popup) {
    SimObject* menu = e.object(r.open_popup);
    const Rect l = r.popup_list;
    r.open_popup = 0;
    if (!menu) return std::string();
    if (x >= l.x && y >= l.y && x < l.x + l.width && y < l.y + l.height) {
      const int row = (y - l.y - 1) / std::max(1, r.popup_row_height);
      if (row >= 0 && static_cast<std::size_t>(row) < menu->rows.size()) {
        const std::uint32_t id = menu->id;
        e.call_method(menu, "setSelected", {menu->rows[std::size_t(row)].second});
        if (SimObject* still = e.object(id)) {
          const std::string cmd = still->field("command");
          if (!cmd.empty()) e.evaluate(cmd);
        }
      }
    }
    return label(menu);
  }
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
    if (is_control_class(e, o, "GuiPopUpMenuCtrl")) {
      if (active(o) && !o->rows.empty()) r.open_popup = o->id;
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
