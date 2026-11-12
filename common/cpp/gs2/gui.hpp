#pragma once

// GS2 GUI objects (plan step B4): the controls, profiles and key maps the
// shell scripts make with `new T(name)`, the commands they call on them,
// and the screen that shows them (content, dialogs, first responder, key
// maps). Drawing is in gui_draw.hpp, through a Painter the engine program
// supplies; nothing here draws or knows the window.
//
// What the scripts expect is read from the 4.04r2 menus (README.md, "GUI
// objects"): the class names and property names are Torque's, so the
// behaviour follows the Torque stock controls the 3.04 rebuild already
// draws (common/torque/gui). Where neither the menus nor Graal_analysis
// say what the engines do, the choice is marked as a reading in README.md.

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "emitter.hpp"
#include "gs2.hpp"

namespace gs2::gui {

class Control;
using ControlPtr = std::shared_ptr<Control>;

// One GUI object. Its properties (`profile`, `position`, `extent`,
// `text`, `visible`, `checked`, ...) are its child variables, as the
// scripts set them; it takes every property name (the engines' property
// lists are not read).
class Control : public Var {
 public:
  Control(const std::string& name, const std::string& type);

  // GuiControlProfile, or a profile made from another profile by name.
  bool isProfile() const { return profile_; }
  bool isActionMap() const;
  // Anything else made as a Gui* class is a control.
  bool isControl() const;

  const std::vector<ControlPtr>& controls() const { return kids_; }
  Control* parent() const { return parent_; }
  void add(const ControlPtr& child);
  void removeChild(const Control* child);

  // The script object whose functions handle this object's events
  // (`Name.onAction` and the rest, and a key map's bound functions): the
  // script that ran `new`, else the one that added it with addcontrol.
  VarPtr owner() const { return owner_.lock(); }
  void setOwner(const VarPtr& o);  // also every descendant without one

  // Property helpers.
  std::string prop(const std::string& key, const std::string& def = "") const;
  double numProp(const std::string& key, double def = 0) const;
  bool flag(const std::string& key, bool def = false) const;
  void setProp(const std::string& key, const std::string& value);
  void setNumProp(const std::string& key, double value);

  // GuiTextListCtrl, GuiPopUpMenuCtrl and GuiTabCtrl rows. A tab row is
  // also an object the script sets fields on (`with (addRow(...))`).
  struct Row {
    double id = 0;
    std::string text;
    VarPtr object;
  };
  std::vector<Row> rows;
  int selectedRow = -1;

  // ActionMap bindings.
  struct Binding {
    std::string device, action, command;
  };
  std::vector<Binding> bindings;

  // GuiTextEditCtrl: the cursor position in `text`.
  std::size_t cursor = 0;

  // GuiTextCtrl: its text's width and the font height, measured when it is
  // drawn. Like Torque's minExtent after setText, the control is never laid
  // out smaller than this, so a label does not clip its own text.
  int textMinW = 0, textMinH = 0;

  // GuiShowImgCtrl: its particle emitter, the script's `emitter`.
  std::shared_ptr<Emitter> emitter;

 private:
  friend class Screen;
  bool profile_ = false;
  Control* parent_ = nullptr;
  std::vector<ControlPtr> kids_;
  std::weak_ptr<Var> owner_;
};

struct Rect {
  int x = 0, y = 0, w = 0, h = 0;
  bool contains(int px, int py) const { return px >= x && py >= y && px < x + w && py < y + h; }
};

// Torque's horizSizing / vertSizing applied when the parent's size changes
// from `oldParent` to `newParent` (common/torque/gui README, "Layout").
void resizeAxis(const std::string& sizing, bool horizontal, int oldParent, int newParent, int& pos, int& len);

class Screen {
 public:
  explicit Screen(Machine& m);
  Screen(const Screen&) = delete;
  Screen& operator=(const Screen&) = delete;

  // Installs the object factory and the GUI commands on the machine, and
  // makes `GlobalActionMap`, which the engine supplies and is always active.
  void install();

  Machine& machine() { return m_; }

  // Objects by name (case-insensitive), as made by `new`.
  ControlPtr find(const std::string& name) const;
  const std::vector<ControlPtr>& all() const { return all_; }

  // The screen size the content and dialogs are laid out to.
  void setSize(int w, int h) { w_ = w; h_ = h; }
  int width() const { return w_; }
  int height() const { return h_; }

  // The content control (the engine makes `MainMenuGui2D` the content) and
  // the dialogs over it. Making a control the content or pushing it as a
  // dialog wakes it and its descendants (`onWake`, parents first); taking
  // it away puts them to sleep (`onSleep`).
  void setContent(const ControlPtr& c);
  ControlPtr content() const { return content_; }
  void pushDialog(const ControlPtr& c);
  bool popDialog(const Control* c);  // null pops the top dialog
  const std::vector<ControlPtr>& dialogs() const { return dialogs_; }
  bool isAwake(const Control* c) const;

  // Where each control is on the screen: its `position` and `extent` (or
  // `x`, `y`, `width`, `height`, which the menus also set) laid out
  // against its parent's drawn size. Roots fill the screen.
  Rect rectOf(const Control& c) const;

  // The control that takes key input (a text edit), or null.
  ControlPtr firstResponder() const { return responder_.lock(); }
  void makeFirstResponder(const ControlPtr& c);

  bool cursorShown() const { return cursor_; }

  // Runs the event function `Name.event` of the control's owner, when the
  // owner's script has one. Returns whether it ran.
  bool fire(Control& c, const std::string& event, std::vector<Value> args = {});

  // Input, in screen pixels. A press goes to the topmost visible, active
  // control under the point (an inactive one lets it through to what is
  // under it) in the top dialog (or the content when there
  // is none). Returns whether a control took it.
  bool mouseDown(int x, int y, int clicks = 1);
  // Keys: `key` is the Torque key name ("a", "up", "escape", "F2", ...),
  // `ch` the character typed (0 for none), `mods` "shift", "ctrl", "alt"
  // joined by spaces. The first responder takes characters, backspace,
  // delete, left, right, home, end and return; then the key maps.
  bool keyDown(const std::string& key, int ch, const std::string& mods = "");
  bool keyUp(const std::string& key, const std::string& mods = "");

  // Runs the show-images' emitters `dt` seconds, each placed at its
  // control's screen position plus (`offsetx`, `offsety`). Only controls
  // on the screen run.
  void advance(double dt);

  // Key maps: GlobalActionMap first, then the pushed maps, newest first.
  const std::vector<ControlPtr>& actionMaps() const { return maps_; }
  // A bound command that is no script function goes here (the engine's
  // own actions: moveUp2D, doA, toggleConsole and the rest), with
  // down = true on press and false on release.
  std::function<void(const std::string& command, bool down)> onEngineAction;

 private:
  ControlPtr make(const std::string& type, const std::string& name);
  void addCommands();
  void wake(Control& c, bool on);
  void advanceTree(Control& c, double dt);
  ControlPtr hit(const ControlPtr& c, int x, int y) const;
  void activate(Control& c, int clicks);
  bool runBinding(const std::string& device, const std::string& action, bool down);

  Machine& m_;
  int w_ = 640, h_ = 480;
  std::vector<ControlPtr> all_;
  std::map<std::string, ControlPtr> byName_;  // lower-cased
  ControlPtr content_;
  std::vector<ControlPtr> dialogs_;
  std::vector<ControlPtr> maps_;
  std::weak_ptr<Control> responder_;
  bool cursor_ = true;
};

}  // namespace gs2::gui
