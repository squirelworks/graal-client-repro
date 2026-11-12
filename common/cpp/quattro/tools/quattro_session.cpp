// quattro-session: runs the Quattro game session headless and logs what
// arrives. A lab tool for checking the session against a server you start;
// it draws nothing and runs no scripts.
//
//   quattro-session --list
//   LAB_PW=... quattro-session --build 6.03r7 --connect 127.0.0.1:14900
//       --account NAME --password-env LAB_PW [--seconds 20]
#include "../net/connection.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

using namespace Quattro::Net;

namespace {

int usage() {
  std::fprintf(stderr,
               "usage: quattro-session --list\n"
               "       quattro-session --build LABEL --connect HOST:PORT --account NAME\n"
               "                       --password-env VAR [--language L] [--seconds N]\n");
  return 2;
}

std::string printable(std::string_view b, size_t max = 60) {
  std::string out;
  for (size_t i = 0; i < b.size() && i < max; ++i) {
    unsigned char c = static_cast<unsigned char>(b[i]);
    out += (c >= 32 && c < 127) ? static_cast<char>(c) : '.';
  }
  if (b.size() > max) out += "...";
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  std::string build, target, account, pw_env, language = "English";
  int seconds = 20;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--list") {
      for (const auto& p : profiles())
        std::printf("%-14s %s  %zu server ids, %zu client ids\n", p.label.c_str(), p.token.c_str(), p.plo.count(),
                    p.pli.count());
      return 0;
    }
    if (a == "--build") build = next();
    else if (a == "--connect") target = next();
    else if (a == "--account") account = next();
    else if (a == "--password-env") pw_env = next();
    else if (a == "--language") language = next();
    else if (a == "--seconds") seconds = std::atoi(next().c_str());
    else return usage();
  }
  const BuildProfile* prof = find_profile(build);
  size_t colon = target.rfind(':');
  if (!prof || colon == std::string::npos || account.empty() || pw_env.empty()) return usage();
  const char* pw = std::getenv(pw_env.c_str());
  if (!pw) {
    std::fprintf(stderr, "%s is not set\n", pw_env.c_str());
    return 2;
  }
  std::string host = target.substr(0, colon);
  int port = std::atoi(target.c_str() + colon + 1);
  if (port <= 0 || port > 65535) return usage();

  Session::Events ev;
  ev.connecting = [](const std::string& name, const std::string& addr) {
    std::printf("connecting to %s (%s)\n", name.c_str(), addr.c_str());
  };
  ev.connect_failed = [](const std::string& why) { std::printf("connect failed: %s\n", why.c_str()); };
  ev.disconnected = [](const std::string& why) { std::printf("disconnected: %s\n", why.c_str()); };
  ev.message = [](int id, std::string_view body) {
    std::printf("S->C %3d  %5zu  %s\n", id, body.size(), printable(body).c_str());
  };
  Session s(*prof, ev);
  if (!s.start(host, static_cast<uint16_t>(port), account, pw, language)) return 1;
  auto end = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
  while (std::chrono::steady_clock::now() < end) {
    s.tick();
    if (!s.connection().connected()) break;
    // The original's frame gate is 50 ms (v5v6-lab-play.md).
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  std::printf("server %s, lobby mode %s, %d login(s), %zu id(s) dropped\n", s.server_name().c_str(),
              s.lobby_mode() ? "yes" : "no", s.logins(), s.connection().dropped());
  return 0;
}
