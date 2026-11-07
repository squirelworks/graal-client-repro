// host4208: the residual Torque surface of the 4.2.0.8 engine.
//
// C++ only. The engine has no Torque console, so this program does not
// run TorqueScript. The Delphi launcher in graal-4.20r8-G3D20126 is a
// different program and is not replaced here.
//
// The frame helper is local to this directory.

#include "login.hpp"
#include "surface.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

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

bool take(int &i, int argc, char **argv, std::string &value) {
  if (i + 1 >= argc) {
    return false;
  }
  value = argv[++i];
  return true;
}

} // namespace

int main(int argc, char **argv) {
  std::string script = "scripts/set-content.cs";
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

  std::cout << "host4208: 4.2.0.8 engine host (C++; no Torque console)\n";
  std::cout << "host4208: token G3D20126 PROVISIONAL "
               "(folder name; not re-read from the DLL this pass)\n";

  SurfaceResult surface;
  std::string error;
  if (!runSurfaceFile(script, surface, error)) {
    std::cerr << "host4208: " << error << "\n";
    return 1;
  }
  std::cout << "host4208: script " << script << "\n";
  for (std::size_t i = 0; i < surface.log.size(); ++i) {
    std::cout << "host4208: " << surface.log[i] << "\n";
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
