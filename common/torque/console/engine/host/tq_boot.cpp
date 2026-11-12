// tq-boot: run a 3.04 install's compiled boot scripts on the console engine
// and write what the original writes: console.log lines, the exported prefs
// and the saved key map.
//
//   tq-boot --root INSTALL --prefs DIR [--log FILE] [--trace FILE]
//           [--advance MS] [--exit]
//
// Plain scripts (the root main.cs, the prefs.cs and config.cs the game
// writes) go through the TorqueScript compiler in ../../compiler.
//
// Video, canvas and GUI methods that need later stages are host stubs: they
// keep the boot going and are written to the trace, never to console.log.

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

#include "../engine.hpp"
#include "../../compiler/compile.hpp"

using namespace Torque;

namespace {

void usage() {
  std::cerr << "usage: tq-boot --root INSTALL --prefs DIR [--log FILE] [--trace FILE]"
               " [--advance MS] [--exit]\n";
}

void stub(Engine& e, const char* space, const char* name, std::size_t min, std::size_t max,
          std::string result = std::string()) {
  e.add_function(space, name, min, max, std::string(name) + "(...)",
                 [space = std::string(space), name = std::string(name), result](Engine& en, SimObject*, Args& a) {
                   std::string line = "host stub " + (space.empty() ? std::string() : space + "::") + name + "(";
                   for (std::size_t i = 1; i < a.size(); ++i) line += (i > 1 ? ", " : "") + a[i];
                   en.trace.push_back(line + ")");
                   return result;
                 });
}

void register_host_stubs(Engine& e) {
  e.add_function("", "createCanvas", 2, 2, "createCanvas(windowTitle)", [](Engine& en, SimObject*, Args& a) {
    en.trace.push_back("host stub createCanvas(" + a[1] + ")");
    if (!en.find_object("Canvas")) en.create_object("GuiCanvas", "Canvas");
    return std::string("1");
  });
  for (const char* name : {"videoSetGammaCorrection", "setOpenGLTextureCompressionHint", "setOpenGLAnisotropy",
                           "setOpenGLMipReduction", "setOpenGLInteriorMipReduction", "setOpenGLSkyMipReduction",
                           "setScreenMode", "setDisplayDevice", "toggleFullScreen", "deactivateKeyboard",
                           "lockMouse", "gotoWebPage", "cursorOff", "cursorOn"})
    stub(e, "", name, 1, 0);
  stub(e, "", "isDeviceFullScreenOnly", 2, 2, "0");
  for (const char* name : {"pushDialog", "popDialog", "repaint", "setCursor", "cursorOn", "cursorOff"})
    stub(e, "GuiCanvas", name, 2, 0);
  stub(e, "GuiCanvas", "isCursorOn", 2, 2, "0");
}

} // namespace

int main(int argc, char** argv) {
  std::string root, prefs, log_path, trace_path;
  unsigned advance = 0;
  bool do_exit = false;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) { usage(); std::exit(2); }
      return argv[++i];
    };
    if (a == "--root") root = next();
    else if (a == "--prefs") prefs = next();
    else if (a == "--log") log_path = next();
    else if (a == "--trace") trace_path = next();
    else if (a == "--advance") advance = static_cast<unsigned>(std::stoul(next()));
    else if (a == "--exit") do_exit = true;
    else { usage(); return 2; }
  }
  if (root.empty() || prefs.empty()) { usage(); return 2; }

  Engine engine;
  engine.files.root = root;
  engine.files.prefs_dir = prefs;
  std::ostringstream console;
  engine.print = [&](const std::string& text) {
    console << text << "\n";
    std::cout << text << "\n";
  };
  register_classes_304(engine);
  register_engine_prefs_304(engine);
  register_text_list_304(engine);
  engine.compiler = [](const std::string& source, const std::string&, DsoBlock& out, std::string& error) {
    CompileError e;
    if (compile_script(source, out, e)) return true;
    error = "line " + std::to_string(e.line) + ": " + e.message;
    return false;
  };
  register_host_stubs(engine);
  engine.on_set_content = [&](SimObject*, SimObject* content) {
    engine.trace.push_back("canvas content " + (content->name.empty() ? std::to_string(content->id) : content->name));
  };
  engine.set_global("$Game::argc", Value::of_int(1));
  engine.set_global("$Game::argv0", Value::of_string("graalexe"));

  // Boot the way the original does: run the install's own root main.cs.
  engine.call_function("exec", {"main.cs"});
  if (advance) engine.advance(advance);
  if (do_exit || engine.quit_requested) engine.call_function("onExit", {});

  if (!log_path.empty()) {
    std::ofstream out(log_path, std::ios::binary);
    out << console.str();
  }
  if (!trace_path.empty()) {
    std::ofstream out(trace_path, std::ios::binary);
    for (const auto& line : engine.trace) out << line << "\n";
  }
  return 0;
}
