// Tests for the GS2 GUI objects and their drawing (plan step B4). The
// scripts are written by hand with tests/assembler.hpp in the shape the
// 4.04r2 menus compile to (README.md, "GUI objects").

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include "../gs2.hpp"
#include "../gui.hpp"
#include "../emitter.hpp"
#include "../gui_draw.hpp"
#include "assembler.hpp"

using gs2asm::Asm;
using namespace gs2::gui;

static int failures = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) {                                                      \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                       \
    }                                                                   \
  } while (0)

namespace {

// new T("Name") { ... }: returns the with block's jump operand.
std::size_t beginNew(Asm& a, const std::string& type, const std::string& name) {
  a.str(name).op(40).op(Asm::COPY).op(Asm::COPY).op(Asm::COPY);
  a.str(type).op(Asm::TOSTRING).op(42).op(Asm::ASSIGN).op(Asm::TOOBJECT).op(Asm::WITH);
  return a.jumpOperand();
}

// ...}; addcontrol(it)
void endNew(Asm& a, std::size_t end) {
  a.op(Asm::ENDWITH);
  a.patch(end, a.here());
  a.op(Asm::MARKER).op(Asm::SWAP).callName("addcontrol").op(Asm::POP);
}

void prop(Asm& a, const std::string& k, const std::string& v) { a.var(k).str(v).op(Asm::ASSIGN); }

double global(gs2::Machine& m, const std::string& n) {
  auto v = m.universe()->child(n);
  return v ? v->number() : -1;
}

// A painter that records what it is asked to draw. Text is 6 pixels a
// character, 14 tall; `theme.png` is a 36-cell array of 4 x 4 cells.
struct Recorder : Painter {
  std::vector<std::string> calls;
  Rect clip;
  void setClip(const Rect& r) override { clip = r; }
  void fill(const Rect& r, Color c) override {
    char b[96];
    std::snprintf(b, sizeof b, "fill %d,%d,%d,%d %d,%d,%d", r.x, r.y, r.w, r.h, c.r, c.g, c.b);
    calls.push_back(b);
  }
  void text(int x, int y, const std::string& s, const std::string&, int, Color) override {
    calls.push_back("text " + std::to_string(x) + "," + std::to_string(y) + " " + s);
  }
  int textWidth(const std::string& s, const std::string&, int) override { return 6 * static_cast<int>(s.size()); }
  int fontHeight(const std::string&, int) override { return 14; }
  bool bitmapSize(const std::string& f, int& w, int& h) override {
    w = h = 16;
    return f == "theme.png" || f == "back.png";
  }
  std::vector<Rect> cells(const std::string& f) override {
    std::vector<Rect> out;
    if (f != "theme.png") return out;
    for (int i = 0; i < 36; ++i) out.push_back({(i % 3) * 5, (i / 3) * 5, 4, 4});
    return out;
  }
  void bitmap(const std::string& f, const Rect& src, const Rect& dst) override {
    char b[128];
    std::snprintf(b, sizeof b, "bitmap %s %d,%d -> %d,%d,%d,%d", f.c_str(), src.x, src.y, dst.x, dst.y, dst.w, dst.h);
    calls.push_back(b);
  }
  bool has(const std::string& s) const {
    for (const auto& c : calls)
      if (c == s) return true;
    return false;
  }
};

// The menu: a profile, a content control with a button, a check box, a
// text edit, a text list and a key map; event functions in the script.
Asm menu() {
  Asm a;
  a.function("onCreated", {});
  auto p = beginNew(a, "GuiControlProfile", "GuiDefaultProfile");
  prop(a, "fontColor", "1 2 3");
  prop(a, "fillColor", "9 9 9");
  endNew(a, p);
  auto q = beginNew(a, "GuiDefaultProfile", "ButtonProfile");
  prop(a, "bitmap", "theme.png");
  endNew(a, q);
  auto root = beginNew(a, "GuiControl", "MainMenu");
  prop(a, "extent", "640 480");
  prop(a, "horizSizing", "width");
  auto b = beginNew(a, "GuiButtonCtrl", "GoButton");
  prop(a, "profile", "ButtonProfile");
  prop(a, "position", "10 20");
  prop(a, "extent", "100 30");
  prop(a, "horizSizing", "left");
  prop(a, "text", "Go");
  endNew(a, b);
  auto c = beginNew(a, "GuiCheckBoxCtrl", "Remember");
  prop(a, "position", "10 60");
  prop(a, "extent", "100 20");
  prop(a, "text", "Remember");
  endNew(a, c);
  auto e = beginNew(a, "GuiTextEditCtrl", "NameEdit");
  prop(a, "position", "10 90");
  prop(a, "extent", "100 20");
  endNew(a, e);
  auto lb = beginNew(a, "GuiTextCtrl", "NameLabel");
  prop(a, "position", "10 120");
  prop(a, "extent", "20 10");
  prop(a, "text", "Nickname");
  endNew(a, lb);
  auto l = beginNew(a, "GuiTextListCtrl", "List");
  prop(a, "position", "200 100");
  prop(a, "extent", "200 100");
  prop(a, "columns", "0 100");
  endNew(a, l);
  endNew(a, root);
  // List.addRow(5, "five\tcol"); List.addRow(7, "seven");
  a.op(Asm::MARKER).str("five\tcol").num(5).var("List").op(Asm::TOOBJECT).var("addRow").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  a.op(Asm::MARKER).str("seven").num(7).var("List").op(Asm::TOOBJECT).var("addRow").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  auto km = beginNew(a, "ActionMap", "keys");
  a.op(Asm::ENDWITH);
  a.patch(km, a.here());
  a.op(Asm::POP);
  // keys.bind("keyboard", "F5", "openWindow"); keys.bind("keyboard", "up", "moveUp2D"); keys.push();
  a.op(Asm::MARKER).str("openWindow").str("F5").str("keyboard").var("keys").op(Asm::TOOBJECT).var("bind").op(Asm::MEMBER)
      .op(Asm::CALL).op(Asm::POP);
  a.op(Asm::MARKER).str("moveUp2D").str("up").str("keyboard").var("keys").op(Asm::TOOBJECT).var("bind").op(Asm::MEMBER)
      .op(Asm::CALL).op(Asm::POP);
  a.op(Asm::MARKER).var("keys").op(Asm::TOOBJECT).var("push").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  a.num(0).op(Asm::RET);

  a.function("GoButton.onAction", {});
  a.var("clicked").num(1).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  a.function("MainMenu.onWake", {});
  a.var("woke").num(1).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  a.function("MainMenu.onSleep", {});
  a.var("slept").num(1).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  a.function("List.onSelect", {"id", "text"});
  a.var("picked").var("id").op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  a.function("openWindow", {"down"});
  a.var("opened").var("down").op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  return a;
}

}  // namespace

static void testObjectsAndCommands() {
  gs2::Machine m;
  Screen s(m);
  s.install();
  auto script = m.newVar("StartScript_Test");
  std::string err;
  CHECK(m.setScript(script, menu().bytes(), &err));
  m.runScripts();
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(m.errors().empty());

  auto root = s.find("MainMenu");
  CHECK(root && root->isControl() && root->controls().size() == 5);
  CHECK(root && root->owner() == script);
  auto btn = s.find("gobutton");  // names are found without case
  CHECK(btn && btn->parent() == root.get() && btn->owner() == script);
  // Profiles: one made from another copies its fields.
  auto bp = s.find("ButtonProfile");
  CHECK(bp && bp->isProfile() && bp->prop("fontColor") == "1 2 3" && bp->prop("bitmap") == "theme.png");
  CHECK(!bp->isControl());
  // Rows.
  auto list = s.find("List");
  CHECK(list && list->rows.size() == 2 && list->rows[0].id == 5 && list->rows[1].text == "seven");
  // The key map.
  auto keys = s.find("keys");
  CHECK(keys && keys->isActionMap() && keys->bindings.size() == 2);
  CHECK(s.actionMaps().size() == 2 && s.actionMaps()[1] == keys);

  // Layout at 800 x 600: the root fills the screen; the button keeps its
  // distance from the right edge (horizSizing left, parent grew by 160).
  s.setSize(800, 600);
  Rect r = s.rectOf(*btn);
  CHECK(r.x == 170 && r.y == 20 && r.w == 100 && r.h == 30);
  Rect lr = s.rectOf(*list);
  CHECK(lr.x == 200 && lr.y == 100);

  // Content wakes, and sleeps when replaced.
  s.setContent(root);
  CHECK(global(m, "woke") == 1);
  CHECK(s.isAwake(btn.get()));

  // A press on the button runs GoButton.onAction in the owner's script.
  CHECK(s.mouseDown(175, 25));
  CHECK(global(m, "clicked") == 1);
  // An inactive control over the button lets the press through.
  auto cover = std::make_shared<Control>("Cover", "GuiShowImgCtrl");
  cover->setProp("position", "160 0");
  cover->setProp("extent", "100 100");
  cover->setNumProp("active", 0);
  root->add(cover);
  m.universe()->childOrCreate("clicked")->setNumber(0);
  CHECK(s.mouseDown(175, 25));
  CHECK(global(m, "clicked") == 1);
  root->removeChild(cover.get());
  // A press on the check box toggles it.
  auto check = s.find("Remember");
  CHECK(s.mouseDown(15, 65) && check->flag("checked"));
  CHECK(s.mouseDown(15, 65) && !check->flag("checked"));
  // A press on the second row selects it and runs List.onSelect(id, text).
  CHECK(s.mouseDown(210, 100 + 16 + 2));
  CHECK(list->selectedRow == 1 && global(m, "picked") == 7);
  // The text edit takes the key focus and typed characters.
  auto edit = s.find("NameEdit");
  CHECK(s.mouseDown(15, 95) && s.firstResponder() == edit);
  s.keyDown("a", 'a');
  s.keyDown("b", 'b');
  s.keyDown("left", 0);
  s.keyDown("c", 'c');
  s.keyDown("backspace", 0);
  s.keyDown("x", 'x');
  CHECK(edit->prop("text") == "axb");
  // Keys the text edit does not use go to the key maps: a script function
  // gets 1 on press and 0 on release; an engine action goes to the hook.
  std::vector<std::string> actions;
  s.onEngineAction = [&](const std::string& c, bool down) { actions.push_back(c + (down ? "+" : "-")); };
  CHECK(s.keyDown("F5", 0) && global(m, "opened") == 1);
  CHECK(s.keyUp("F5") && global(m, "opened") == 0);
  CHECK(s.keyDown("up", 0) && actions.size() == 1 && actions[0] == "moveUp2D+");
  CHECK(!s.keyDown("F9", 0));

  // Dialogs: pushDialog takes the input; popDialog wakes nothing new.
  auto dlg = std::make_shared<Control>("Dlg", "GuiControl");
  s.pushDialog(dlg);
  CHECK(s.dialogs().size() == 1);
  CHECK(!s.mouseDown(-5, -5));
  CHECK(s.popDialog(nullptr) && s.dialogs().empty());
  s.setContent(nullptr);
  CHECK(global(m, "slept") == 1);
  CHECK(!s.isAwake(btn.get()));
}

static void testScriptCommands() {
  // addRow, findText, setSelectedById, getSelectedId, getBinding, pushDialog
  // and popDialog called from script.
  gs2::Machine m;
  Screen s(m);
  s.install();
  Asm a;
  a.function("onCreated", {});
  auto l = beginNew(a, "GuiPopUpMenuCtrl", "Menu");
  a.op(Asm::ENDWITH);
  a.patch(l, a.here());
  a.op(Asm::POP);
  auto d = beginNew(a, "GuiControl", "Dialog");
  endNew(a, d);
  a.op(Asm::MARKER).str("English").num(1).var("Menu").op(Asm::TOOBJECT).var("addRow").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  a.op(Asm::MARKER).str("Deutsch").num(2).var("Menu").op(Asm::TOOBJECT).var("addRow").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  // found = Menu.findText("deutsch");
  a.var("found").op(Asm::MARKER).str("deutsch").var("Menu").op(Asm::TOOBJECT).var("findText").op(Asm::MEMBER).op(Asm::CALL)
      .op(Asm::ASSIGN);
  // Menu.setSelectedById(2); sel = Menu.getSelectedId();
  a.op(Asm::MARKER).num(2).var("Menu").op(Asm::TOOBJECT).var("setSelectedById").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  a.var("sel").op(Asm::MARKER).var("Menu").op(Asm::TOOBJECT).var("getSelectedId").op(Asm::MEMBER).op(Asm::CALL).op(Asm::ASSIGN);
  a.var("selrow").op(Asm::MARKER).var("Menu").op(Asm::TOOBJECT).var("getSelectedRow").op(Asm::MEMBER).op(Asm::CALL)
      .op(Asm::ASSIGN);
  // GlobalActionMap.bind("keyboard", "F2", "toggleConsole");
  // binding = GlobalActionMap.getBinding("toggleConsole");
  a.op(Asm::MARKER).str("toggleConsole").str("F2").str("keyboard").var("GlobalActionMap").op(Asm::TOOBJECT).var("bind")
      .op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  a.var("binding").op(Asm::MARKER).str("toggleConsole").var("GlobalActionMap").op(Asm::TOOBJECT).var("getBinding")
      .op(Asm::MEMBER).op(Asm::CALL).op(Asm::ASSIGN);
  // pushDialog(Dialog);
  a.op(Asm::MARKER).var("Dialog").callName("pushDialog").op(Asm::POP);
  a.num(0).op(Asm::RET);
  auto v = m.newVar("StartScript_Menu");
  std::string err;
  CHECK(m.setScript(v, a.bytes(), &err));
  m.runScripts();
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(m.errors().empty());
  CHECK(global(m, "found") == 1);
  CHECK(global(m, "sel") == 2);
  CHECK(global(m, "selrow") == 1);
  auto menuCtl = s.find("Menu");
  CHECK(menuCtl && menuCtl->prop("text") == "Deutsch");
  auto b = m.universe()->child("binding");
  CHECK(b && b->string() == "keyboard\tF2");
  CHECK(s.dialogs().size() == 1 && s.dialogs()[0] == s.find("Dialog"));
}

static void testDrawing() {
  gs2::Machine m;
  Screen s(m);
  s.install();
  auto script = m.newVar("StartScript_Test");
  CHECK(m.setScript(script, menu().bytes()));
  m.runScripts();
  s.setSize(640, 480);
  s.setContent(s.find("MainMenu"));
  s.find("List")->selectedRow = 0;
  Recorder p;
  drawScreen(s, p);
  // The button draws its normal frame from the theme's first nine cells:
  // the top-left corner as it is, the centre stretched.
  CHECK(p.has("bitmap theme.png 0,0 -> 10,20,4,4"));
  CHECK(p.has("bitmap theme.png 5,5 -> 14,24,92,22"));
  // Its label is centred: 2 characters, 12 pixels, in a 100 x 30 box;
  // the line box is the font height less two rows.
  CHECK(p.has("text 54,29 Go"));
  // The check box without a theme draws a box and its text after it.
  CHECK(p.has("text 25,64 Remember"));
  // The selected row is filled and its columns are drawn at their offsets.
  CHECK(p.has("text 200,100 five"));
  CHECK(p.has("text 300,100 col"));
  // A label grows to its text (8 characters, 48 pixels) and the font
  // height, past its 20 x 10 extent.
  const Rect lr = s.rectOf(*s.find("NameLabel"));
  CHECK(lr.x == 10 && lr.y == 120 && lr.w == 48 && lr.h == 14);
  CHECK(p.has("text 200,114 seven"));
  // Hidden controls draw nothing.
  s.find("GoButton")->setNumProp("visible", 0);
  Recorder p2;
  drawScreen(s, p2);
  CHECK(!p2.has("text 54,29 Go"));
  // An inactive button draws the inactive set (cells 27 onwards).
  s.find("GoButton")->setNumProp("visible", 1);
  s.find("GoButton")->setNumProp("active", 0);
  Recorder p3;
  drawScreen(s, p3);
  CHECK(p3.has("bitmap theme.png 0,45 -> 10,20,4,4"));
  CHECK(parseColor("1 2 300").b == 255 && parseColor("4 5 6").a == 255);
}


static void testEmitter() {
  gs2::Machine m;
  Screen s(m);
  s.install();
  // A show-image with an emitter, set up from script the way the 4.04r2
  // main menu does it.
  Asm a;
  a.function("onCreated", {});
  auto root = beginNew(a, "GuiControl", "Root");
  auto img = beginNew(a, "GuiShowImgCtrl", "Smoke");
  prop(a, "position", "100 100");
  prop(a, "extent", "50 50");
  a.var("offsetx").num(10).op(Asm::ASSIGN);
  a.var("offsety").num(20).op(Asm::ASSIGN);
  auto em = [&](const std::string& k, double v) {
    a.var("emitter").op(Asm::TOOBJECT).var(k).op(Asm::MEMBER).num(v).op(Asm::ASSIGN);
  };
  auto part = [&](const std::string& k) {
    a.var("emitter").op(Asm::TOOBJECT).var("particle").op(Asm::MEMBER).op(Asm::TOOBJECT).var(k).op(Asm::MEMBER);
  };
  em("delaymin", 0.45);
  em("delaymax", 0.45);
  em("nrofparticles", 2);
  em("maxparticles", 3);
  part("lifetime"); a.num(0.95).op(Asm::ASSIGN);
  part("image"); a.str("puff.png").op(Asm::ASSIGN);
  part("angle"); a.num(3.14159265358979 / 2).op(Asm::ASSIGN);
  part("speed"); a.num(10).op(Asm::ASSIGN);
  part("spin"); a.num(1).op(Asm::ASSIGN);
  a.var("emitter").op(Asm::TOOBJECT).var("emissionoffset").op(Asm::MEMBER).op(Asm::MARKER).num(1).num(2).num(0).op(37)
      .op(Asm::ASSIGN);
  // emitter.addlocalmodifier("once", 0, 0, "rotation", "replace", 1, 1);
  a.op(Asm::MARKER).num(1).num(1).str("replace").str("rotation").num(0).num(0).str("once").var("emitter")
      .op(Asm::TOOBJECT).var("addlocalmodifier").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  // emitter.addglobalmodifier("impulse", 0.2, 0.2, "spin", "multiply", 0.5, 0.5);
  a.op(Asm::MARKER).num(0.5).num(0.5).str("multiply").str("spin").num(0.2).num(0.2).str("impulse").var("emitter")
      .op(Asm::TOOBJECT).var("addglobalmodifier").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  // ok = emitter.addlocalmodifier("sometimes", ...): refused
  a.var("ok").op(Asm::MARKER).num(1).num(1).str("add").str("x").num(0).num(0).str("sometimes").var("emitter")
      .op(Asm::TOOBJECT).var("addlocalmodifier").op(Asm::MEMBER).op(Asm::CALL).op(Asm::ASSIGN);
  endNew(a, img);
  endNew(a, root);
  a.num(0).op(Asm::RET);
  auto script = m.newVar("StartScript_Smoke");
  CHECK(m.setScript(script, a.bytes()));
  m.runScripts();
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(m.errors().empty());
  CHECK(s.find("Smoke") && s.find("Smoke")->child("ok") && s.find("Smoke")->child("ok")->number() == 0);
  auto c = s.find("Smoke");
  CHECK(c && c->emitter);
  if (!c || !c->emitter) return;
  auto& e = *c->emitter;
  s.setSize(640, 480);
  s.setContent(s.find("Root"));

  // The first tick only starts the timer; the burst comes one delay later.
  s.advance(0.1);
  CHECK(e.particles().empty());
  for (int i = 0; i < 4; ++i) s.advance(0.1);
  CHECK(e.particles().empty());  // 0.5 s: the burst is due at 0.55
  s.advance(0.1);
  CHECK(e.particles().size() == 2);
  // Born at the control (100, 100) + offset (10, 20) + emissionoffset (1, 2),
  // then moved up for one step of 0.1 s at 10 pixels a second.
  const Particle& p = e.particles()[0];
  CHECK(std::fabs(p.f[FX] - 111) < 1e-6);
  CHECK(std::fabs(p.f[FY] - (122 - 1)) < 1e-6);
  // The local `once` at age 0 set the rotation to 1; spin then turned it.
  CHECK(std::fabs(p.f[FRotation] - (1 + 0.1 * p.f[FSpin])) < 1e-6 || std::fabs(p.f[FRotation] - 1.1) < 1e-6);
  // The global impulse halves spin every 0.2 s for every live particle.
  s.advance(0.1);
  s.advance(0.1);
  CHECK(e.particles()[0].f[FSpin] < 1);
  // The next burst (due at 1.05 s) adds only one: maxparticles is 3.
  for (int i = 0; i < 3; ++i) s.advance(0.1);
  CHECK(e.particles().size() == 3);
  // The first two die at their lifetime of 0.95 s (by 1.5 s).
  for (int i = 0; i < 3; ++i) s.advance(0.1);
  CHECK(e.particles().size() == 3);
  s.advance(0.1);
  CHECK(e.particles().size() == 1);
  CHECK(e.child("currentparticlecount") && e.child("currentparticlecount")->number() == 1);

  // Drawn after the engine's part, through the painter's sprite.
  struct Sprites : Recorder {
    int n = 0;
    std::string file;
    void sprite(const std::string& f, double, double, double, double, double, const double*, int) override {
      ++n;
      file = f;
    }
  } sp;
  drawScreen(s, sp);
  CHECK(sp.n == 1 && sp.file == "puff.png");
  // removemodifiers clears them.
  e.removeModifiers();
  CHECK(!e.addModifier(Emitter::List::Local, "once", 0, 0, "nofield", "add", 0, 0));
  CHECK(e.addModifier(Emitter::List::Local, "range", 0, 1, "alpha", "replace", 1, 0));
}

// A show-image's `actor`: what the 4.04r2 main menu sets inside
// with (StartAni1) lands on the control's actor object.
static void testShowImgActor() {
  gs2::Machine m;
  Screen s(m);
  s.install();
  Asm a;
  a.function("onCreated", {});
  auto img = beginNew(a, "GuiShowImgCtrl", "Walker");
  a.var("actor").op(Asm::TOOBJECT).var("head").op(Asm::MEMBER).str("khead0.png").op(Asm::ASSIGN);
  a.var("actor").op(Asm::TOOBJECT).var("attr").op(Asm::MEMBER).op(Asm::TOOBJECT).num(5).str("klegs13.png")
      .op(132);  // arrayset
  endNew(a, img);
  a.num(0).op(Asm::RET);
  auto script = m.newVar("StartScript_Walker");
  CHECK(m.setScript(script, a.bytes()));
  m.runScripts();
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  auto c = s.find("Walker");
  CHECK(c && c->actor);
  if (!c || !c->actor) return;
  CHECK(c->actor->child("head") && c->actor->child("head")->string() == "khead0.png");
  auto attr = c->actor->child("attr");
  CHECK(attr && attr->elements().size() == 31 && attr->elements()[5]->string() == "klegs13.png");
  // Nothing landed on a global of the same name.
  CHECK(!m.universe()->child("head"));
}

int main() {
  testEmitter();
  testShowImgActor();
  testObjectsAndCommands();
  testScriptCommands();
  testDrawing();
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("gui tests passed\n");
  return 0;
}
