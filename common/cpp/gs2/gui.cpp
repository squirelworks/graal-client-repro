// GS2 GUI objects, their commands, and the screen (plan step B4).

#include "gui.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <sstream>

namespace gs2::gui {

namespace {

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

bool startsWith(const std::string& s, const char* p) { return lower(s).rfind(p, 0) == 0; }

bool parseBool(const std::string& s) {
  if (lower(s) == "true") return true;
  return std::strtod(s.c_str(), nullptr) != 0;
}

void parsePair(const std::string& s, int& a, int& b) {
  std::istringstream in(s);
  double x = 0, y = 0;
  in >> x >> y;
  a = static_cast<int>(x);
  b = static_cast<int>(y);
}

// Torque key names are matched without case; modifiers in any order.
std::string normaliseAction(const std::string& s) {
  std::istringstream in(lower(s));
  std::vector<std::string> mods;
  std::string word, key;
  while (in >> word) {
    if (word == "shift" || word == "ctrl" || word == "alt") mods.push_back(word);
    else key = word;
  }
  std::sort(mods.begin(), mods.end());
  std::string out;
  for (const auto& m : mods) out += m + " ";
  return out + key;
}

Control* asControl(Var& v) { return dynamic_cast<Control*>(&v); }

ControlPtr asControlPtr(const VarPtr& v) { return std::dynamic_pointer_cast<Control>(v); }

}  // namespace

// ------------------------------------------------------------- Control

Control::Control(const std::string& name, const std::string& type) : Var(name, type) {
  setAcceptsAllProperties(true);
  profile_ = lower(type) == "guicontrolprofile";
}

bool Control::isActionMap() const { return lower(type()) == "actionmap"; }

bool Control::isControl() const { return !profile_ && !isActionMap() && startsWith(type(), "gui"); }

void Control::add(const ControlPtr& child) {
  if (!child || child.get() == this) return;
  if (child->parent_) child->parent_->removeChild(child.get());
  child->parent_ = this;
  kids_.push_back(child);
  if (owner()) child->setOwner(owner());
}

void Control::removeChild(const Control* child) {
  auto it = std::find_if(kids_.begin(), kids_.end(), [&](const ControlPtr& k) { return k.get() == child; });
  if (it == kids_.end()) return;
  (*it)->parent_ = nullptr;
  kids_.erase(it);
}

void Control::setOwner(const VarPtr& o) {
  if (!owner()) owner_ = o;
  for (const auto& k : kids_) k->setOwner(o);
}

std::string Control::prop(const std::string& key, const std::string& def) const {
  auto v = child(key);
  return v ? v->string() : def;
}

double Control::numProp(const std::string& key, double def) const {
  auto v = child(key);
  return v ? v->number() : def;
}

bool Control::flag(const std::string& key, bool def) const {
  auto v = child(key);
  if (!v) return def;
  return v->kind() == Kind::String ? parseBool(v->string()) : v->number() != 0;
}

void Control::setProp(const std::string& key, const std::string& value) { childOrCreate(key)->setString(value); }

void Control::setNumProp(const std::string& key, double value) { childOrCreate(key)->setNumber(value); }

// ------------------------------------------------------------- layout

void resizeAxis(const std::string& sizing, bool horizontal, int oldParent, int newParent, int& pos, int& len) {
  const std::string s = lower(sizing);
  const int delta = newParent - oldParent;
  if (s == "width" || s == "height") {
    len += delta;
  } else if ((horizontal && s == "left") || (!horizontal && s == "top")) {
    pos += delta;
  } else if (s == "center") {
    pos = (newParent - len) / 2;
  } else if (s == "relative" && oldParent > 0) {
    const int end = (pos + len) * newParent / oldParent;
    pos = pos * newParent / oldParent;
    len = end - pos;
  }
  if (len < 0) len = 0;
}

namespace {
// The script's own position and size: `position` and `extent`, each
// overridden by `x`, `y`, `width` or `height` when set.
void placed(const Control& c, int& x, int& y, int& w, int& h) {
  parsePair(c.prop("position", "0 0"), x, y);
  parsePair(c.prop("extent", "0 0"), w, h);
  if (c.child("x")) x = static_cast<int>(c.numProp("x"));
  if (c.child("y")) y = static_cast<int>(c.numProp("y"));
  if (c.child("width")) w = static_cast<int>(c.numProp("width"));
  if (c.child("height")) h = static_cast<int>(c.numProp("height"));
}
}  // namespace

Rect Screen::rectOf(const Control& c) const {
  int x = 0, y = 0, w = 0, h = 0;
  placed(c, x, y, w, h);
  int ow = w_, oh = h_, nw = w_, nh = h_;
  Rect base{0, 0, w_, h_};
  if (c.parent()) {
    base = rectOf(*c.parent());
    int px = 0, py = 0;
    placed(*c.parent(), px, py, ow, oh);
    nw = base.w;
    nh = base.h;
  } else {
    // A root fills the screen.
    return Rect{0, 0, w_, h_};
  }
  resizeAxis(c.prop("horizSizing", "right"), true, ow, nw, x, w);
  resizeAxis(c.prop("vertSizing", "bottom"), false, oh, nh, y, h);
  int mw = 0, mh = 0;
  parsePair(c.prop("minExtent", "0 0"), mw, mh);
  w = std::max({w, mw, c.textMinW});
  h = std::max({h, mh, c.textMinH});
  return Rect{base.x + x, base.y + y, w, h};
}

// ------------------------------------------------------------- Screen

Screen::Screen(Machine& m) : m_(m) {}

ControlPtr Screen::find(const std::string& name) const {
  auto it = byName_.find(lower(name));
  return it == byName_.end() ? nullptr : it->second;
}

ControlPtr Screen::make(const std::string& type, const std::string& name) {
  auto c = std::make_shared<Control>(name, type);
  // `new P(name)` where P is a profile copies P's fields: the profiles
  // script makes GuiSliderProfile from GuiTextProfile this way.
  if (auto base = find(type); base && base->isProfile()) {
    c->profile_ = true;
    for (const auto& [key, v] : base->Var::children()) c->childOrCreate(v->name().empty() ? key : v->name())->assignFrom(*v);
  }
  if (lower(type) == "guishowimgctrl") {
    c->emitter = std::make_shared<Emitter>(m_);
    c->childOrCreate("emitter")->setObject(c->emitter);
    // The character a show-image plays its `ani` with: `actor.head`,
    // `actor.body`, `actor.attr[n]` (the 4.04r2 main menu's StartAni1).
    c->actor = std::make_shared<Var>("actor");
    c->actor->setAcceptsAllProperties(true);
    c->actor->childOrCreate("attr")->setArray(31);
    c->childOrCreate("actor")->setObject(c->actor);
  }
  all_.push_back(c);
  if (!name.empty()) byName_[lower(name)] = c;
  return c;
}

void Screen::advanceTree(Control& c, double dt) {
  if (c.emitter) {
    const Rect r = rectOf(c);
    c.emitter->setPosition(r.x + c.numProp("offsetx"), r.y + c.numProp("offsety"));
    c.emitter->advance(dt);
  }
  for (const auto& k : c.controls()) advanceTree(*k, dt);
}

void Screen::advance(double dt) {
  if (content_) advanceTree(*content_, dt);
  for (const auto& d : dialogs_) advanceTree(*d, dt);
}

void Screen::install() {
  m_.setObjectFactory([this](Machine&, const std::string& type, const std::string& name) -> VarPtr {
    const std::string t = lower(type);
    if (t != "actionmap" && t.rfind("gui", 0) != 0 && !find(type)) return nullptr;
    auto c = make(type, name);
    // The script running `new` handles the object's events.
    if (auto o = m_.currentThis(); o && !asControl(*o)) c->setOwner(o);
    return c;
  });
  auto global = make("ActionMap", "GlobalActionMap");
  m_.universe()->childOrCreate("GlobalActionMap")->setObject(global);
  maps_.push_back(global);
  addCommands();
}

bool Screen::isAwake(const Control* c) const {
  while (c && c->parent()) c = c->parent();
  if (!c) return false;
  if (content_.get() == c) return true;
  for (const auto& d : dialogs_)
    if (d.get() == c) return true;
  return false;
}

void Screen::wake(Control& c, bool on) {
  fire(c, on ? "onWake" : "onSleep");
  for (const auto& k : c.controls()) wake(*k, on);
}

void Screen::setContent(const ControlPtr& c) {
  if (c == content_) return;
  if (content_) wake(*content_, false);
  content_ = c;
  if (c) wake(*c, true);
}

void Screen::pushDialog(const ControlPtr& c) {
  if (!c) return;
  for (const auto& d : dialogs_)
    if (d == c) return;
  dialogs_.push_back(c);
  wake(*c, true);
}

bool Screen::popDialog(const Control* c) {
  if (dialogs_.empty()) return false;
  auto it = dialogs_.end() - 1;
  if (c) {
    it = std::find_if(dialogs_.begin(), dialogs_.end(), [&](const ControlPtr& d) { return d.get() == c; });
    if (it == dialogs_.end()) return false;
  }
  ControlPtr d = *it;
  dialogs_.erase(it);
  if (auto r = responder_.lock(); r && !isAwake(r.get())) responder_.reset();
  wake(*d, false);
  return true;
}

void Screen::makeFirstResponder(const ControlPtr& c) {
  auto old = responder_.lock();
  if (old == c) return;
  responder_ = c;
  if (c) c->cursor = c->prop("text").size();
}

bool Screen::fire(Control& c, const std::string& event, std::vector<Value> args) {
  auto o = c.owner();
  const std::string fn = c.name() + "." + event;
  if (!o || c.name().empty() || !m_.hasFunction(o, fn)) return false;
  m_.callFunction(o, fn, std::move(args));
  return true;
}

// ------------------------------------------------------------- input

ControlPtr Screen::hit(const ControlPtr& c, int x, int y) const {
  if (!c || !c->flag("visible", true)) return nullptr;
  if (!rectOf(*c).contains(x, y)) return nullptr;
  const auto& kids = c->controls();
  for (auto it = kids.rbegin(); it != kids.rend(); ++it)
    if (auto h = hit(*it, x, y)) return h;
  // An inactive control does not take the press itself, so a control
  // under it does: the main menu's show-images are `active = false` and
  // cover half of a button (README.md, a reading).
  if (!c->flag("active", true)) return nullptr;
  return c;
}

void Screen::activate(Control& c, int clicks) {
  const std::string t = lower(c.type());
  if (t == "guicheckboxctrl") {
    c.setNumProp("checked", c.flag("checked") ? 0 : 1);
  } else if (t == "guiradioctrl") {
    // Radios with the same groupNum under one parent are exclusive.
    if (c.parent()) {
      const double group = c.numProp("groupNum", -1);
      for (const auto& s : c.parent()->controls())
        if (s.get() != &c && lower(s->type()) == "guiradioctrl" && s->numProp("groupNum", -1) == group)
          s->setNumProp("checked", 0);
    }
    c.setNumProp("checked", 1);
  }
  fire(c, "onAction");
  if (clicks >= 2) fire(c, "onDblClick");
}

bool Screen::mouseDown(int x, int y, int clicks) {
  ControlPtr root = !dialogs_.empty() ? dialogs_.back() : content_;
  ControlPtr target = hit(root, x, y);
  if (!target) return false;
  // Walk up to the nearest control that reacts to a press.
  for (Control* c = target.get(); c; c = c->parent()) {
    const std::string t = lower(c->type());
    if (!c->flag("active", true)) continue;
    if (t == "guibuttonctrl" || t == "guicheckboxctrl" || t == "guiradioctrl") {
      activate(*c, clicks);
      return true;
    }
    if (t == "guitexteditctrl" || t == "guimltexteditctrl") {
      makeFirstResponder(asControlPtr(c->shared_from_this()));
      return true;
    }
    if (t == "guitextlistctrl") {
      const Rect r = rectOf(*c);
      const int rowH = std::max(1, static_cast<int>(c->numProp("rowHeight", 16)));
      const int row = (y - r.y) / rowH;
      if (row >= 0 && row < static_cast<int>(c->rows.size())) {
        c->selectedRow = row;
        fire(*c, "onSelect", {Value::number(c->rows[row].id), Value::string(c->rows[row].text)});
        if (clicks >= 2) fire(*c, "onDblClick");
      }
      return true;
    }
    if (t == "guitabctrl") {
      const Rect r = rectOf(*c);
      const int tw = std::max(1, static_cast<int>(c->numProp("tabwidth", 64)));
      const int i = (x - r.x) / tw;
      if (i >= 0 && i < static_cast<int>(c->rows.size())) {
        c->selectedRow = i;
        fire(*c, "onSelect", {Value::number(c->rows[i].id), Value::string(c->rows[i].text)});
      }
      return true;
    }
    if (t == "guipopupmenuctrl" || t == "guipopupeditctrl") {
      // Without a drawn list yet, a press steps to the next row.
      if (!c->rows.empty()) {
        c->selectedRow = (c->selectedRow + 1) % static_cast<int>(c->rows.size());
        c->setProp("text", c->rows[c->selectedRow].text);
        fire(*c, "onSelect", {Value::number(c->rows[c->selectedRow].id), Value::string(c->rows[c->selectedRow].text)});
      }
      return true;
    }
    if (fire(*c, "onMouseDown")) return true;
  }
  return true;
}

bool Screen::keyDown(const std::string& key, int ch, const std::string& mods) {
  if (auto r = responder_.lock(); r && isAwake(r.get()) && r->flag("visible", true)) {
    std::string text = r->prop("text");
    std::size_t& cur = r->cursor;
    cur = std::min(cur, text.size());
    const std::string k = lower(key);
    bool took = true;
    if (k == "backspace") {
      if (cur > 0) text.erase(--cur, 1);
    } else if (k == "delete") {
      if (cur < text.size()) text.erase(cur, 1);
    } else if (k == "left") {
      if (cur > 0) --cur;
    } else if (k == "right") {
      if (cur < text.size()) ++cur;
    } else if (k == "home") {
      cur = 0;
    } else if (k == "end") {
      cur = text.size();
    } else if (k == "return" || k == "enter") {
      fire(*r, "onAction");
    } else if (ch >= 32 && ch < 256 && lower(mods).find("ctrl") == std::string::npos) {
      const double max = r->numProp("maxLength", 0);
      if (max <= 0 || text.size() < static_cast<std::size_t>(max)) text.insert(cur++, 1, static_cast<char>(ch));
    } else {
      took = false;
    }
    if (took) {
      r->setProp("text", text);
      fire(*r, "onKeyDown", {Value::string(key)});
      return true;
    }
  }
  return runBinding("keyboard", (mods.empty() ? "" : mods + " ") + key, true);
}

bool Screen::keyUp(const std::string& key, const std::string& mods) {
  return runBinding("keyboard", (mods.empty() ? "" : mods + " ") + key, false);
}

bool Screen::runBinding(const std::string& device, const std::string& action, bool down) {
  const std::string want = normaliseAction(action);
  const std::string dev = lower(device);
  // GlobalActionMap first, then the pushed maps newest first.
  std::vector<ControlPtr> order;
  if (!maps_.empty()) order.push_back(maps_.front());
  for (auto it = maps_.rbegin(); it != maps_.rend() && it != maps_.rend() - 1; ++it) order.push_back(*it);
  for (const auto& map : order) {
    for (const auto& b : map->bindings) {
      if (lower(b.device).rfind(dev, 0) != 0 || normaliseAction(b.action) != want) continue;
      auto o = map->owner();
      std::vector<Value> args{Value::number(down ? 1 : 0)};
      if (o && m_.hasFunction(o, b.command)) m_.callFunction(o, b.command, args);
      else if (onEngineAction) onEngineAction(b.command, down);
      return true;
    }
  }
  return false;
}

// ------------------------------------------------------------- commands

void Screen::addCommands() {
  Machine& m = m_;

  // addcontrol(obj): inside `with (parent)` the new control becomes the
  // parent's child; outside any GUI object (the script itself) the control
  // is a root and the script becomes the owner of its events.
  m.addCommand("addcontrol", "o", [](Machine& mm, Var& self, std::vector<Value>& a) {
    auto child = asControlPtr(mm.toObject(a[0]));
    if (!child) return Value::number(0);
    if (Control* parent = asControl(self); parent && parent->isControl() && child->isControl()) {
      parent->add(child);
    } else {
      child->setOwner(self.shared_from_this());
    }
    return Value::number(1);
  });

  m.addCommand("pushDialog", "o", [this](Machine& mm, Var&, std::vector<Value>& a) {
    auto c = asControlPtr(mm.toObject(a[0]));
    if (c) pushDialog(c);
    return Value::number(c ? 1 : 0);
  });
  m.addCommand("popDialog", "", [this](Machine& mm, Var&, std::vector<Value>& a) {
    ControlPtr c = a.empty() ? nullptr : asControlPtr(mm.toObject(a[0]));
    return Value::number(popDialog(c.get()) ? 1 : 0);
  });
  m.addCommand("cursorOn", "", [this](Machine&, Var&, std::vector<Value>&) {
    cursor_ = true;
    return Value::number(0);
  });
  m.addCommand("cursorOff", "", [this](Machine&, Var&, std::vector<Value>&) {
    cursor_ = false;
    return Value::number(0);
  });

  // GuiControl.
  m.addCommand("GuiControl.makeFirstResponder", "", [this](Machine& mm, Var& self, std::vector<Value>& a) {
    auto c = asControlPtr(self.shared_from_this());
    const bool on = a.empty() || mm.toNumber(a[0]) != 0;
    if (on) makeFirstResponder(c);
    else if (firstResponder() == c) makeFirstResponder(nullptr);
    return Value::number(0);
  });

  // Rows: GuiTextListCtrl and GuiPopUpMenuCtrl. A row is an id and a text
  // whose columns are separated by tabs.
  auto rowCommands = [&](const std::string& cls, bool rowObjects) {
    m.addCommand(cls + ".clearRows", "", [](Machine&, Var& self, std::vector<Value>&) {
      if (auto c = asControl(self)) { c->rows.clear(); c->selectedRow = -1; }
      return Value::number(0);
    });
    m.addCommand(cls + ".addRow", "fs", [rowObjects](Machine& mm, Var& self, std::vector<Value>& a) {
      auto c = asControl(self);
      if (!c) return Value::number(-1);
      Control::Row r{mm.toNumber(a[0]), mm.toString(a[1]), nullptr};
      long at = a.size() > 2 ? static_cast<long>(mm.toNumber(a[2])) : -1;
      if (at < 0 || at > static_cast<long>(c->rows.size())) at = static_cast<long>(c->rows.size());
      if (rowObjects) {
        r.object = std::make_shared<Var>(r.text, "GuiTabRow");
        r.object->setAcceptsAllProperties(true);
        r.object->childOrCreate("id")->setNumber(r.id);
        r.object->childOrCreate("text")->setString(r.text);
      }
      c->rows.insert(c->rows.begin() + at, r);
      if (r.object) return Value::object(r.object);
      return Value::number(static_cast<double>(at));
    });
    m.addCommand(cls + ".setRowById", "fs", [](Machine& mm, Var& self, std::vector<Value>& a) {
      auto c = asControl(self);
      if (!c) return Value::number(0);
      for (auto& r : c->rows)
        if (r.id == mm.toNumber(a[0])) { r.text = mm.toString(a[1]); return Value::number(1); }
      return Value::number(0);
    });
    m.addCommand(cls + ".rowCount", "", [](Machine&, Var& self, std::vector<Value>&) {
      auto c = asControl(self);
      return Value::number(c ? static_cast<double>(c->rows.size()) : 0);
    });
    m.addCommand(cls + ".setSelectedRow", "f", [](Machine& mm, Var& self, std::vector<Value>& a) {
      auto c = asControl(self);
      if (!c) return Value::number(0);
      const long i = static_cast<long>(mm.toNumber(a[0]));
      c->selectedRow = (i >= 0 && i < static_cast<long>(c->rows.size())) ? static_cast<int>(i) : -1;
      if (c->selectedRow >= 0) c->setProp("text", c->rows[c->selectedRow].text);
      return Value::number(0);
    });
    m.addCommand(cls + ".setSelectedById", "f", [](Machine& mm, Var& self, std::vector<Value>& a) {
      auto c = asControl(self);
      if (!c) return Value::number(0);
      c->selectedRow = -1;
      for (std::size_t i = 0; i < c->rows.size(); ++i)
        if (c->rows[i].id == mm.toNumber(a[0])) {
          c->selectedRow = static_cast<int>(i);
          c->setProp("text", c->rows[i].text);
        }
      return Value::number(c->selectedRow >= 0 ? 1 : 0);
    });
    // getSelectedRow: the selected row's index, -1 for none. The 5.12
    // options window keeps it across clearRows and addRow on its tabs.
    m.addCommand(cls + ".getSelectedRow", "", [](Machine&, Var& self, std::vector<Value>&) {
      auto c = asControl(self);
      return Value::number(c ? c->selectedRow : -1);
    });
    m.addCommand(cls + ".getSelectedId", "", [](Machine&, Var& self, std::vector<Value>&) {
      auto c = asControl(self);
      if (!c || c->selectedRow < 0) return Value::number(-1);
      return Value::number(c->rows[c->selectedRow].id);
    });
    m.addCommand(cls + ".getSelected", "", [](Machine&, Var& self, std::vector<Value>&) {
      auto c = asControl(self);
      if (!c || c->selectedRow < 0) return Value::number(-1);
      return Value::number(c->rows[c->selectedRow].id);
    });
    m.addCommand(cls + ".getSelectedText", "", [](Machine&, Var& self, std::vector<Value>&) {
      auto c = asControl(self);
      if (!c || c->selectedRow < 0) return Value::string("");
      return Value::string(c->rows[c->selectedRow].text);
    });
    // findText(text): the row index, -1 when absent. findTextId: its id.
    m.addCommand(cls + ".findText", "s", [](Machine& mm, Var& self, std::vector<Value>& a) {
      auto c = asControl(self);
      if (!c) return Value::number(-1);
      const std::string want = lower(mm.toString(a[0]));
      for (std::size_t i = 0; i < c->rows.size(); ++i)
        if (lower(c->rows[i].text) == want) return Value::number(static_cast<double>(i));
      return Value::number(-1);
    });
    m.addCommand(cls + ".findTextId", "s", [](Machine& mm, Var& self, std::vector<Value>& a) {
      auto c = asControl(self);
      if (!c) return Value::number(-1);
      const std::string want = lower(mm.toString(a[0]));
      for (const auto& r : c->rows)
        if (lower(r.text) == want) return Value::number(r.id);
      return Value::number(-1);
    });
    m.addCommand(cls + ".sort", "", [](Machine&, Var& self, std::vector<Value>&) {
      auto c = asControl(self);
      if (!c) return Value::number(0);
      std::stable_sort(c->rows.begin(), c->rows.end(),
                       [](const Control::Row& x, const Control::Row& y) { return lower(x.text) < lower(y.text); });
      c->selectedRow = -1;
      return Value::number(0);
    });
  };
  rowCommands("GuiTextListCtrl", false);
  rowCommands("GuiPopUpMenuCtrl", false);
  rowCommands("GuiPopUpEditCtrl", false);
  // GuiTabCtrl.addRow returns the tab, which the options window then
  // gives a `hint` inside `with` (README.md, a reading).
  rowCommands("GuiTabCtrl", true);

  // GuiTextEditCtrl.setSelection(start, end): here only the cursor moves to
  // the end of the selection.
  m.addCommand("GuiTextEditCtrl.setSelection", "ff", [](Machine& mm, Var& self, std::vector<Value>& a) {
    if (auto c = asControl(self)) c->cursor = static_cast<std::size_t>(std::max(0.0, mm.toNumber(a[1])));
    return Value::number(0);
  });

  // The show-image emitter: add{local,global,emit}modifier(type, time1,
  // time2, field, operation, min, max) and removemodifiers().
  auto modifier = [&](const char* name, Emitter::List which) {
    m.addCommand(std::string("TParticleEmitter.") + name, "sffssff", [which](Machine& mm, Var& self, std::vector<Value>& a) {
      auto e = dynamic_cast<Emitter*>(&self);
      if (!e) return Value::number(0);
      const bool ok = e->addModifier(which, mm.toString(a[0]), mm.toNumber(a[1]), mm.toNumber(a[2]), mm.toString(a[3]),
                                     mm.toString(a[4]), mm.toNumber(a[5]), mm.toNumber(a[6]));
      return Value::number(ok ? 1 : 0);
    });
  };
  modifier("addlocalmodifier", Emitter::List::Local);
  modifier("addglobalmodifier", Emitter::List::Global);
  modifier("addemitmodifier", Emitter::List::Emit);
  m.addCommand("TParticleEmitter.removemodifiers", "", [](Machine&, Var& self, std::vector<Value>&) {
    if (auto e = dynamic_cast<Emitter*>(&self)) e->removeModifiers();
    return Value::number(0);
  });

  // ActionMap: bind(device, action, command), getBinding(command) as
  // "device<TAB>action", getCommand(device, action), push and pop.
  m.addCommand("ActionMap.bind", "sss", [](Machine& mm, Var& self, std::vector<Value>& a) {
    auto c = asControl(self);
    if (!c) return Value::number(0);
    Control::Binding b{mm.toString(a[0]), mm.toString(a[1]), mm.toString(a[2])};
    for (auto& old : c->bindings)
      if (lower(old.device) == lower(b.device) && normaliseAction(old.action) == normaliseAction(b.action)) {
        old.command = b.command;
        return Value::number(1);
      }
    c->bindings.push_back(b);
    return Value::number(1);
  });
  m.addCommand("ActionMap.unbind", "ss", [](Machine& mm, Var& self, std::vector<Value>& a) {
    auto c = asControl(self);
    if (!c) return Value::number(0);
    const std::string dev = lower(mm.toString(a[0])), act = normaliseAction(mm.toString(a[1]));
    auto& v = c->bindings;
    const auto n = v.size();
    v.erase(std::remove_if(v.begin(), v.end(),
                           [&](const Control::Binding& b) { return lower(b.device) == dev && normaliseAction(b.action) == act; }),
            v.end());
    return Value::number(v.size() != n ? 1 : 0);
  });
  m.addCommand("ActionMap.getBinding", "s", [](Machine& mm, Var& self, std::vector<Value>& a) {
    auto c = asControl(self);
    const std::string want = lower(mm.toString(a[0]));
    if (c)
      for (const auto& b : c->bindings)
        if (lower(b.command) == want) return Value::string(b.device + "\t" + b.action);
    return Value::string("");
  });
  m.addCommand("ActionMap.getCommand", "ss", [](Machine& mm, Var& self, std::vector<Value>& a) {
    auto c = asControl(self);
    const std::string dev = lower(mm.toString(a[0])), act = normaliseAction(mm.toString(a[1]));
    if (c)
      for (const auto& b : c->bindings)
        if (lower(b.device) == dev && normaliseAction(b.action) == act) return Value::string(b.command);
    return Value::string("");
  });
  m.addCommand("ActionMap.push", "", [this](Machine&, Var& self, std::vector<Value>&) {
    auto c = asControlPtr(self.shared_from_this());
    if (!c || c == maps_.front()) return Value::number(0);
    maps_.erase(std::remove(maps_.begin() + 1, maps_.end(), c), maps_.end());
    maps_.push_back(c);
    return Value::number(1);
  });
  m.addCommand("ActionMap.pop", "", [this](Machine&, Var& self, std::vector<Value>&) {
    auto c = asControlPtr(self.shared_from_this());
    if (!c || c == maps_.front()) return Value::number(0);
    const auto n = maps_.size();
    maps_.erase(std::remove(maps_.begin() + 1, maps_.end(), c), maps_.end());
    return Value::number(maps_.size() != n ? 1 : 0);
  });
}

}  // namespace gs2::gui
