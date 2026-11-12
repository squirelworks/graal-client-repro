// tq-shot: boot a 3.04 install on the console engine, then draw the canvas
// content (and any dialogs named with --dialog) with the stock control
// renderer and write a PNG. A lab tool: nothing it reads is in the repo.
//
//   tq-shot --root INSTALL --prefs DIR --out FILE.png
//           [--size W H] [--dialog NAME]... [--notes FILE]
//
// It boots like console/engine/host/tq_boot.cpp: the install's own root
// main.cs runs through the TorqueScript compiler, and the host functions
// the scripts call before video exists are stubs. The canvas size
// defaults to the first two words of $pref::Video::resolution, else
// 800 x 600.

#include "../../console/engine/engine.hpp"
#include "../../console/compiler/compile.hpp"
#include "../render.hpp"

#include <cstdlib>
#include <iostream>
#include <sstream>

using namespace Torque;

namespace {

void usage() {
  std::cerr << "usage: tq-shot --root INSTALL --prefs DIR --out FILE.png [--size W H]"
               " [--dialog NAME]... [--notes FILE]\n";
}

void quiet(Engine& e, const char* space, const char* name, std::string result = std::string()) {
  e.add_function(space, name, 1, 0, std::string(name) + "(...)",
                 [result](Engine&, SimObject*, Args&) { return result; });
}

}  // namespace

int main(int argc, char** argv) {
  std::string root, prefs, out, notes_path;
  int width = 0, height = 0;
  std::vector<std::string> dialogs;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) { usage(); std::exit(2); }
      return argv[++i];
    };
    if (a == "--root") root = next();
    else if (a == "--prefs") prefs = next();
    else if (a == "--out") out = next();
    else if (a == "--notes") notes_path = next();
    else if (a == "--dialog") dialogs.push_back(next());
    else if (a == "--size") { width = std::stoi(next()); height = std::stoi(next()); }
    else { usage(); return 2; }
  }
  if (root.empty() || prefs.empty() || out.empty()) { usage(); return 2; }

  Engine engine;
  engine.files.root = root;
  engine.files.prefs_dir = prefs;
  engine.print = [](const std::string&) {};
  register_classes_304(engine);
  register_engine_prefs_304(engine);
  engine.compiler = [](const std::string& source, const std::string&, DsoBlock& out, std::string& error) {
    CompileError e;
    if (compile_script(source, out, e)) return true;
    error = "line " + std::to_string(e.line) + ": " + e.message;
    return false;
  };
  engine.add_function("", "createCanvas", 2, 2, "createCanvas(windowTitle)", [](Engine& en, SimObject*, Args&) {
    if (!en.find_object("Canvas")) en.create_object("GuiCanvas", "Canvas");
    return std::string("1");
  });
  for (const char* name : {"videoSetGammaCorrection", "setOpenGLTextureCompressionHint", "setOpenGLAnisotropy",
                           "setOpenGLMipReduction", "setOpenGLInteriorMipReduction", "setOpenGLSkyMipReduction",
                           "setScreenMode", "setDisplayDevice", "toggleFullScreen", "deactivateKeyboard",
                           "lockMouse", "gotoWebPage", "cursorOff", "cursorOn"})
    quiet(engine, "", name);
  quiet(engine, "", "isDeviceFullScreenOnly", "0");
  for (const char* name : {"pushDialog", "popDialog", "repaint", "setCursor", "cursorOn", "cursorOff"})
    quiet(engine, "GuiCanvas", name);
  quiet(engine, "GuiCanvas", "isCursorOn", "0");
  engine.set_global("$Game::argc", Value::of_int(1));
  engine.set_global("$Game::argv0", Value::of_string("graalexe"));
  engine.call_function("exec", {"main.cs"});

  if (!width || !height) {
    std::istringstream res(engine.global("$pref::Video::resolution").str());
    if (!(res >> width >> height) || width <= 0 || height <= 0 || width > 4096 || height > 4096) {
      width = 800;
      height = 600;
    }
  }
  SimObject* canvas = engine.find_object("Canvas");
  SimObject* content = canvas ? engine.find_object(canvas->field("content")) : nullptr;
  if (!content) {
    std::cerr << "tq-shot: the scripts set no canvas content\n";
    return 1;
  }
  std::vector<SimObject*> on_top;
  for (const auto& name : dialogs) {
    SimObject* d = engine.find_object(name);
    if (!d) { std::cerr << "tq-shot: no control named " << name << "\n"; return 1; }
    on_top.push_back(d);
  }

  Gui::Canvas surface(width, height);
  Gui::Renderer renderer(engine);
  renderer.render(surface, content, on_top);
  std::string error;
  if (!Gui::write_file(out, Gui::encode_png(surface.surface()), error)) {
    std::cerr << "tq-shot: " << error << "\n";
    return 1;
  }
  for (const auto& n : renderer.notes) std::cerr << "note: " << n << "\n";
  if (!notes_path.empty()) {
    std::string text;
    for (const auto& n : renderer.notes) text += n + "\n";
    if (!Gui::write_file(notes_path, std::vector<std::uint8_t>(text.begin(), text.end()), error)) {
      std::cerr << "tq-shot: " << error << "\n";
      return 1;
    }
  }
  return 0;
}
