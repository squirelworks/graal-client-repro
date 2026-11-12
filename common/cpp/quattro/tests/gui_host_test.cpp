// The GS2 GUI on the Quattro program: a hand-assembled menu made
// MainMenuGui2D, drawn on the canvas with the world in its playfield, and
// a mouse press from the window reaching the button's onAction.
#include "../../gs2/tests/assembler.hpp"
#include "../draw/ui_font.hpp"
#include "../shell/program.hpp"
#include "check.hpp"

#include <algorithm>
#include <filesystem>

using namespace Quattro;
using gs2asm::Asm;

namespace {

std::size_t begin_new(Asm& a, const std::string& type, const std::string& name) {
  a.str(name).op(40).op(Asm::COPY).op(Asm::COPY).op(Asm::COPY);
  a.str(type).op(Asm::TOSTRING).op(42).op(Asm::ASSIGN).op(Asm::TOOBJECT).op(Asm::WITH);
  return a.jumpOperand();
}

void end_new(Asm& a, std::size_t end) {
  a.op(Asm::ENDWITH);
  a.patch(end, a.here());
  a.op(Asm::MARKER).op(Asm::SWAP).callName("addcontrol").op(Asm::POP);
}

void prop(Asm& a, const std::string& k, const std::string& v) { a.var(k).str(v).op(Asm::ASSIGN); }

Asm menu() {
  Asm a;
  a.function("onCreated", {});
  auto p = begin_new(a, "GuiControlProfile", "GuiDefaultProfile");
  prop(a, "fontColor", "255 255 0");
  prop(a, "fillColor", "0 0 128");
  prop(a, "opaque", "1");
  end_new(a, p);
  auto root = begin_new(a, "GuiControl", "MainMenuGui2D");
  prop(a, "extent", "320 240");
  auto f = begin_new(a, "GuiGraalCtrl", "Playfield");
  prop(a, "position", "0 0");
  prop(a, "extent", "320 200");
  end_new(a, f);
  auto b = begin_new(a, "GuiButtonCtrl", "GoButton");
  prop(a, "position", "10 205");
  prop(a, "extent", "80 30");
  prop(a, "text", "Go");
  end_new(a, b);
  end_new(a, root);
  a.num(0).op(Asm::RET);
  a.function("GoButton.onAction", {});
  a.var("clicked").num(1).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  return a;
}

double global(gs2::Machine& m, const std::string& n) {
  auto v = m.universe()->child(n);
  return v ? v->number() : -1;
}

void test_font() {
  Torque::Gui::Canvas c(40, 20);
  CHECK(Draw::ui_text_width("Go", false) > 0);
  Draw::ui_draw_text(c, 2, 2, "Go", {255, 255, 255, 255}, false);
  int lit = 0;
  for (const auto& px : c.surface().pixels) lit += px.r == 255;
  CHECK(lit > 10);
  CHECK(Draw::ui_text_width("Go", true) >= Draw::ui_text_width("Go", false));
}

void test_menu() {
  Draw::HeadlessWindow win;
  Shell::Options opt;
  opt.width = 320;
  opt.height = 240;
  Shell::Program prog(*Net::find_profile("6.03r7"), opt, win);
  gs2::Machine& m = prog.scripts().machine();
  auto script = m.newVar("StartScript_Test");
  std::string err;
  CHECK(m.setScript(script, menu().bytes(), &err));

  prog.tick();
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(prog.gui().has_content());
  CHECK(prog.gui().playfield() != nullptr);
  const auto& passes = prog.last_passes();
  CHECK(!passes.empty() && passes.back() == "RenderGUI");
  CHECK(std::find(passes.begin(), passes.end(), "Draw_Tiles") != passes.end());

  // The button below the playfield: its fill and its yellow caption.
  const auto& img = win.last();
  CHECK(img.width == 320 && img.height == 240);
  int yellow = 0;
  for (int y = 205; y < 235; ++y)
    for (int x = 10; x < 90; ++x) {
      const auto& px = img.at(x, y);
      yellow += px.r == 255 && px.g == 255 && px.b == 0;
    }
  CHECK(yellow > 5);

  // A press from the window reaches GoButton.onAction.
  Draw::InputEvent press;
  press.type = Draw::InputEvent::MouseDown;
  press.x = 20;
  press.y = 215;
  win.push_input(press);
  prog.tick();
  CHECK(global(m, "clicked") == 1);
}


// A particle: a 4 x 4 red square doubled in size, added onto black, and
// transparent at half alpha.
void test_sprite() {
  namespace fs = std::filesystem;
  fs::path dir = fs::temp_directory_path() / "quattro-gui-sprite";
  fs::create_directories(dir);
  Torque::Gui::Image red(4, 4, {200, 0, 0, 255});
  std::string err;
  CHECK(Torque::Gui::write_file((dir / "spark.png").string(), Torque::Gui::encode_png(red), err));
  Torque::Gui::Canvas c(32, 32);
  Shell::CanvasPainter p(c, {dir.string()});
  double add[4] = {1, 1, 1, 1};
  p.sprite("spark.png", 16, 16, 0, 2, 2, add, 0);
  CHECK(c.surface().at(16, 16).r == 200 && c.surface().at(12, 16).r == 200 && c.surface().at(19, 16).r == 200);
  CHECK(c.surface().at(11, 16).r == 0 && c.surface().at(20, 16).r == 0);  // 8 wide: 12..19
  p.sprite("spark.png", 16, 16, 0, 2, 2, add, 0);
  CHECK(c.surface().at(16, 16).r == 255);  // added and clamped
  double half[4] = {0, 0, 1, 0.5};
  Torque::Gui::Canvas d(8, 8);
  Shell::CanvasPainter q(d, {dir.string()});
  q.sprite("spark.png", 4, 4, 0, 1, 1, half, 1);
  CHECK(d.surface().at(4, 4).r == 0);  // tinted to no red
  fs::remove_all(dir);
}

}  // namespace

int main() {
  test_font();
  test_menu();
  test_sprite();
  TEST_MAIN_END();
}
