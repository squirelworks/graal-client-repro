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

#include <iostream>
#include <string>

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

  ScriptResult scriptResult;
  std::string error;
  if (!runScriptFile(script, scriptResult, error)) {
    std::cerr << "host304: " << error << "\n";
    return 1;
  }
  std::cout << "host304: script " << script << "\n";
  for (std::size_t i = 0; i < scriptResult.log.size(); ++i) {
    std::cout << "host304: " << scriptResult.log[i] << "\n";
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
