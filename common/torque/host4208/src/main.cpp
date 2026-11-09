// host4208: the residual Torque surface of the 4.2.0.8 engine.
//
// C++ only. The engine has no Torque console, so this program does not
// run TorqueScript. The Delphi launcher in graal-4.20r8-G3D20126 is a
// different program and is not replaced here.
//
// Version-specific fields are local; codec and lab transport are shared.

#include "controls.hpp"
#include "login.hpp"
#include "surface.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#ifndef _WIN32
#include <unistd.h>
#endif

namespace {

void usage() {
  std::cerr
      << "host4208 [--script FILE] [--port N] [--host NAME] [--key N]\n"
      << "         [--account NAME] [--password TEXT]\n"
      << "\n"
      << "Boots the 4.2.0.8 residual surface, sets the canvas content,\n"
      << "and sends the login-shaped first frame to loopback.\n"
      << "The default address is loopback. A non-loopback host is refused.\n"
      << "The default port is the lab port 14900.\n";
}

bool fileExists(const std::string &path) {
  std::ifstream in(path.c_str());
  return static_cast<bool>(in);
}

std::string parentDir(const std::string &path) {
  const std::string::size_type slash = path.find_last_of("/\\");
  if (slash == std::string::npos || slash == 0) {
    return "";
  }
  return path.substr(0, slash);
}

std::string exeDir() {
  char buf[4096];
#ifdef _WIN32
  const unsigned n = GetModuleFileNameA(0, buf, sizeof buf);
  if (n == 0 || n >= sizeof buf) {
    return ".";
  }
  buf[n] = 0;
  for (unsigned i = 0; i < n; ++i) {
    if (buf[i] == '\\') {
      buf[i] = '/';
    }
  }
#else
  const ssize_t n = ::readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (n <= 0) {
    return ".";
  }
  buf[n] = 0;
#endif
  return parentDir(buf);
}

std::string findUp(const std::string &rel) {
  std::string dir = exeDir();
  for (int up = 0; up < 8 && !dir.empty(); ++up) {
    const std::string candidate = dir + "/" + rel;
    if (fileExists(candidate)) {
      return candidate;
    }
    dir = parentDir(dir);
  }
  if (fileExists(rel)) {
    return rel;
  }
  return "";
}

bool loadModuleList(const std::string &path, std::vector<std::string> &names,
                    std::string &error) {
  std::ifstream in(path.c_str());
  if (!in) {
    error = "cannot open " + path;
    return false;
  }
  std::string line;
  while (std::getline(in, line)) {
    std::size_t a = 0;
    while (a < line.size() && (line[a] == ' ' || line[a] == '\t' || line[a] == '\r')) {
      ++a;
    }
    std::size_t b = line.size();
    while (b > a && (line[b - 1] == ' ' || line[b - 1] == '\t' || line[b - 1] == '\r')) {
      --b;
    }
    const std::string trimmed = line.substr(a, b - a);
    if (trimmed.empty() || trimmed[0] == '#') {
      continue;
    }
    names.push_back(trimmed);
  }
  if (names.size() != 4) {
    error = "4.2.0.8-engine.list does not name four modules";
    return false;
  }
  return true;
}

bool take(int &i, int argc, char **argv, std::string &value) {
  if (i + 1 >= argc) {
    return false;
  }
  value = argv[++i];
  return true;
}

} // namespace

int main(int argc, char **argv) {
  std::string script = "scripts/level-tile.cs";
  std::string host;
  std::string account = "lab";
  std::string password = "lab";
  int port = 14900;
  int key = 1;

  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--help" || arg == "-h") {
      usage();
      return 0;
    }
    std::string value;
    if (arg == "--script") {
      if (!take(i, argc, argv, value)) {
        usage();
        return 2;
      }
      script = value;
    } else if (arg == "--host") {
      if (!take(i, argc, argv, value)) {
        usage();
        return 2;
      }
      host = value;
    } else if (arg == "--port") {
      if (!take(i, argc, argv, value)) {
        usage();
        return 2;
      }
      port = std::atoi(value.c_str());
    } else if (arg == "--key") {
      if (!take(i, argc, argv, value)) {
        usage();
        return 2;
      }
      key = std::atoi(value.c_str());
    } else if (arg == "--account") {
      if (!take(i, argc, argv, value)) {
        usage();
        return 2;
      }
      account = value;
    } else if (arg == "--password") {
      if (!take(i, argc, argv, value)) {
        usage();
        return 2;
      }
      password = value;
    } else {
      std::cerr << "unknown argument: " << arg << "\n";
      usage();
      return 2;
    }
  }

  if (port < 1 || port > 65535) {
    std::cerr << "port out of range\n";
    return 2;
  }

  std::cout << "host4208: 4.2.0.8 engine host (C++ residual surface)\n";
  std::cout << "host4208: token " << kVersionToken
            << " (documented Windows 4.20r8 game-server token)\n";

  std::string error;
  const std::string listPath = findUp("common/torque/manifests/4.2.0.8-engine.list");
  if (listPath.empty()) {
    std::cerr << "host4208: cannot find 4.2.0.8-engine.list\n";
    return 1;
  }
  std::vector<std::string> modules;
  if (!loadModuleList(listPath, modules, error)) {
    std::cerr << "host4208: " << error << "\n";
    return 1;
  }
  bool sawGui = false;
  bool sawGraal = false;
  bool sawGame = false;
  for (std::size_t i = 0; i < modules.size(); ++i) {
    std::cout << "host4208: registered module " << modules[i] << "\n";
    if (modules[i] == "gui") sawGui = true;
    if (modules[i] == "guigraal") sawGraal = true;
    if (modules[i] == "game-tge" || modules[i] == "gameobject") sawGame = true;
  }
  if (!sawGui || !sawGraal || sawGame) {
    std::cerr << "host4208: module list is not the 4.2.0.8 engine set\n";
    return 1;
  }

  if (!fileExists(script)) {
    const std::string beside = findUp("common/torque/host4208/scripts/level-tile.cs");
    if (!beside.empty()) {
      script = beside;
    }
  }

  SurfaceResult surface;
  if (!runSurfaceFile(script, surface, error)) {
    std::cerr << "host4208: " << error << "\n";
    return 1;
  }
  std::cout << "host4208: script " << script << "\n";
  for (std::size_t i = 0; i < surface.log.size(); ++i) {
    std::cout << "host4208: " << surface.log[i] << "\n";
  }
  if (!surface.levelOpened || !surface.tilePlaced) {
    std::cerr << "host4208: level was not opened or no tile was placed\n";
    return 1;
  }

  std::vector<std::string> keyLog;
  onEngineKey(0x1B, 0, keyLog);
  onEngineKey(0x1A, 0, keyLog);
  onEngineKey(0x1C, 0, keyLog);
  onEngineKey(0x21, 0x0C, keyLog);
  onEngineKey(0x32, 0, keyLog);
  onEngineKey(0x15, 0, keyLog);
  onEngineKey(0x03, 0, keyLog);
  onEngineKey(0x20, 0, keyLog);
  onEngineKey(0x26, 0, keyLog);
  for (std::size_t i = 0; i < keyLog.size(); ++i) {
    std::cout << "host4208: " << keyLog[i] << "\n";
  }

  LoginFrame frame;
  if (!buildLoginFrame(key, account, password, frame, error)) {
    std::cerr << "host4208: " << error << "\n";
    return 1;
  }
  if (!loginFrameRoundTrip(frame, error)) {
    std::cerr << "host4208: " << error << "\n";
    return 1;
  }

  std::cout << "host4208: login key " << key
            << " (lab fixed; the client draws a key in 0..127)\n";
  std::cout << "host4208: login-plain: " << escapeBytes(frame.plain) << "\n";
  std::cout << "host4208: login-roundtrip: ok\n";
  std::cout << "host4208: first-frame-bytes: " << hexBytes(frame.wire) << "\n";
  std::cout << "host4208: first-frame-len: " << frame.wire.size() << "\n";
  std::cout << "host4208: machine fields are empty (not the real hashes); "
               "ids 37 and 23 are later frames and are not sent\n";

  const SendResult sent =
      sendLoginFrame(host, static_cast<std::uint16_t>(port), frame.wire);
  if (sent.status == SendStatus::RejectedHost || sent.status == SendStatus::Error) {
    std::cerr << "host4208: " << sent.detail << "\n";
    return 1;
  }
  std::cout << "host4208: " << sent.detail << "\n";
  return 0;
}
