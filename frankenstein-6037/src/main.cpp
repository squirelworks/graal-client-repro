// frankenstein-6037: a 6.037 host with the 5.12 Graal3D link folded in and
// UDP left enabled. Community experimental client; see ../README.md.
//
//   PW=... frankenstein-6037 --connect HOST:PORT --account NAME --password-env PW
//       [--server-name NAME] [--nickname NICK] [--assets DIR] [--asset-root DIR]...
//       [--program FILE] [--download-files] [--no-3d-view]
//       [--headless --seconds N --shot FILE.png]
//       [--renderer auto|opengl|software] [--max-fps N] [--no-fps]
//   frankenstein-6037 --offline LEVEL [--x X --y Y] --assets DIR
//   frankenstein-6037 --bench [WORLD] [--renderer R] [--seconds N] [--size WxH] [--shot-dir DIR]
//
// A server name starting with "3 " ("3 Lab") goes straight into 3D; with
// the default name (Login) the Login server's 178 warp to a "3 " server
// does the same.
#include "bench.hpp"
#include "host6037/host.hpp"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <locale>
#include <sstream>
#include <thread>

using namespace Quattro;

namespace {

bool integer(const std::string& text, int minimum, int maximum, int& value) {
  if (text.empty()) return false;
  int parsed = 0;
  for (char c : text) {
    if (c < '0' || c > '9') return false;
    const int digit = c - '0';
    if (parsed > (maximum - digit) / 10) return false;
    parsed = parsed * 10 + digit;
  }
  if (parsed < minimum) return false;
  value = parsed;
  return true;
}

bool coordinate(const std::string& text, double& value) {
  if (text.empty()) return false;
  std::istringstream input(text);
  input.imbue(std::locale::classic());
  double parsed = 0;
  input >> std::noskipws >> parsed;
  if (input.fail() || !input.eof() || !std::isfinite(parsed)) return false;
  value = parsed;
  return true;
}

int usage() {
  std::fprintf(stderr,
               "usage: frankenstein-6037 --connect HOST:PORT --account NAME --password-env VAR\n"
               "                         [--server-name NAME] [--nickname NICK] [--no-3d-view]\n"
               "       frankenstein-6037 --offline LEVEL [--x X --y Y]\n"
               "  both: [--assets DIR] [--asset-root DIR]... [--download-files] [--program FILE]\n"
               "        [--headless] [--seconds N] [--shot FILE.png]\n"
               "        [--renderer auto|opengl|software] [--max-fps N (0: no cap)] [--no-fps]\n"
               "       frankenstein-6037 --bench [WORLD|all] [--renderer R] [--seconds N] [--size WxH]\n"
               "                         [--shot-dir DIR] [--compare]\n"
               "  A server name starting with \"3 \" is a Graal3D server: UDP on its port + 1.\n");
  return 2;
}

}  // namespace

int main(int argc, char** argv) {
  Shell::Options opt;
  opt.secure = Net::Sec::configured_mode();
  opt.width = 1024;  // the 6.03r7 lab: 1024 x 768 on first start
  opt.height = 768;
  std::string target, pw_env, shot, offline;
  double start_x = 30, start_y = 30;
  bool headless = false, view3d = true, show_fps = true, bench = false, compare = false;
  int seconds = 0, max_fps = 60, bench_w = 1024, bench_h = 768;
  std::string bench_world = "all", shot_dir;
  Frank::RendererChoice renderer = Frank::RendererChoice::Auto;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--connect") target = next();
    else if (a == "--account") opt.account = next();
    else if (a == "--password-env") pw_env = next();
    else if (a == "--assets") opt.assets = next();
    else if (a == "--program") opt.program = next();
    else if (a == "--asset-root") opt.asset_roots.push_back(next());
    else if (a == "--download-files") opt.download_files = true;
    else if (a == "--server-name") opt.server_name = next();
    else if (a == "--nickname") opt.nickname = next();
    else if (a == "--no-3d-view") view3d = false;
    else if (a == "--offline") offline = next();
    else if (a == "--x") { if (!coordinate(next(), start_x)) return usage(); }
    else if (a == "--y") { if (!coordinate(next(), start_y)) return usage(); }
    else if (a == "--headless") headless = true;
    else if (a == "--seconds") { if (!integer(next(), 0, std::numeric_limits<int>::max(), seconds)) return usage(); }
    else if (a == "--shot") shot = next();
    else if (a == "--renderer") { if (!Frank::parse_renderer(next(), renderer)) return usage(); }
    else if (a == "--max-fps") { if (!integer(next(), 0, 1000, max_fps)) return usage(); }
    else if (a == "--no-fps") show_fps = false;
    else if (a == "--bench") {
      bench = true;
      if (i + 1 < argc && argv[i + 1][0] != '-') bench_world = argv[++i];
    }
    else if (a == "--compare") compare = true;
    else if (a == "--shot-dir") shot_dir = next();
    else if (a == "--size") {
      const std::string v = next();
      const size_t x = v.find('x');
      if (x == std::string::npos || !integer(v.substr(0, x), 16, 8192, bench_w) ||
          !integer(v.substr(x + 1), 16, 8192, bench_h))
        return usage();
    }
    else return usage();
  }
  if (bench) {
    Frank::BenchOptions b;
    b.world = bench_world;
    b.renderer = renderer;
    b.seconds = seconds > 0 ? seconds : 5;
    b.width = bench_w;
    b.height = bench_h;
    b.shot_dir = shot_dir;
    b.compare = compare;
    return Frank::run_bench(b);
  }
  if (offline.empty()) {
    const size_t colon = target.rfind(':');
    if (colon == std::string::npos || colon == 0 || opt.account.empty() || pw_env.empty()) return usage();
    int port = 0;
    if (!integer(target.substr(colon + 1), 1, 65535, port)) return usage();
    const char* pw = std::getenv(pw_env.c_str());
    if (!pw) {
      std::fprintf(stderr, "%s is not set\n", pw_env.c_str());
      return 2;
    }
    opt.password = pw;
    opt.host = target.substr(0, colon);
    opt.port = static_cast<uint16_t>(port);
  }

  std::unique_ptr<Draw::Window> window;
  Draw::HeadlessWindow* hw = nullptr;
  if (!headless) window = Draw::open_window(opt.width, opt.height, "Frankenstein 6.037");
  if (!window) {
    if (!headless) std::fprintf(stderr, "no display: running headless\n");
    auto h = std::make_unique<Draw::HeadlessWindow>();
    hw = h.get();
    window = std::move(h);
    if (seconds == 0) seconds = 15;
  }

  Frank::Host host(opt, *window);
  host.view3d = view3d;
  host.log = [](const std::string& s) { std::printf("%s\n", s.c_str()); };
  if (view3d) {
    std::string note;
    host.view().world3d.renderer = Frank::make_renderer(renderer, note);
    std::printf("%s\n", note.c_str());
    if (!host.view().world3d.renderer) return 1;
  }
  host.view().max_fps = max_fps;
  host.view().show_fps = show_fps;
  host.view().log = host.log;
  if (offline.empty() ? !host.start() : !host.start_offline(offline, start_x, start_y)) {
    std::fprintf(stderr, "%s\n", offline.empty() ? "could not start" : ("no level " + offline).c_str());
    return 1;
  }
  const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
  // The 6.x program's clock is its 50 ms tick (timers, walking). Ticks keep
  // to that clock: one that runs long is caught up by the next ones; more
  // than 250 ms behind, the backlog is dropped. Between ticks the 3D view
  // draws new frames on its own clock (ViewWindow::refresh): up to
  // --max-fps with OpenGL, at most about half the time with the software
  // renderer.
  const auto tick = std::chrono::milliseconds(50);
  auto next = std::chrono::steady_clock::now();
  for (;;) {
    const auto t0 = std::chrono::steady_clock::now();
    if (!host.tick()) break;
    if (seconds > 0 && t0 >= end) break;
    next += tick;
    const auto after = std::chrono::steady_clock::now();
    if (after - next > 5 * tick) next = after;
    for (;;) {
      const auto now = std::chrono::steady_clock::now();
      if (now >= next) break;
      if (host.view().refresh()) continue;
      const double due = host.view().next_frame_at();
      auto wake = next;
      if (std::isfinite(due)) {
        const auto at = std::chrono::steady_clock::time_point(
            std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(due)));
        if (at < wake) wake = at;
      }
      std::this_thread::sleep_until(wake);
    }
  }
  if (host.view().counter.frames() > 0)
    std::printf("Graal3D: %s (%s)\n", host.view().counter.summary().c_str(),
                host.view().world3d.renderer ? host.view().world3d.renderer->description().c_str() : "software");
  std::printf("server %s, 3D %s, login step %d\n", host.server().c_str(), host.mode3d() ? "yes" : "no",
              host.login_step());
  if (hw && !shot.empty()) {
    std::string err;
    if (!Torque::Gui::write_file(shot, Torque::Gui::encode_png(hw->last()), err)) {
      std::fprintf(stderr, "%s\n", err.c_str());
      return 1;
    }
  }
  return 0;
}
