/* Connector for the 6.114 Worlds folder.

   Worlds is a Unity player plus a native plugin. This program is neither,
   and it is not the Torque engine. The playable stand-in is worlds-player
   (portable C#). This program only writes the documented connector hello.

   The hello is the eight bytes GNP1905C. A running 6.113 client sends
   those bytes before it reads the server. They are not marked provisional.
   The bytes after that hello in the 6.113 capture are unidentified, so
   this program does not send a header, a zlib member, a cipher, or a
   6.0x type-5 login. The password is not written.

   An unknown call logs its name and returns. Peer bytes are an unknown
   call. They are not parsed. */

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace {

/* Documented connector token. Not provisional. */
const char *kLoginToken = "GNP1905C";
/* Build 71243 publishes this native export. This program does not call it. */
const char *kNativeExport = "Flavor0";

int unknown_call(const std::string &name) {
  std::cout << "unknown call " << name << "\n";
  return 0;
}

std::vector<unsigned char> hello_bytes() {
  std::vector<unsigned char> hello;
  for (const char *p = kLoginToken; *p; ++p)
    hello.push_back(static_cast<unsigned char>(*p));
  return hello;
}

void log_preamble() {
  std::cout << "connector token " << kLoginToken << "\n";
  std::cout << "native export " << kNativeExport << "\n";
  std::cout << "not a 6.114 wire map\n";
  std::cout << "unity player built: no\n";
}

void log_hello(const std::vector<unsigned char> &hello) {
  std::cout << "connector hello " << hello.size() << " bytes\n";
  std::cout << "frame:";
  for (size_t i = 0; i < hello.size(); ++i) {
    char hex[8];
    std::snprintf(hex, sizeof hex, " %02x", hello[i]);
    std::cout << hex;
  }
  std::cout << "\n";
}

int send_all(int fd, const std::vector<unsigned char> &frame) {
  size_t off = 0;
  while (off < frame.size()) {
    ssize_t n = ::send(fd, frame.data() + off, frame.size() - off, 0);
    if (n <= 0) return -1;
    off += static_cast<size_t>(n);
  }
  return 0;
}

int connect_loopback(int port) {
  for (int attempt = 0; attempt < 20; ++attempt) {
    int fd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    sockaddr_in addr;
    std::memset(&addr, 0, sizeof addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(static_cast<uint16_t>(port));
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (::connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr) == 0)
      return fd;
    ::close(fd);
    ::usleep(100000);
  }
  return -1;
}

int run_self_check() {
  log_preamble();
  std::vector<unsigned char> hello = hello_bytes();
  if (hello.size() != 8) return 1;
  if (std::string(hello.begin(), hello.end()) != kLoginToken) return 1;
  if (std::strcmp(kLoginToken, "GNP1905C") != 0) return 1;
  if (std::strcmp(kLoginToken, "G3D0511C") == 0) return 1;
  log_hello(hello);
  if (unknown_call("self-check-probe") != 0) return 1;
  std::cout << "self-check ok\n";
  return 0;
}

void print_list() {
  std::cout << "6.114 Worlds connector\n";
  std::cout << "The playable stand-in is worlds-player. This program is not a Unity player.\n";
  std::cout << "No IL2CPP player. No Torque.\n";
  std::cout << "Connector token " << kLoginToken << ".\n";
  std::cout << "Native export " << kNativeExport << " (not called).\n";
  std::cout << "Build 614 dump counted 108 assemblies "
               "(6 Quattro, 80 Unity, 10 runtime, 11 plugin, 1 generated).\n";
  std::cout << "Quattro names kept: Assemblies-Quattro.dll, "
               "Assemblies-graalunity.dll.\n";
}

bool parse_port(const std::string &text, int &port) {
  if (text.empty()) return false;
  int value = 0;
  for (size_t i = 0; i < text.size(); ++i) {
    if (text[i] < '0' || text[i] > '9') return false;
    value = value * 10 + (text[i] - '0');
    if (value > 65535) return false;
  }
  if (value <= 0) return false;
  port = value;
  return true;
}

int run_connect(int port, const std::string &account) {
  log_preamble();
  if (port <= 0 || port > 65535) {
    std::cout << "state Error reason=port-out-of-range\n";
    return 2;
  }
  if (account.empty()) {
    std::cout << "state Error reason=missing-account\n";
    return 2;
  }
  std::vector<unsigned char> hello = hello_bytes();
  std::cout << "account " << account << "\n";
  log_hello(hello);
  std::cout.flush();
  char numeric[64];
  in_addr loop;
  loop.s_addr = htonl(INADDR_LOOPBACK);
  if (inet_ntop(AF_INET, &loop, numeric, sizeof numeric) == 0)
    std::snprintf(numeric, sizeof numeric, "loopback");
  std::cout << "connect " << numeric << ":" << port << "\n";
  int fd = connect_loopback(port);
  if (fd < 0) {
    std::cout << "state Error reason=connect-failed\n";
    return 1;
  }
  if (send_all(fd, hello) != 0) {
    std::cout << "state Error reason=send-failed\n";
    ::close(fd);
    return 1;
  }
  std::cout << "sent " << hello.size() << " bytes\n";
  std::cout << "state HelloSent\n";
  timeval tv;
  tv.tv_sec = 0;
  tv.tv_usec = 200000;
  ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  unsigned char buf[512];
  ssize_t n = ::recv(fd, buf, sizeof buf, 0);
  if (n > 0) {
    unknown_call("peer");
    std::cout << "peer bytes " << n << "\n";
  } else {
    std::cout << "no peer bytes\n";
  }
  ::close(fd);
  return 0;
}

}  // namespace

int main(int argc, char **argv) {
  bool list = false;
  bool self = false;
  int port = 0;
  bool have_port = false;
  std::string account;
  std::vector<std::string> calls;
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg == "--list") {
      list = true;
    } else if (arg == "--self-check") {
      self = true;
    } else if (arg == "--port" && i + 1 < argc) {
      if (!parse_port(argv[++i], port)) {
        std::cout << "state Error reason=port-out-of-range\n";
        return 2;
      }
      have_port = true;
    } else if (arg == "--account" && i + 1 < argc) {
      account = argv[++i];
    } else if (arg == "--call" && i + 1 < argc) {
      calls.push_back(argv[++i]);
    } else {
      calls.push_back(arg);
    }
  }
  for (size_t i = 0; i < calls.size(); ++i) unknown_call(calls[i]);
  if (self) return run_self_check();
  if (list) {
    print_list();
    if (!have_port) return 0;
  }
  if (have_port) return run_connect(port, account);
  if (!calls.empty()) return 0;
  std::cout << "worlds-host: connector for 6.114. "
               "--port PORT --account NAME\n";
  return 0;
}
