// Stage 3 of the 3.04 rebuild: keys through ActionMap, canvas dialogs and
// focus, the F2 console (GuiConsole, GuiConsoleEditCtrl) and the remap
// dialog's GuiInputCtrl.
//
// Written from what the shipped 3.04 scripts expect (default.bind.cs,
// ConsoleDlg.gui, optionsDlg.cs, remapDlg.gui, messageBox.cs, cursor.cs) and
// from rebuild policy. README.md lists which is which and what the lab
// compared against the original client.

#include <algorithm>
#include <sstream>

#include "engine.hpp"

namespace Torque {
namespace {

std::vector<std::string> words(const std::string& s) {
  std::vector<std::string> out;
  std::istringstream in(s);
  for (std::string w; in >> w;) out.push_back(w);
  return out;
}

// Modifier words in a bound action string ("alt enter", "shift a").
// Left and right variants count as the plain modifier (policy).
unsigned modifier_bit(const std::string& w) {
  if (w == "shift" || w == "lshift" || w == "rshift") return InputEvent::shift;
  if (w == "ctrl" || w == "lctrl" || w == "rctrl" || w == "control") return InputEvent::ctrl;
  if (w == "alt" || w == "lalt" || w == "ralt") return InputEvent::alt;
  return 0;
}

// A key that is itself a modifier (pressing shift alone).
bool is_modifier_key(const std::string& key) { return modifier_bit(key) != 0; }

// Torque's key name for Enter is "return" (lab, 3.04).
std::string key_name(const std::string& key) {
  const std::string k = lower(key);
  return k == "enter" ? std::string("return") : k;
}

struct Action { unsigned modifiers = 0; std::string key; };

Action parse_action(const std::string& action) {
  Action a;
  auto w = words(lower(action));
  if (w.empty()) return a;
  a.key = key_name(w.back());
  for (std::size_t i = 0; i + 1 < w.size(); ++i) a.modifiers |= modifier_bit(w[i]);
  return a;
}

std::string device_class(const std::string& d) {
  std::string l = lower(d);
  while (!l.empty() && l.back() >= '0' && l.back() <= '9') l.pop_back();
  return l;
}

// The action string GuiInputCtrl reports: modifiers, then the key.
std::string action_string(const InputEvent& ev) {
  std::string s;
  if (ev.modifiers & InputEvent::shift) s += "shift ";
  if (ev.modifiers & InputEvent::ctrl) s += "ctrl ";
  if (ev.modifiers & InputEvent::alt) s += "alt ";
  return s + key_name(ev.key);
}

std::string event_name(const InputEvent& ev) {
  return ev.device + " " + action_string(ev) + (ev.make ? (ev.repeat ? " repeat" : " make") : " break");
}

std::string ref(const SimObject* o) {
  return o->name.empty() ? std::to_string(o->id) : o->name;
}

bool is_text_edit(const Engine& e, const SimObject* o) {
  return is_control_class(e, o, "GuiTextEditCtrl") || is_control_class(e, o, "GuiConsoleEditCtrl");
}

bool focusable(const Engine& e, const SimObject* o) {
  return o && o->awake && o->field("visible") != "0" &&
         (is_control_class(e, o, "GuiInputCtrl") || is_text_edit(e, o));
}

// First focusable control in a tree, depth first, in member order (policy).
std::uint32_t first_focusable(const Engine& e, std::uint32_t id) {
  const SimObject* o = e.object(id);
  if (!o) return 0;
  if (focusable(e, o)) return id;
  for (auto m : o->members)
    if (auto f = first_focusable(e, m)) return f;
  return 0;
}

bool contains(const Engine& e, std::uint32_t root, std::uint32_t id) {
  for (std::size_t depth = 0; id && depth < 4096; ++depth) {
    if (id == root) return true;
    const SimObject* o = e.object(id);
    if (!o) return false;
    id = o->group;
  }
  return false;
}

void log(Engine& e, const std::string& line) {
  e.input_log.push_back(line);
  e.trace.push_back("input " + line);
}

// ------------------------------------------------------------ ActionMap

const ActionBinding* find_binding(const SimObject* map, const InputEvent& ev) {
  const std::string device = device_class(ev.device), key = key_name(ev.key);
  for (const auto& b : map->binds) {
    if (b.device != device) continue;
    const Action a = parse_action(b.action);
    if (a.key == key && a.modifiers == ev.modifiers) return &b;
  }
  return nullptr;
}

void fire(Engine& e, const std::string& map, const ActionBinding& b, bool make, const std::string& what) {
  if (b.is_cmd) {
    const std::string& cmd = make ? b.make : b.brk;
    log(e, what + ": " + map + " bindCmd " + (make ? "make" : "break") + " \"" + cmd + "\"");
    if (!cmd.empty()) e.evaluate(cmd);
    return;
  }
  log(e, what + ": " + map + " bind " + b.command + "(" + (make ? "1" : "0") + ")");
  if (!b.command.empty()) e.call_function(b.command, {make ? "1" : "0"});
}

bool try_map(Engine& e, SimObject* map, const InputEvent& ev) {
  if (!map) return false;
  const ActionBinding* b = find_binding(map, ev);
  if (!b) return false;
  const ActionBinding bind = *b;  // the script may rebind while it runs
  const std::string name = ref(map);
  e.pending_breaks.push_back({device_class(ev.device), key_name(ev.key), name, bind});
  fire(e, name, bind, true, event_name(ev));
  return true;
}

// ------------------------------------------------------------ text edits

void set_text(SimObject* o, TextEditState& st, const std::string& text) {
  o->set_field("value", text);
  st.cursor = text.size();
}

bool edit_key(Engine& e, SimObject* o, const InputEvent& ev) {
  if (ev.modifiers & (InputEvent::ctrl | InputEvent::alt)) return false;
  TextEditState& st = e.edits[o->id];
  std::string text = o->field("value");
  st.cursor = std::min(st.cursor, text.size());
  const std::string key = key_name(ev.key);
  const bool console = is_control_class(e, o, "GuiConsoleEditCtrl");

  if (static_cast<unsigned char>(ev.ascii) >= 32 && ev.ascii != 127) {
    const auto max = static_cast<std::int32_t>(parse_int(o->field("maxLength")));
    if (max > 0 && text.size() >= static_cast<std::size_t>(max)) return true;
    text.insert(st.cursor, 1, ev.ascii);
    ++st.cursor;
    o->set_field("value", text);
    return true;
  }
  if (key == "backspace") {
    if (st.cursor > 0) { text.erase(st.cursor - 1, 1); --st.cursor; o->set_field("value", text); }
    return true;
  }
  if (key == "delete") {
    if (st.cursor < text.size()) { text.erase(st.cursor, 1); o->set_field("value", text); }
    return true;
  }
  if (key == "left") { if (st.cursor > 0) --st.cursor; return true; }
  if (key == "right") { if (st.cursor < text.size()) ++st.cursor; return true; }
  if (key == "home") { st.cursor = 0; return true; }
  if (key == "end") { st.cursor = text.size(); return true; }
  if (console && (key == "up" || key == "down")) {
    if (key == "up" && st.history_pos > 0) set_text(o, st, st.history[--st.history_pos]);
    else if (key == "down" && st.history_pos < st.history.size())
      set_text(o, st, ++st.history_pos == st.history.size() ? std::string() : st.history[st.history_pos]);
    return true;
  }
  if (key == "return" || key == "numpadenter") {
    if (ev.repeat) return true;
    if (console) {
      const auto size = static_cast<std::int32_t>(parse_int(o->field("historySize")));
      if (!text.empty() && size > 0 && (st.history.empty() || st.history.back() != text)) {
        st.history.push_back(text);
        while (st.history.size() > static_cast<std::size_t>(size)) st.history.erase(st.history.begin());
      }
      st.history_pos = st.history.size();
    }
    const std::string cmd = o->field("altCommand");
    log(e, event_name(ev) + ": " + ref(o) + " altCommand \"" + cmd + "\"");
    if (!cmd.empty()) e.evaluate(cmd);
    return true;
  }
  return false;
}

// The canvas: the first responder sees the key before the pushed maps.
bool canvas_input(Engine& e, const InputEvent& ev) {
  SimObject* o = e.object(e.first_responder);
  if (!o || !o->awake) return false;
  if (is_control_class(e, o, "GuiInputCtrl")) {
    if (ev.repeat) return true;
    if (is_modifier_key(lower(ev.key))) return true;  // wait for the key itself
    const std::string device = device_class(ev.device) == "keyboard" ? "keyboard" : ev.device;
    log(e, event_name(ev) + ": " + ref(o) + ".onInputEvent(" + device + ", " + action_string(ev) + ")");
    e.call_method(o, "onInputEvent", {device, action_string(ev)});
    return true;
  }
  if (is_text_edit(e, o) && edit_key(e, o, ev)) {
    if (ev.ascii || key_name(ev.key) != "return") log(e, event_name(ev) + ": " + ref(o) + " edit");
    return true;
  }
  return false;
}

} // namespace

bool Engine::process_input(const InputEvent& ev) {
  if (!ev.make) {
    const std::string device = device_class(ev.device), key = key_name(ev.key);
    for (auto it = pending_breaks.begin(); it != pending_breaks.end(); ++it) {
      if (it->device != device || it->key != key) continue;
      const PendingBreak pb = *it;
      pending_breaks.erase(it);
      fire(*this, pb.map, pb.bind, false, event_name(ev));
      return true;
    }
    return false;
  }
  if (!ev.repeat && try_map(*this, find_object("GlobalActionMap"), ev)) return true;
  if (canvas_input(*this, ev)) return true;
  if (!ev.repeat) {
    const auto maps = action_maps;
    for (auto it = maps.rbegin(); it != maps.rend(); ++it)
      if (try_map(*this, object(*it), ev)) return true;
  }
  log(*this, event_name(ev) + ": not taken");
  return false;
}

void Engine::add_console_text(const std::string& text) {
  std::size_t start = 0;
  for (;;) {
    const auto nl = text.find('\n', start);
    console_buffer.push_back(text.substr(start, nl == std::string::npos ? std::string::npos : nl - start));
    if (nl == std::string::npos) break;
    start = nl + 1;
  }
  if (console_buffer.size() > console_buffer_max)
    console_buffer.erase(console_buffer.begin(),
                         console_buffer.begin() + static_cast<std::ptrdiff_t>(console_buffer.size() - console_buffer_max));
}

void start_input_304(Engine& e) {
  // The original exports $pref::Input::MouseEnabled = "1" although
  // defaults.cs stores 0 (stage 0 capture): the engine sets it when input
  // starts with the canvas, after the prefs scripts ran.
  e.bind_variable("$pref::Input::MouseEnabled", "1");
}

void register_input_304(Engine& e) {
  // Keyboard activation (the console calls these only with
  // $enableDirectInput set). Both are registered in the 3.04 engine and
  // print nothing (lab: activateKeyboard() typed into the console).
  for (const char* name : {"activateKeyboard", "deactivateKeyboard"})
    e.add_function("", name, 1, 1, std::string(name) + "()", [](Engine&, SimObject*, Args&) { return std::string(); });

  // pushDialog(ctrl [, layer]): wake the dialog, keep the layers sorted
  // (equal layers stay in push order), and give the first focusable control
  // in it the keys when it lands on top. Pushing a dialog that is already
  // up moves it to its new layer without waking it again (policy).
  e.add_function("GuiCanvas", "pushDialog", 3, 4, "canvas.pushDialog(ctrl [, layer])", [](Engine& en, SimObject*, Args& a) {
    SimObject* ctrl = en.find_object(a[2]);
    if (!ctrl) { en.trace.push_back("pushDialog: no control " + a[2]); return std::string(); }
    const int layer = a.size() > 3 ? static_cast<std::int32_t>(parse_int(a[3])) : 0;
    DialogLayer entry{ctrl->id, layer, en.first_responder};
    bool again = false;
    for (auto it = en.dialogs.begin(); it != en.dialogs.end(); ++it)
      if (it->control == ctrl->id) { entry.previous_focus = it->previous_focus; en.dialogs.erase(it); again = true; break; }
    auto pos = std::find_if(en.dialogs.begin(), en.dialogs.end(), [&](const DialogLayer& d) { return d.layer > layer; });
    const bool on_top = pos == en.dialogs.end();
    en.dialogs.insert(pos, entry);
    if (!again) wake_control(en, ctrl->id);
    if (on_top)
      if (auto f = first_focusable(en, ctrl->id)) en.first_responder = f;
    return std::string();
  });
  // popDialog([ctrl]): without a control, the top dialog (policy).
  e.add_function("GuiCanvas", "popDialog", 2, 3, "canvas.popDialog([ctrl])", [](Engine& en, SimObject*, Args& a) {
    if (en.dialogs.empty()) return std::string();
    auto it = en.dialogs.end() - 1;
    if (a.size() > 2) {
      SimObject* ctrl = en.find_object(a[2]);
      if (!ctrl) return std::string();
      it = std::find_if(en.dialogs.begin(), en.dialogs.end(), [&](const DialogLayer& d) { return d.control == ctrl->id; });
      if (it == en.dialogs.end()) return std::string();
    }
    const DialogLayer gone = *it;
    en.dialogs.erase(it);
    sleep_control(en, gone.control);
    // Focus that was inside the popped dialog moves to the top dialog that
    // has a focusable control (a remap dialog pushed under the console gets
    // the keys when the console closes), else back to what had it before
    // the push, if that is still awake (policy).
    if (contains(en, gone.control, en.first_responder) || !en.object(en.first_responder)) {
      std::uint32_t next = 0;
      for (auto d = en.dialogs.rbegin(); d != en.dialogs.rend() && !next; ++d) next = first_focusable(en, d->control);
      if (!next) {
        const SimObject* f = en.object(gone.previous_focus);
        if (f && f->awake && !contains(en, gone.control, f->id)) next = f->id;
      }
      en.first_responder = next;
    }
    return std::string();
  });
}

} // namespace Torque
