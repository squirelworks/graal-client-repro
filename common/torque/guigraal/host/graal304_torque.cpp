// graal304-torque: the 3.04 (or 3.153) client on the rebuilt Torque engine, in a
// window. It boots the install's own main.cs, draws the install's own
// menus, routes keys through its ActionMaps and clicks to its controls,
// and hosts the 2D game as GuiGraalCtrl.
//
//   graal304-torque [--root INSTALL] [--prefs DIR] [--game LIB]
//                   [--steps FILE] [--seconds N] [--trace FILE] [--shot FRAME.bmp]
//
// --root defaults to the program's folder (put it in a 3.04 or 3.153
// install, beside main.cs), then the current folder, whichever holds
// main.cs; --prefs to ~/.graal304-torque (%APPDATA%\graal304-torque on
// Windows); --game to the game library next to the program:
// libGame304Lib.so on Linux, Game304Lib.dll on Windows, libGame304Lib.dylib
// on macOS (Game3153Lib for a 3.153 install; the one library beside the
// program when there is only one, as in the 3.0beta, 3.01 and 3.151 zips). --steps runs scripted
// statements as tq-play does (for lab runs); --seconds ends the program
// after N seconds; --shot writes the last window image when the program
// ends.

#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#include <sys/stat.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <direct.h>
#include <cstdio>
#include <io.h>
#else
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#endif

#include "../pascal_game304.hpp"
#include "boot304.hpp"
#include "frame304.hpp"
#include "window.hpp"

using namespace Torque;

namespace {

std::string program_dir(const char* argv0) {
  std::string path;
#ifdef _WIN32
  char buf[MAX_PATH * 4];
  const DWORD n = GetModuleFileNameA(nullptr, buf, DWORD(sizeof buf));
  if (n > 0 && n < sizeof buf) path.assign(buf, n);
#elif defined(__APPLE__)
  char buf[4096];
  std::uint32_t size = sizeof buf;
  if (_NSGetExecutablePath(buf, &size) == 0) path = buf;
#else
  char buf[4096];
  const ssize_t n = readlink("/proc/self/exe", buf, sizeof buf - 1);
  if (n > 0) path.assign(buf, std::size_t(n));
#endif
  if (path.empty()) path = argv0;
  const std::size_t slash = path.find_last_of("/\\");
  return slash == std::string::npos ? std::string(".") : path.substr(0, slash);
}

// The game library's file name for this system: Game304Lib ->
// libGame304Lib.so, Game304Lib.dll (Free Pascal's Windows name) or
// libGame304Lib.dylib.
std::string game_lib_file(const std::string& base) {
#ifdef _WIN32
  return base + ".dll";
#elif defined(__APPLE__)
  return "lib" + base + ".dylib";
#else
  return "lib" + base + ".so";
#endif
}

std::string default_prefs() {
#ifdef _WIN32
  const char* appdata = std::getenv("APPDATA");
  if (appdata && *appdata) return std::string(appdata) + "\\graal304-torque";
#endif
  const char* home = std::getenv("HOME");
  return std::string(home ? home : ".") + "/.graal304-torque";
}

void make_dir(const std::string& dir) {
#ifdef _WIN32
  _mkdir(dir.c_str());
#else
  mkdir(dir.c_str(), 0755);
#endif
}

#ifdef _WIN32
bool g_console_attached = false;

// The program is a GUI program (no console window of its own). Started from
// a console with nowhere else to write, it writes the console lines there.
void attach_console() {
  HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
  if (out && out != INVALID_HANDLE_VALUE && GetFileType(out) != FILE_TYPE_UNKNOWN) return;
  if (!AttachConsole(ATTACH_PARENT_PROCESS)) return;
  g_console_attached = true;
  if (!std::freopen("CONOUT$", "w", stdout)) return;
  std::freopen("CONOUT$", "w", stderr);
  std::cout.clear();
  std::cerr.clear();
}
#endif

// A start-up error: on the console, and in a message box where there may be
// no console to read (a double-clicked exe or app).
// Whether stderr goes nowhere a person or a script reads: a double-clicked
// exe has no console, and an app started from the Finder writes to
// /dev/null. A console, a pipe or a file (tests, CI) gets no box, which
// would wait for a click.
bool no_reader_for_stderr() {
#ifdef _WIN32
  if (g_console_attached) return false;
  HANDLE err = GetStdHandle(STD_ERROR_HANDLE);
  return !err || err == INVALID_HANDLE_VALUE || GetFileType(err) == FILE_TYPE_UNKNOWN;
#else
  struct stat st;
  if (fstat(2, &st) != 0) return true;
  return S_ISCHR(st.st_mode) && !isatty(2);
#endif
}

void fail(const std::string& text) {
  std::cerr << "graal304-torque: " << text << "\n";
  if (no_reader_for_stderr()) show_error("graal304-torque", text);
}

void usage() {
  std::cerr << "usage: graal304-torque [--root INSTALL] [--prefs DIR] [--game LIB] [--steps FILE]\n"
               "                       [--seconds N] [--trace FILE] [--shot FRAME.bmp]\n";
}

} // namespace

int main(int argc, char** argv) {
#ifdef _WIN32
  attach_console();
#endif
  const std::string here = program_dir(argv[0]);
  unsigned seconds = 0;
  std::string root, prefs, lib, steps_path, trace_path, shot;
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
  // In a macOS app bundle (graal304-torque.app/Contents/MacOS) the install
  // is the folder that holds the .app; a double-clicked app starts in /.
  const std::string bundle_suffix = ".app/Contents/MacOS";
  std::string beside = here;
  if (here.size() > bundle_suffix.size() &&
      here.compare(here.size() - bundle_suffix.size(), bundle_suffix.size(), bundle_suffix) == 0) {
    const std::string app = here.substr(0, here.size() - std::string("/Contents/MacOS").size());
    const std::size_t slash = app.find_last_of('/');
    beside = slash == std::string::npos ? std::string(".") : app.substr(0, slash);
  }
  const bool in_bundle = beside != here;
  // A quarantined app opened where it was unzipped runs from a read-only
  // copy (App Translocation), away from the install beside it.
  if (in_bundle && root.empty() && here.find("/AppTranslocation/") != std::string::npos && !has_main(".")) {
    fail("macOS is running graal304-torque.app from a temporary copy, so it cannot see your Graal folder.\n"
         "Quit, then drag graal304-torque.app with the Finder into your Graal 3.04 or 3.153 folder\n"
         "(beside main.cs), or run: xattr -dr com.apple.quarantine graal304-torque.app");
    return 1;
  }
  if (root.empty()) {
    if (has_main(here)) root = here;
    else if (has_main(beside)) root = beside;
    else if (has_main(".")) root = ".";
    else root = beside;
  }
  if (!has_main(root)) {
    fail("no main.cs in " + root + ".\n" +
         std::string(in_bundle ? "Put graal304-torque.app into your Graal 3.04 or 3.153 folder (beside main.cs),\n"
                               : "Copy graal304-torque and the game library into your Graal 3.04 or 3.153 folder "
                                 "(beside main.cs),\n") +
         "run it from that folder, or pass --root with that folder.");
    return 1;
  }
  // a 3.153 install (scripts2D/main2D.cs) runs the 3.153 game library
  const bool is_3153 = std::ifstream(root + "/scripts2D/main2D.cs.dso").good() ||
                       std::ifstream(root + "/scripts2D/main2D.cs").good();
  // Each release zip ships one game library beside the program (3.04's,
  // 3.153's, or 3.0beta's, 3.01's or 3.151's on the same program). If
  // exactly one is there, it is the build; otherwise the install picks.
  if (lib.empty()) {
    std::vector<std::string> present;
    for (const char* base : {"Game304Lib", "Game3153Lib", "Game30bLib", "Game301Lib", "Game3151Lib"}) {
      const std::string file = here + "/" + game_lib_file(base);
      if (std::ifstream(file).good()) present.push_back(file);
    }
    lib = present.size() == 1 ? present[0] : here + "/" + game_lib_file(is_3153 ? "Game3153Lib" : "Game304Lib");
  }
  if (prefs.empty()) prefs = default_prefs();
  make_dir(prefs);
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
    fail(error);
    return 1;
  }
  GuiGraal304 graal(engine, std::move(game));
  if (is_install_3153(engine)) graal.register_3153();
  boot_304(engine);

  int width = 800, height = 600;
  canvas_size_304(engine, width, height);
  auto window = Window::open("Graal 3.04 (Torque rebuild)", width, height, error);
  if (!window) {
    fail(error);
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
    // setScreenMode (Options, Apply) changed the resolution pref.
    int want_w = width, want_h = height;
    canvas_size_304(engine, want_w, want_h);
    if (want_w != width || want_h != height) {
      width = want_w;
      height = want_h;
      window->resize(width, height);
      frame.resize(width, height);
      engine.trace.push_back("window " + std::to_string(width) + " x " + std::to_string(height));
    }
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
    engine.trace.push_back("player " + graal.game().player() + ", state " + std::to_string(graal.game().state()));
    std::ofstream out(trace_path, std::ios::binary);
    for (const auto& line : engine.trace) out << line << "\n";
    for (const auto& line : frame.log) out << line << "\n";
  }
  return 0;
}
