// The console classes the shipped 3.04 scripts create with `new`
// (Graal_analysis torque/study-torque-clients.md section 5; all 31 are
// registered in the 3.04 engine, section 5.1), plus GuiCanvas, which the
// engine creates for createCanvas().
//
// Parents: every GUI control is a GuiControl and every GuiControl is a
// SimGroup (its children are its members). Intermediate stock classes
// between a control and GuiControl are not read for 3.04, so each control
// links straight to GuiControl (rebuild policy). Only the data model is
// here; drawing, awake order and input are later stages.

#include <algorithm>
#include <cstdlib>

#include "engine.hpp"

namespace Torque {
namespace {

bool is_control(const Engine& e, const SimObject* o) { return is_control_class(e, o, "guicontrol"); }

// A script boolean: "true" or a nonzero number.
bool truthy(const std::string& s) { return lower(s) == "true" || std::atof(s.c_str()) != 0; }

} // namespace

bool is_control_class(const Engine& e, const SimObject* o, const char* class_name) {
  const std::string want = lower(class_name);
  for (const ClassInfo* c = o ? o->info : nullptr; c; c = e.find_class(c->parent))
    if (lower(c->name) == want) return true;
  return false;
}

// Wake a control tree: the control's script onWake, then its children
// (order is rebuild policy). Sleep is the reverse.
void wake_control(Engine& e, std::uint32_t id) {
  SimObject* o = e.object(id);
  if (!is_control(e, o) || o->awake) return;
  o->awake = true;
  e.call_method(o, "onWake", {});
  const auto members = o->members;
  for (auto m : members) wake_control(e, m);
}

void sleep_control(Engine& e, std::uint32_t id) {
  SimObject* o = e.object(id);
  if (!is_control(e, o) || !o->awake) return;
  const auto members = o->members;
  for (auto m : members) sleep_control(e, m);
  o->awake = false;
  e.call_method(o, "onSleep", {});
}

static bool edit_buffer(const Engine& e, const SimObject* o) {
  return is_control_class(e, o, "GuiTextEditCtrl") || is_control_class(e, o, "GuiConsoleEditCtrl");
}

void register_classes_304(Engine& e) {
  e.add_class({"GuiControl", "SimGroup", true, true, true});
  e.add_class({"GuiCanvas", "GuiControl", true, true, true});
  for (const char* control : {
           "GuiTextCtrl", "GuiButtonCtrl", "GuiTextEditCtrl", "GuiScrollCtrl", "GuiWindowCtrl",
           "GuiCheckBoxCtrl", "GuiPopUpMenuCtrl", "GuiTextListCtrl", "GuiMLTextCtrl", "GuiSliderCtrl",
           "GuiChunkedBitmapCtrl", "GuiTreeViewCtrl", "GuiInspector", "GuiControlListPopUp",
           "GuiMLTextEditCtrl", "GuiBitmapBorderCtrl", "GuiBitmapCtrl", "GuiRadioCtrl", "GuiConsole",
           "GuiConsoleEditCtrl", "GuiConsoleTextCtrl", "GuiEditCtrl", "GuiFrameSetCtrl",
           "GuiProgressCtrl", "GuiInputCtrl", "GuiGraalCtrl"})
    e.add_class({control, "GuiControl", true, true, true});
  e.add_class({"GuiControlProfile", "SimObject", true, false, false});
  e.add_class({"GuiCursor", "SimObject", true, false, false});

  // The canvas holds one content control. Waking it (onWake) and drawing
  // are the GUI stage; this stores it and tells the host.
  e.add_function("GuiCanvas", "setContent", 3, 3, "canvas.setContent(ctrl)", [](Engine& en, SimObject* canvas, Args& a) {
    if (!canvas) return std::string();
    SimObject* content = en.find_object(a[2]);
    const std::string old = canvas->field("content");
    if (!old.empty() && (!content || std::to_string(content->id) != old))
      sleep_control(en, static_cast<std::uint32_t>(std::stoul(old)));
    canvas->set_field("content", content ? std::to_string(content->id) : std::string());
    if (content) wake_control(en, content->id);
    content = en.find_object(a[2]);
    if (content && en.on_set_content) en.on_set_content(canvas, content);
    return std::string();
  });
  e.add_function("GuiCanvas", "getContent", 2, 2, "canvas.getContent()", [](Engine&, SimObject* canvas, Args&) {
    const std::string id = canvas ? canvas->field("content") : std::string();
    return id.empty() ? std::string("-1") : id;
  });
  e.add_function("GuiControl", "isAwake", 2, 2, "ctrl.isAwake()", [](Engine&, SimObject* o, Args&) {
    return std::string(o && o->awake ? "1" : "0");
  });

  // Visibility, the active state and geometry live in the control's fields
  // ("visible", "active", "position", "extent"), which the renderer and the
  // mouse read. Stock Torque 1.x names (rebuild policy for what the 3.04
  // scripts ask: the Options tabs, messageBox.cs's sizing).
  e.add_function("GuiControl", "setVisible", 3, 3, "ctrl.setVisible(bool)", [](Engine&, SimObject* o, Args& a) {
    if (o) o->set_field("visible", truthy(a[2]) ? "1" : "0");
    return std::string();
  });
  e.add_function("GuiControl", "isVisible", 2, 2, "ctrl.isVisible()", [](Engine&, SimObject* o, Args&) {
    return std::string(o && o->field("visible") != "0" ? "1" : "0");
  });
  e.add_function("GuiControl", "setActive", 3, 3, "ctrl.setActive(bool)", [](Engine&, SimObject* o, Args& a) {
    if (o) o->set_field("active", truthy(a[2]) ? "1" : "0");
    return std::string();
  });
  e.add_function("GuiControl", "isActive", 2, 2, "ctrl.isActive()", [](Engine&, SimObject* o, Args&) {
    return std::string(o && o->field("active") != "0" ? "1" : "0");
  });
  e.add_function("GuiControl", "getPosition", 2, 2, "ctrl.getPosition()", [](Engine&, SimObject* o, Args&) {
    const std::string v = o ? o->field("position") : std::string();
    return v.empty() ? std::string("0 0") : v;
  });
  e.add_function("GuiControl", "getExtent", 2, 2, "ctrl.getExtent()", [](Engine&, SimObject* o, Args&) {
    const std::string v = o ? o->field("extent") : std::string();
    return v.empty() ? std::string("64 64") : v;
  });
  e.add_function("GuiControl", "resize", 6, 6, "ctrl.resize(x, y, w, h)", [](Engine&, SimObject* o, Args& a) {
    if (!o) return std::string();
    auto num = [](const std::string& t) { return std::to_string(std::atoi(t.c_str())); };
    o->set_field("position", num(a[2]) + " " + num(a[3]));
    o->set_field("extent", num(a[4]) + " " + num(a[5]));
    return std::string();
  });
  // A button pressed from script: what a click does (gui/mouse.cpp), the
  // control's command and its onAction, unless it is inactive.
  for (const char* button : {"GuiButtonCtrl", "GuiCheckBoxCtrl", "GuiRadioCtrl"})
    e.add_function(button, "performClick", 2, 2, "button.performClick()", [](Engine& en, SimObject* o, Args&) {
      if (!o || o->field("active") == "0") return std::string();
      if (!is_control_class(en, o, "GuiButtonCtrl"))
        o->set_field("value", truthy(o->field("value")) ? "0" : "1");
      const std::uint32_t id = o->id;
      const std::string cmd = o->field("command");
      if (!cmd.empty()) en.evaluate(cmd);
      if (SimObject* still = en.object(id)) en.call_method(still, "onAction", {});
      return std::string();
    });

  // Display settings for the Options dialog. The window is a fixed-size
  // canvas, so there is one device and the sizes the 3.04 lists offer;
  // choosing one is stored in the prefs and does not resize the window
  // (rebuild policy).
  e.add_function("", "getDisplayDeviceList", 1, 1, "getDisplayDeviceList()", [](Engine&, SimObject*, Args&) {
    return std::string("OpenGL");
  });
  e.add_function("", "getResolutionList", 2, 3, "getResolutionList(device)", [](Engine&, SimObject*, Args&) {
    return std::string("640 480 32\t800 600 32\t1024 768 32");
  });
  e.add_function("", "getDesktopResolution", 1, 1, "getDesktopResolution()", [](Engine&, SimObject*, Args&) {
    return std::string("1024 768 32");
  });

  // Text and value live in the control's fields, where the .gui put them.
  // A text edit has one buffer: setText, setValue, getText and getValue all
  // use it, and typing (input304.cpp) edits it. mainMenuGui::onWake fills
  // NickEdit with setText and switchToServerList reads it with getValue.
  // Kept in the "value" field (rebuild policy).
  e.add_function("GuiControl", "setText", 3, 3, "ctrl.setText(text)", [](Engine& en, SimObject* o, Args& a) {
    if (o) o->set_field(edit_buffer(en, o) ? "value" : "text", a[2]);
    return std::string();
  });
  e.add_function("GuiControl", "getText", 2, 2, "ctrl.getText()", [](Engine& en, SimObject* o, Args&) {
    return o ? o->field(edit_buffer(en, o) ? "value" : "text") : std::string();
  });
  e.add_function("GuiControl", "setValue", 3, 3, "ctrl.setValue(value)", [](Engine&, SimObject* o, Args& a) {
    if (o) o->set_field("value", a[2]);
    return std::string();
  });
  e.add_function("GuiControl", "getValue", 2, 2, "ctrl.getValue()", [](Engine&, SimObject* o, Args&) {
    return o ? o->field("value") : std::string();
  });

  // Pop-up menu entries. setSelected calls the script's onSelect(id, text):
  // the stage 0 open order shows the language file exec'd a second time from
  // LanguageBox::onSelect after mainMenuGui::onWake selects English.
  const char* popup = "GuiPopUpMenuCtrl";
  e.add_function(popup, "add", 4, 4, "menu.add(text, id)", [](Engine&, SimObject* o, Args& a) {
    if (o) o->rows.push_back({a[2], a[3]});
    return std::string();
  });
  e.add_function(popup, "clear", 2, 2, "menu.clear()", [](Engine&, SimObject* o, Args&) {
    if (o) { o->rows.clear(); o->set_field("text", ""); }
    return std::string();
  });
  e.add_function(popup, "size", 2, 2, "menu.size()", [](Engine&, SimObject* o, Args&) {
    return std::to_string(o ? o->rows.size() : 0);
  });
  e.add_function(popup, "sort", 2, 2, "menu.sort()", [](Engine&, SimObject* o, Args&) {
    if (o) std::stable_sort(o->rows.begin(), o->rows.end(), [](const auto& x, const auto& y) {
      return lower(x.first) < lower(y.first);
    });
    return std::string();
  });
  e.add_function(popup, "findText", 3, 3, "menu.findText(text)", [](Engine&, SimObject* o, Args& a) {
    if (o) for (const auto& r : o->rows) if (lower(r.first) == lower(a[2])) return r.second;
    return std::string("-1");
  });
  e.add_function(popup, "getSelected", 2, 2, "menu.getSelected()", [](Engine&, SimObject* o, Args&) {
    const std::string v = o ? o->field("selected") : std::string();
    return v.empty() ? std::string("-1") : v;
  });
  e.add_function(popup, "setSelected", 3, 3, "menu.setSelected(id)", [](Engine& en, SimObject* o, Args& a) {
    if (!o) return std::string();
    for (const auto& r : o->rows) {
      if (r.second != a[2]) continue;
      const std::string text = r.first, id = r.second;
      o->set_field("selected", id);
      o->set_field("text", text);
      en.call_method(o, "onSelect", {id, text});
      break;
    }
    return std::string();
  });
}

} // namespace Torque
