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
#include "../guigraal304.hpp"
#include "boot304.hpp"
#include "../pascal_game304.hpp"

using namespace Torque;

namespace {

void usage() {
  std::cerr << "usage: tq-play --root INSTALL --prefs DIR --game LIB [--steps FILE] [--seconds N]\n"
               "               [--log FILE] [--trace FILE] [--shot FRAME.bmp] [--no-draw] [--fast]\n";
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
  std::ostringstream console;
  setup_engine_304(engine, root, prefs, [&](const std::string& text) {
    console << text << "\n";
    std::cout << text << "\n" << std::flush;
  });

  std::string error;
  auto game = load_pascal_game304(lib, root, error);
  if (!game) {
    std::cerr << "tq-play: " << error << "\n";
    return 1;
  }
  GuiGraal304 graal(engine, std::move(game));

  boot_304(engine);

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
