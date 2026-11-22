// quattro-play: the Quattro program in a window (X11), or headless with a
// PNG of the last frame. Against a server you start yourself.
//
//   LAB_PW=... quattro-play --build 6.03r7 --connect 127.0.0.1:14900
//       --account NAME --password-env LAB_PW [--assets DIR]
//       [--headless --seconds 15 --shot out.png]
//   quattro-play --build 6.03r7 --offline start.nw [--x 30 --y 30] --assets DIR
//
// The 6.01r1 and 6.03r7 folders ship it beside their start screen, which
// hands the picked server (or Training) to it with --server-name,
// --nickname and --asset-root. Online, the Seihai secure login follows the
// player's setting (GRAAL_SECURE_LOGIN or secure_login.txt) unless
// --secure-login and --server-key say otherwise.
#include "../shell/program.hpp"

#include <chrono>
#include <cmath>
#include <limits>
#include <locale>
#include <sstream>
#include <cstdio>
#include <cstdlib>
#include <thread>

using namespace Quattro;

namespace {
// Consume the complete argument before creating a window or connection.
bool integer(const std::string& text, int minimum, int maximum, int& value) {
  if (text.empty()) return false;
  std::size_t i = text[0] == '+' ? 1 : 0;
  if (i == text.size()) return false;
  int parsed = 0;
  for (; i < text.size(); ++i) {
    if (text[i] < '0' || text[i] > '9') return false;
    const int digit = text[i] - '0';
    if (parsed > maximum / 10 || (parsed == maximum / 10 && digit > maximum % 10)) return false;
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

bool dimensions(const std::string& text, int& width, int& height) {
  const auto x = text.find('x');
  if (x == std::string::npos || text.find('x', x + 1) != std::string::npos) return false;
  int w = 0, h = 0;
  if (!integer(text.substr(0, x), 64, 4096, w) ||
      !integer(text.substr(x + 1), 64, 4096, h)) return false;
  width = w;
  height = h;
  return true;
}

int usage() {
  std::fprintf(stderr,
               "usage: quattro-play --build LABEL --connect HOST:PORT --account NAME --password-env VAR\n"
               "                    [--server-name NAME] [--nickname NICK]\n"
               "                    [--secure-login off|auto|required] [--server-key BASE64]\n"
               "       quattro-play --build LABEL --offline LEVEL [--x X --y Y]\n"
               "  both: [--assets DIR] [--asset-root DIR]... [--download-files] [--program FILE]\n"
               "        [--size WxH] [--headless] [--seconds N] [--shot FILE.png]\n"
               "  game chat: Ctrl+Enter opens; Enter sends; Esc cancels (printable ASCII, 223 bytes)\n");
  return 2;
}
}  // namespace

int main(int argc, char** argv) {
  Shell::Options opt;
  // The player's own setting, shared with the start screens (GSecLogin).
  opt.secure = Net::Sec::configured_mode();
  std::string target, pw_env, shot, offline;
  double start_x = 30, start_y = 30;
  bool headless = false, sized = false;
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
    else if (a == "--asset-root") opt.asset_roots.push_back(next());
    else if (a == "--download-files") opt.download_files = true;
    else if (a == "--server-name") opt.server_name = next();
    else if (a == "--nickname") opt.nickname = next();
    else if (a == "--secure-login") {
      if (!Net::Sec::parse_mode(next(), opt.secure)) return usage();
    } else if (a == "--server-key") {
      opt.server_key = next();
      std::string k;
      if (!Net::Sec::decode_key(opt.server_key, k)) return usage();
    }
    else if (a == "--offline") offline = next();
    else if (a == "--x") { if (!coordinate(next(), start_x)) return usage(); }
    else if (a == "--y") { if (!coordinate(next(), start_y)) return usage(); }
    else if (a == "--headless") headless = true;
    else if (a == "--seconds") {
      if (!integer(next(), 0, std::numeric_limits<int>::max(), seconds)) return usage();
    }
    else if (a == "--shot") shot = next();
    else if (a == "--size") {
      sized = true;
      std::string s = next();
      if (!dimensions(s, opt.width, opt.height)) return usage();
    } else return usage();
  }
  const Net::BuildProfile* prof = Net::find_profile(opt.build);
  if (prof && prof->hud_6x && !sized) {  // the 6.03r7 lab: 1024 x 768 on first start
    opt.width = 1024;
    opt.height = 768;
  }
  if (!prof) return usage();
  if (offline.empty()) {
    size_t colon = target.rfind(':');
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
  if (!headless) window = Draw::open_window(opt.width, opt.height, "Graal");
  if (!window) {
    if (!headless) std::fprintf(stderr, "no display: running headless\n");
    auto h = std::make_unique<Draw::HeadlessWindow>();
    hw = h.get();
    window = std::move(h);
    if (seconds == 0) seconds = 15;
  }

  Shell::Program program(*prof, opt, *window);
  program.log = [](const std::string& s) { std::printf("%s\n", s.c_str()); };
  if (offline.empty() ? !program.start() : !program.start_offline(offline, start_x, start_y)) {
    std::fprintf(stderr, "%s\n", offline.empty() ? "could not start" : ("no level " + offline).c_str());
    return 1;
  }
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
