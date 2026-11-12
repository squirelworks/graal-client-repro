// graal304-torque: the 3.04 client on the rebuilt Torque engine, in a
// window. It boots the install's own main.cs, draws the install's own
// menus, routes keys through its ActionMaps and clicks to its controls,
// and hosts the 2D game as GuiGraalCtrl.
//
//   graal304-torque [--root INSTALL] [--prefs DIR] [--game LIB]
//                   [--steps FILE] [--seconds N] [--trace FILE] [--shot FRAME.bmp]
//
// --root defaults to the program's folder (put it in a 3.04 install, beside
// graalexe), then the current folder, whichever holds main.cs; --prefs to ~/.graal304-torque; --game to libGame304Lib.so next
// to the program. --steps runs scripted statements as tq-play does (for lab
// runs); --seconds ends the program after N seconds; --shot writes the last
// window image when the program ends.

#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include <sys/stat.h>
#include <unistd.h>

#include "../pascal_game304.hpp"
#include "boot304.hpp"
#include "frame304.hpp"
#include "window.hpp"

using namespace Torque;

namespace {

std::string program_dir(const char* argv0) {
  char buf[4096];
  const ssize_t n = readlink("/proc/self/exe", buf, sizeof buf - 1);
  std::string path = n > 0 ? std::string(buf, std::size_t(n)) : std::string(argv0);
  const std::size_t slash = path.find_last_of('/');
  return slash == std::string::npos ? std::string(".") : path.substr(0, slash);
}

void usage() {
  std::cerr << "usage: graal304-torque [--root INSTALL] [--prefs DIR] [--game LIB] [--steps FILE]\n"
               "                       [--seconds N] [--trace FILE] [--shot FRAME.bmp]\n";
}

} // namespace

int main(int argc, char** argv) {
  const std::string here = program_dir(argv[0]);
  unsigned seconds = 0;
  std::string root, prefs, lib = here + "/libGame304Lib.so", steps_path, trace_path, shot;
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
    else if (a == "--trace") trace_path = next();
    else if (a == "--shot") shot = next();
    else { usage(); return 2; }
  }
  auto has_main = [](const std::string& dir) { return std::ifstream(dir + "/main.cs").good(); };
  if (root.empty()) root = has_main(here) || !has_main(".") ? here : std::string(".");
  if (!has_main(root)) {
    std::cerr << "graal304-torque: no main.cs in " << root << ".\n"
              << "Copy graal304-torque and libGame304Lib.so into your Graal 3.04 folder (beside graalexe),\n"
              << "run it from that folder, or pass --root with that folder.\n";
    return 1;
  }
  if (prefs.empty()) {
    const char* home = std::getenv("HOME");
    prefs = std::string(home ? home : ".") + "/.graal304-torque";
  }
  mkdir(prefs.c_str(), 0755);
  std::vector<Step> steps;
  if (!steps_path.empty() && !read_steps(steps_path, steps)) {
    std::cerr << "graal304-torque: cannot read " << steps_path << "\n";
    return 2;
  }

  Engine engine;
  setup_engine_304(engine, root, prefs, [](const std::string& text) { std::cout << text << "\n" << std::flush; });
  std::string error;
  auto game = load_pascal_game304(lib, root, error);
  if (!game) {
    std::cerr << "graal304-torque: " << error << "\n";
    return 1;
  }
  GuiGraal304 graal(engine, std::move(game));
  boot_304(engine);

  int width = 800, height = 600;
  canvas_size_304(engine, width, height);
  auto window = Window::open("Graal 3.04 (Torque rebuild)", width, height, error);
  if (!window) {
    std::cerr << "graal304-torque: " << error << "\n";
    return 1;
  }
  Frame304 frame(engine, graal, width, height);

  std::size_t next_step = 0;
  bool running = true;
  for (unsigned t = 0; running && !engine.quit_requested && (!seconds || t < seconds * 1000); t += 50) {
    const auto start = std::chrono::steady_clock::now();
    for (const WindowEvent& ev : window->pump())
      if (!frame.handle(ev)) running = false;
    while (next_step < steps.size() && steps[next_step].at <= t) {
      engine.trace.push_back("step " + std::to_string(t) + ": " + steps[next_step].code);
      engine.evaluate(steps[next_step].code);
      ++next_step;
    }
    frame.step();
    window->present(frame.image());
    std::this_thread::sleep_until(start + std::chrono::milliseconds(50));
  }
  engine.call_function("onExit", {});

  if (!shot.empty()) {
    const Gui::Image& img = frame.image();
    std::vector<std::uint32_t> px(img.pixels.size());
    for (std::size_t i = 0; i < px.size(); ++i) {
      const Gui::Color& c = img.pixels[i];
      px[i] = 0xFF000000u | (std::uint32_t(c.r) << 16) | (std::uint32_t(c.g) << 8) | c.b;
    }
    write_bmp(shot, px.data(), img.width, img.height);
  }
  if (!trace_path.empty()) {
    std::ofstream out(trace_path, std::ios::binary);
    for (const auto& line : engine.trace) out << line << "\n";
    for (const auto& line : frame.log) out << line << "\n";
  }
  return 0;
}
