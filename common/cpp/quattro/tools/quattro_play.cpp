// quattro-play: the Quattro program in a window (X11), or headless with a
// PNG of the last frame. Against a server you start yourself.
//
//   LAB_PW=... quattro-play --build 6.03r7 --connect 127.0.0.1:14900
//       --account NAME --password-env LAB_PW [--assets DIR]
//       [--headless --seconds 15 --shot out.png]
#include "../shell/program.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>

using namespace Quattro;

namespace {
int usage() {
  std::fprintf(stderr,
               "usage: quattro-play --build LABEL --connect HOST:PORT --account NAME --password-env VAR\n"
               "                    [--assets DIR] [--program FILE] [--size WxH] [--headless] [--seconds N] [--shot FILE.png]\n");
  return 2;
}
}  // namespace

int main(int argc, char** argv) {
  Shell::Options opt;
  std::string target, pw_env, shot;
  bool headless = false;
  int seconds = 0;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--build") opt.build = next();
    else if (a == "--connect") target = next();
    else if (a == "--account") opt.account = next();
    else if (a == "--password-env") pw_env = next();
    else if (a == "--assets") opt.assets = next();
    else if (a == "--program") opt.program = next();
    else if (a == "--headless") headless = true;
    else if (a == "--seconds") seconds = std::atoi(next().c_str());
    else if (a == "--shot") shot = next();
    else if (a == "--size") {
      std::string s = next();
      if (std::sscanf(s.c_str(), "%dx%d", &opt.width, &opt.height) != 2 || opt.width < 64 || opt.height < 64 ||
          opt.width > 4096 || opt.height > 4096)
        return usage();
    } else return usage();
  }
  const Net::BuildProfile* prof = Net::find_profile(opt.build);
  size_t colon = target.rfind(':');
  if (!prof || colon == std::string::npos || opt.account.empty() || pw_env.empty()) return usage();
  const char* pw = std::getenv(pw_env.c_str());
  if (!pw) {
    std::fprintf(stderr, "%s is not set\n", pw_env.c_str());
    return 2;
  }
  opt.password = pw;
  opt.host = target.substr(0, colon);
  int port = std::atoi(target.c_str() + colon + 1);
  if (port <= 0 || port > 65535) return usage();
  opt.port = static_cast<uint16_t>(port);

  std::unique_ptr<Draw::Window> window;
  Draw::HeadlessWindow* hw = nullptr;
  if (!headless) window = Draw::open_x11_window(opt.width, opt.height, "Graal");
  if (!window) {
    if (!headless) std::fprintf(stderr, "no display: running headless\n");
    auto h = std::make_unique<Draw::HeadlessWindow>();
    hw = h.get();
    window = std::move(h);
    if (seconds == 0) seconds = 15;
  }

  Shell::Program program(*prof, opt, *window);
  program.log = [](const std::string& s) { std::printf("%s\n", s.c_str()); };
  if (!program.start()) return 1;
  auto end = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
  for (;;) {
    auto t0 = std::chrono::steady_clock::now();
    if (!program.tick()) break;
    if (seconds > 0 && t0 >= end) break;
    std::this_thread::sleep_until(t0 + std::chrono::milliseconds(50));
  }
  std::printf("title \"%s\", level %s, lobby %s\n", window->title().c_str(), program.level_name().c_str(),
              program.world().lobby ? "yes" : "no");
  if (hw && !shot.empty()) {
    std::string err;
    if (!Torque::Gui::write_file(shot, Torque::Gui::encode_png(hw->last()), err)) {
      std::fprintf(stderr, "%s\n", err.c_str());
      return 1;
    }
  }
  return 0;
}
