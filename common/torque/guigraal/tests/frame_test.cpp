// The windowed program's frame logic (Frame304) without a window: clicks,
// keys and the game drawn into GuiGraalCtrl. The control tree is written
// for the test; no original script, DSO, font or image is used.

#include <iostream>
#include <string>

#include "../../console/compiler/compile.hpp"
#include "../host/frame304.hpp"

using namespace Torque;

namespace {

int failures = 0;

void check(bool ok, const std::string& what) {
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << what << "\n";
  }
}

struct TinyGame : Game304 {
  std::string keys;
  std::uint32_t px[4] = {0xFF102030u, 0xFF405060u, 0xFF708090u, 0xFFA0B0C0u};
  std::string error() override { return {}; }
  void set_nickname(const std::string&) override {}
  bool list_open(const std::string&, const std::string&) override { return true; }
  int list_poll() override { return list_waiting; }
  std::string list_status() override { return {}; }
  int list_count() override { return 0; }
  ListServerEntry list_entry(int) override { return {}; }
  bool connect(const std::string&, int, const std::string&, const std::string&) override { return true; }
  bool offline(const std::string&, double, double) override { return true; }
  std::string offline_path() override { return "level.nw"; }
  void key(int dir, bool down) override { keys += std::to_string(dir) + (down ? "+" : "-"); }
  void say(const std::string&) override {}
  void to_all(const std::string&) override {}
  bool tick(bool) override { return true; }
  int state() override { return playing_offline; }
  const std::uint32_t* frame(int& w, int& h) override { w = 2; h = 2; return px; }
  std::string player() override { return "level.nw 30 30 2"; }
};

const char* kTree = R"(
new GuiCanvas(Canvas) {};
new GuiControl(MainMenuGui) {
  position = "0 0"; extent = "800 600";
  new GuiButtonCtrl(GoButton) { position = "10 10"; extent = "100 20"; command = "$cmd = 1;"; };
  new GuiButtonCtrl(OffButton) { position = "10 40"; extent = "100 20"; command = "$off = 1;"; active = "0"; };
  new GuiTextEditCtrl(NameEdit) { position = "10 70"; extent = "200 20"; };
  new GuiTextListCtrl(List) { position = "300 10"; extent = "200 8"; altCommand = "$alt = List.getSelectedId();"; };
};
new GuiControl(AdventureGui) {
  position = "0 0"; extent = "640 480";
  new GuiGraalCtrl(Adventure) {
    horizSizing = "relative"; vertSizing = "relative"; position = "0 0"; extent = "640 480";
  };
};
function GoButton::onAction(%this) { $action = 1; }
function List::onSelect(%this, %id, %text) { $sel = %id; }
function moveRight(%val) { Adventure.moveRight(%val); }
new ActionMap(moveMap);
moveMap.bind(keyboard, right, moveRight);
moveMap.push();
List.addRow(7, "seven"); List.addRow(8, "eight"); List.addRow(9, "nine");
Canvas.setContent(MainMenuGui);
)";

WindowEvent click(int x, int y, bool dbl = false) {
  WindowEvent e;
  e.kind = WindowEvent::Kind::click;
  e.x = x;
  e.y = y;
  e.double_click = dbl;
  return e;
}

} // namespace

int main() {
  Engine engine;
  engine.print = [](const std::string&) {};
  register_builtins(engine);
  register_classes_304(engine);
  register_input_304(engine);
  register_text_list_304(engine);
  engine.compiler = [](const std::string& source, const std::string&, DsoBlock& out, std::string& error) {
    CompileError e;
    if (compile_script(source, out, e)) return true;
    error = e.message;
    return false;
  };
  auto owned = std::make_unique<TinyGame>();
  TinyGame* game = owned.get();
  GuiGraal304 graal(engine, std::move(owned));
  // The canvas size from $pref::Video::resolution: numbers are kept, a
  // depth that is not a number ("800 600 Default", 3.153) gives 640 x 480.
  const auto size_for = [&](const std::string& pref) {
    engine.set_global("$pref::Video::resolution", Value::of_string(pref));
    int w = 0, h = 0;
    canvas_size_304(engine, w, h);
    return std::to_string(w) + "x" + std::to_string(h);
  };
  check(size_for("1024 768 32") == "1024x768", "resolution with a bit depth");
  check(size_for("800 600 Default") == "640x480", "resolution with a named depth");
  check(size_for("") == "800x600", "no resolution");
  check(size_for("10 10 16") == "800x600", "too small a resolution");
  engine.set_global("$pref::Video::resolution", Value::of_string(std::string()));
  check(engine.evaluate(kTree), "the test tree runs");
  Frame304 frame(engine, graal, 800, 600);
  frame.draw();

  frame.handle(click(50, 20));
  check(engine.global("$cmd").str() == "1", "a button click runs its command");
  check(engine.global("$action").str() == "1", "and its onAction");
  frame.handle(click(50, 50));
  check(engine.global("$off").str().empty(), "an inactive button does nothing");
  frame.handle(click(50, 80));
  check(engine.first_responder == engine.find_object("NameEdit")->id, "a text edit click gives it focus");
  WindowEvent k;
  k.key.key = "h";
  k.key.ascii = 'h';
  frame.handle(k);
  std::string got;
  engine.evaluate("return NameEdit.getValue();", &got);
  check(got == "h", "typing goes to the focused edit");
  const int rh = frame.renderer().row_height(engine.find_object("List"));
  frame.handle(click(310, 10 + rh + 1));
  check(engine.global("$sel").str() == "8", "a click on the second row selects it");
  frame.handle(click(310, 10 + 2 * rh + 1, true));
  check(engine.global("$alt").str() == "9", "a double click runs altCommand");
  check(frame.renderer().hit(790, 590) == engine.find_object("MainMenuGui")->id, "hit test finds the content");

  engine.evaluate("Adventure.startOfflineMode();");
  check(graal.playing(), "offline play started");
  frame.handle(click(400, 300));
  check(engine.first_responder == 0, "a click on the game takes focus from the edits");
  WindowEvent right;
  right.key.key = "right";
  frame.handle(right);
  right.key.make = false;
  frame.handle(right);
  check(game->keys == "3+3-", "the right key reaches the game through moveMap");
  frame.step();
  const Gui::Image& img = frame.image();
  auto rgb = [&](int x, int y) {
    const Gui::Color c = img.at(x, y);
    return (std::uint32_t(c.r) << 16) | (std::uint32_t(c.g) << 8) | c.b;
  };
  check(rgb(0, 0) == 0x102030u, "the game frame fills the control (top left)");
  check(rgb(799, 599) == 0xA0B0C0u, "the game frame fills the control (bottom right)");
  check(rgb(500, 100) == 0x405060u, "the game frame is scaled to the control");

  WindowEvent close;
  close.kind = WindowEvent::Kind::close;
  check(!frame.handle(close), "a close request ends the loop");

  if (failures) {
    std::cerr << failures << " failure(s)\n";
    return 1;
  }
  std::cout << "frame-test: all passed\n";
  return 0;
}
