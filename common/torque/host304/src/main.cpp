// host304: a 3.04-shaped Torque host.
//
// It registers GuiGraalCtrl, runs one TorqueScript file, and sends a
// login-shaped first frame at loopback. The console behind the script
// is a line runner. It is not the stock TGE console and it does not
// execute main.cs.
//
// The Pascal module list under common/torque stays as it is.

#include "guigraal.hpp"
#include "login.hpp"
#include "script.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

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
      << "host304 [--script FILE] [--port N] [--host NAME] [--key N]\n"
      << "        [--account NAME] [--password TEXT] [--language TEXT]\n"
      << "\n"
      << "Boots a 3.04-shaped host, runs one TorqueScript camera move,\n"
      << "and sends the login-shaped first frame to loopback.\n"
      << "The default address is loopback. A non-loopback host is refused.\n"
      << "The default port is the lab port 14802.\n";
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
  if (names.size() != 9) {
    error = "3.04.list does not name nine modules";
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
  std::string script = "scripts/camera-move.cs";
  bool scriptExplicit = false;
  std::string host;
  std::string account = "lab";
  std::string password = "lab";
  std::string language = "English";
  int port = 14802;
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
      scriptExplicit = true;
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
    } else if (arg == "--language") {
      if (!take(i, argc, argv, value)) {
        usage();
        return 2;
      }
      language = value;
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
  if (guiMethodCount() != 31) {
    std::cerr << "GuiGraalCtrl table is not 31 methods\n";
    return 1;
  }

  std::cout << "host304: 3.04-shaped TGE host (line runner, not a full console)\n";
  std::cout << "host304: token G3D03014 (folder name; lab login token)\n";

  std::string error;
  const std::string listPath = findUp("common/torque/manifests/3.04.list");
  if (listPath.empty()) {
    std::cerr << "host304: cannot find manifests/3.04.list\n";
    return 1;
  }
  std::vector<std::string> modules;
  if (!loadModuleList(listPath, modules, error)) {
    std::cerr << "host304: " << error << "\n";
    return 1;
  }
  bool sawGuiGraal = false;
  bool sawGameObject = false;
  for (std::size_t i = 0; i < modules.size(); ++i) {
    std::cout << "host304: registered module " << modules[i] << "\n";
    if (modules[i] == "guigraal") {
      sawGuiGraal = true;
    }
    if (modules[i] == "gameobject") {
      sawGameObject = true;
    }
  }
  if (!sawGuiGraal || sawGameObject) {
    std::cerr << "host304: module list is not the 3.04 TGE set\n";
    return 1;
  }

  // Only the implicit demo may be resolved from the bundled location.
  // An explicit path must fail at that path, never run a different script.
  if (!scriptExplicit && !fileExists(script)) {
    const std::string beside = findUp("common/torque/host304/scripts/camera-move.cs");
    if (!beside.empty()) {
      script = beside;
    }
  }

  ScriptResult scriptResult;
  if (!runScriptFile(script, scriptResult, error)) {
    std::cerr << "host304: " << error << "\n";
    return 1;
  }
  std::cout << "host304: script " << script << "\n";
  for (std::size_t i = 0; i < scriptResult.log.size(); ++i) {
    std::cout << "host304: " << scriptResult.log[i] << "\n";
  }
  if (!scriptResult.levelOpened || !levelViewOpen()) {
    std::cerr << "host304: level view did not open\n";
    return 1;
  }

  // Hardcoded key bytes. The script bind file does not own these.
  std::vector<std::string> keyLog;
  onHardcodedKey(0x21, 0x0C, keyLog);
  onHardcodedKey(0x19, 0x30, keyLog);
  onHardcodedKey(0x26, 0x00, keyLog);
  onHardcodedKey(2, 0x00, keyLog);
  for (std::size_t i = 0; i < keyLog.size(); ++i) {
    std::cout << "host304: " << keyLog[i] << "\n";
  }

  LoginFrame frame;
  if (!buildLoginFrame(key, account, password, language, frame, error)) {
    std::cerr << "host304: " << error << "\n";
    return 1;
  }
  if (!loginFrameRoundTrip(frame, error)) {
    std::cerr << "host304: " << error << "\n";
    return 1;
  }

  std::cout << "host304: login key " << key
            << " (lab fixed; the client draws a key in 0..127)\n";
  std::cout << "host304: login-plain: " << escapeBytes(frame.plain) << "\n";
  std::cout << "host304: login-roundtrip: ok\n";
  std::cout << "host304: first-frame-bytes: " << hexBytes(frame.wire) << "\n";
  std::cout << "host304: first-frame-len: " << frame.wire.size() << "\n";
  std::cout << "host304: filename prefix on id 34 is provisional "
               "(GINT5 zero; lab note names the files, Test304 supplies the bytes)\n";

  const SendResult sent =
      sendLoginFrame(host, static_cast<std::uint16_t>(port), frame.wire);
  if (sent.status == SendStatus::RejectedHost || sent.status == SendStatus::Error) {
    std::cerr << "host304: " << sent.detail << "\n";
    return 1;
  }
  std::cout << "host304: " << sent.detail << "\n";
  return 0;
}
