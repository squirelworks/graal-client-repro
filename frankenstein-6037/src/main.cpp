// frankenstein-6037: a 6.037 host with the 5.12 Graal3D link folded in and
// UDP left enabled. Community experimental client; see ../README.md.
//
//   PW=... frankenstein-6037 --connect HOST:PORT --account NAME --password-env PW
//       [--server-name NAME] [--nickname NICK] [--assets DIR] [--asset-root DIR]...
//       [--program FILE] [--download-files] [--no-3d-view]
//       [--headless --seconds N --shot FILE.png]
//   frankenstein-6037 --offline LEVEL [--x X --y Y] --assets DIR
//
// A server name starting with "3 " ("3 Lab") goes straight into 3D; with
// the default name (Login) the Login server's 178 warp to a "3 " server
// does the same.
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
  bool headless = false, view3d = true;
  int seconds = 0;
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
    else return usage();
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
  if (offline.empty() ? !host.start() : !host.start_offline(offline, start_x, start_y)) {
    std::fprintf(stderr, "%s\n", offline.empty() ? "could not start" : ("no level " + offline).c_str());
    return 1;
  }
  const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
  for (;;) {
    const auto t0 = std::chrono::steady_clock::now();
    if (!host.tick()) break;
    if (seconds > 0 && t0 >= end) break;
    std::this_thread::sleep_until(t0 + std::chrono::milliseconds(50));
  }
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
