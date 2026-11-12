// tq-play: boot a 3.04 install on the console engine with GuiGraalCtrl
// hosting the rebuilt 2D game, then drive it through the install's own
// scripts, the way a player's clicks and keys would.
//
//   tq-play --root INSTALL --prefs DIR --game LIB [--steps FILE] [--seconds N]
//           [--log FILE] [--trace FILE] [--shot FRAME.bmp] [--no-draw] [--fast]
//
// A steps file has one line per step: a time in ms from the start, then a
// TorqueScript statement run at that time, e.g.
//   0     NickEdit.setText("lab"); AccountEdit.setText("lab"); PassEdit.setText("pw");
//   0     switchToServerList();
//   2000  Adventure.selectServerCategory(2); ServerList.setSelectedRow(0);
//   2100  Adventure.connectToSelectedServer();
//   5000  moveRight(1);
//   5500  moveRight(0);
// Lines starting with # are comments. The clock is the engine's: 50 ms a
// frame, each frame advances schedules and ticks the game, paced to the wall
// clock (the game's network and timers run on it) unless --fast. With
// --seconds 0 the run ends after the last step.
//
// Video functions are host stubs (written to the trace); canvas dialogs and
// focus are the engine's (input304.cpp).

#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>
#include <chrono>
#include <vector>

#include "../../console/engine/engine.hpp"
#include "../../console/compiler/compile.hpp"
#include "../guigraal304.hpp"
#include "../pascal_game304.hpp"

using namespace Torque;

namespace {

void usage() {
  std::cerr << "usage: tq-play --root INSTALL --prefs DIR --game LIB [--steps FILE] [--seconds N]\n"
               "               [--log FILE] [--trace FILE] [--shot FRAME.bmp] [--no-draw] [--fast]\n";
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
    start_input_304(en);
    return std::string("1");
  });
  for (const char* name : {"videoSetGammaCorrection", "setOpenGLTextureCompressionHint", "setOpenGLAnisotropy",
                           "setOpenGLMipReduction", "setOpenGLInteriorMipReduction", "setOpenGLSkyMipReduction",
                           "setScreenMode", "setDisplayDevice", "toggleFullScreen",
                           "lockMouse", "gotoWebPage", "cursorOff", "cursorOn"})
    stub(e, "", name, 1, 0);
  stub(e, "", "isDeviceFullScreenOnly", 2, 2, "0");
  for (const char* name : {"repaint", "setCursor", "cursorOn", "cursorOff"})
    stub(e, "GuiCanvas", name, 2, 0);
  stub(e, "GuiCanvas", "isCursorOn", 2, 2, "0");
}

struct Step {
  unsigned at = 0;
  std::string code;
};

bool read_steps(const std::string& path, std::vector<Step>& out) {
  std::ifstream in(path);
  if (!in) return false;
  std::string line;
  while (std::getline(in, line)) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    std::size_t p = line.find_first_not_of(" \t");
    if (p == std::string::npos || line[p] == '#') continue;
    std::size_t q = line.find_first_of(" \t", p);
    Step s;
    s.at = static_cast<unsigned>(std::stoul(line.substr(p, q - p)));
    if (q != std::string::npos) s.code = line.substr(line.find_first_not_of(" \t", q));
    out.push_back(s);
  }
  return true;
}

void put32(std::ofstream& f, std::uint32_t v) {
  const char b[4] = {char(v), char(v >> 8), char(v >> 16), char(v >> 24)};
  f.write(b, 4);
}

bool write_bmp(const std::string& path, const std::uint32_t* px, int w, int h) {
  std::ofstream f(path, std::ios::binary);
  if (!f || !px || w <= 0 || h <= 0) return false;
  const std::uint32_t row = static_cast<std::uint32_t>(w) * 3, pad = (4 - row % 4) % 4;
  const std::uint32_t size = (row + pad) * static_cast<std::uint32_t>(h);
  f.write("BM", 2); put32(f, 54 + size); put32(f, 0); put32(f, 54);
  put32(f, 40); put32(f, static_cast<std::uint32_t>(w)); put32(f, static_cast<std::uint32_t>(h));
  const char planes[4] = {1, 0, 24, 0};
  f.write(planes, 4);
  put32(f, 0); put32(f, size); put32(f, 2835); put32(f, 2835); put32(f, 0); put32(f, 0);
  for (int y = h - 1; y >= 0; --y) {
    for (int x = 0; x < w; ++x) {
      const std::uint32_t c = px[y * w + x];
      const char bgr[3] = {char(c), char(c >> 8), char(c >> 16)};
      f.write(bgr, 3);
    }
    f.write("\0\0\0", pad);
  }
  return static_cast<bool>(f);
}

} // namespace

int main(int argc, char** argv) {
  std::string root, prefs, lib, steps_path, log_path, trace_path, shot;
  unsigned seconds = 0;
  bool draw = true, realtime = true;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) { usage(); std::exit(2); }
      return argv[++i];
    };
    if (a == "--root") root = next();
    else if (a == "--prefs") prefs = next();
    else if (a == "--game") lib = next();
    else if (a == "--steps") steps_path = next();
    else if (a == "--seconds") seconds = static_cast<unsigned>(std::stoul(next()));
    else if (a == "--log") log_path = next();
    else if (a == "--trace") trace_path = next();
    else if (a == "--shot") shot = next();
    else if (a == "--no-draw") draw = false;
    else if (a == "--fast") realtime = false;
    else { usage(); return 2; }
  }
  if (root.empty() || prefs.empty() || lib.empty()) { usage(); return 2; }
  std::vector<Step> steps;
  if (!steps_path.empty() && !read_steps(steps_path, steps)) {
    std::cerr << "tq-play: cannot read " << steps_path << "\n";
    return 2;
  }

  Engine engine;
  engine.files.root = root;
  engine.files.prefs_dir = prefs;
  std::ostringstream console;
  engine.print = [&](const std::string& text) {
    console << text << "\n";
    std::cout << text << "\n" << std::flush;
    engine.add_console_text(text);
  };
  register_classes_304(engine);
  register_input_304(engine);
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

  std::string error;
  auto game = load_pascal_game304(lib, root, error);
  if (!game) {
    std::cerr << "tq-play: " << error << "\n";
    return 1;
  }
  GuiGraal304 graal(engine, std::move(game));

  engine.set_global("$Game::argc", Value::of_int(1));
  engine.set_global("$Game::argv0", Value::of_string("graalexe"));
  engine.call_function("exec", {"main.cs"});

  unsigned end_ms = seconds * 1000;
  for (const Step& s : steps) if (seconds == 0 && s.at + 50 > end_ms) end_ms = s.at + 50;
  std::size_t next_step = 0;
  for (unsigned t = 0; t <= end_ms && !engine.quit_requested; t += 50) {
    const auto frame_start = std::chrono::steady_clock::now();
    while (next_step < steps.size() && steps[next_step].at <= t) {
      engine.trace.push_back("step " + std::to_string(t) + ": " + steps[next_step].code);
      engine.evaluate(steps[next_step].code);
      ++next_step;
    }
    engine.advance(50);
    graal.tick(draw);
    if (realtime) std::this_thread::sleep_until(frame_start + std::chrono::milliseconds(50));
  }
  engine.trace.push_back("player " + graal.game().player() + ", state " + std::to_string(graal.game().state()));

  int code = 0;
  if (!shot.empty()) {
    int w = 0, h = 0;
    const std::uint32_t* px = graal.game().frame(w, h);
    if (!write_bmp(shot, px, w, h)) {
      std::cerr << "tq-play: no frame for " << shot << "\n";
      code = 1;
    }
  }
  engine.call_function("onExit", {});
  if (!log_path.empty()) {
    std::ofstream out(log_path, std::ios::binary);
    out << console.str();
  }
  if (!trace_path.empty()) {
    std::ofstream out(trace_path, std::ios::binary);
    for (const auto& line : engine.trace) out << line << "\n";
  }
  return code;
}
