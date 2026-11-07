/* Thin host for the 6.114 Worlds folder.

   Worlds is a Unity player plus the native Graal3DEngine. This program is
   neither, and it is not the Torque engine. It does not start an IL2CPP
   player. It can be pointed at the loopback address on a lab port.
   It sends one login-shaped frame and logs it.

   The token bytes are GNP1905C from the 6.1.1.3 connector note. This
   host marks them provisional: the 6.114 dump did not store a clear
   login literal. The frame is a plain zlib member with no cipher byte.
   It is not a 6.114 wire map.

   An unknown call logs its name and returns. Peer bytes are an unknown
   call. They are not parsed. */

#include <zlib.h>

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

/* Connector token from the 6.1.1.3 note. Provisional for this host. */
const char *kLoginToken = "GNP1905C";
/* Build 71243 publishes this native export. Earlier builds use an
   obfuscated name that was not recovered. */
const char *kNativeExport = "Flavor0";
/* A 7-bit key, fixed so a lab log can be compared. Not a recovered key. */
const int kAttemptKey = 1;

// provisional: body not yet known
int unknown_call(const std::string &name) {
  std::cout << "unknown call " << name << "\n";
  return 0;
}

char gchar(int v) {
  if (v < 0) v = 0;
  if (v > 223) v = 223;
  return static_cast<char>(v + 0x20);
}

std::string gstring(const std::string &s) {
  std::string t = s.size() > 223 ? s.substr(0, 223) : s;
  return std::string(1, gchar(static_cast<int>(t.size()))) + t;
}

// provisional: body not yet known
std::string login_plain(const std::string &account, const std::string &password) {
  std::string plain;
  plain += gchar(5);
  plain += gchar(kAttemptKey);
  plain += kLoginToken;
  plain += gstring(account);
  plain += gstring(password);
  plain += "linux,\"\",\"\",\"\",\"\"";
  plain += '\n';
  return plain;
}

std::vector<unsigned char> zlib_member(const std::string &plain) {
  uLongf bound = compressBound(static_cast<uLong>(plain.size()));
  std::vector<unsigned char> out(bound);
  uLongf len = bound;
  int rc = compress2(out.data(), &len,
                     reinterpret_cast<const Bytef *>(plain.data()),
                     static_cast<uLong>(plain.size()), Z_DEFAULT_COMPRESSION);
  if (rc != Z_OK) return {};
  out.resize(len);
  return out;
}

std::vector<unsigned char> login_frame(const std::vector<unsigned char> &z) {
  std::vector<unsigned char> frame;
  frame.push_back(static_cast<unsigned char>((z.size() >> 8) & 0xff));
  frame.push_back(static_cast<unsigned char>(z.size() & 0xff));
  frame.insert(frame.end(), z.begin(), z.end());
  return frame;
}

void log_preamble() {
  std::cout << "token " << kLoginToken << " provisional\n";
  std::cout << "native export " << kNativeExport << "\n";
  std::cout << "not a wire map\n";
}

void log_frame(const std::vector<unsigned char> &frame) {
  std::cout << "login frame " << frame.size() << " bytes\n";
  std::cout << "frame:";
  for (size_t i = 0; i < frame.size(); ++i) {
    if (i % 24 == 0) std::cout << "\n";
    char hex[8];
    std::snprintf(hex, sizeof hex, " %02x", frame[i]);
    std::cout << hex;
  }
  std::cout << "\n";
}

bool inflate_matches(const std::string &plain, const std::vector<unsigned char> &z) {
  if (z.size() < 2) return false;
  std::vector<unsigned char> back(plain.size() + 64);
  uLongf got = static_cast<uLongf>(back.size());
  int rc = uncompress(back.data(), &got, z.data(), static_cast<uLong>(z.size()));
  if (rc != Z_OK || got != plain.size()) return false;
  return std::memcmp(back.data(), plain.data(), plain.size()) == 0;
}

bool build_frame(const std::string &account, const std::string &password,
                 std::string &plain, std::vector<unsigned char> &frame) {
  if (account.find('\n') != std::string::npos ||
      password.find('\n') != std::string::npos) {
    std::cout << "account or password contains a newline\n";
    return false;
  }
  plain = login_plain(account, password);
  std::vector<unsigned char> z = zlib_member(plain);
  if (z.empty() || z.size() >= 65535) return false;
  if (!inflate_matches(plain, z)) return false;
  frame = login_frame(z);
  if (frame.size() != z.size() + 2) return false;
  unsigned int declared = (static_cast<unsigned int>(frame[0]) << 8) | frame[1];
  return declared == z.size();
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
  std::string plain;
  std::vector<unsigned char> frame;
  if (!build_frame("loop1", "loopbackpw", plain, frame)) {
    std::cout << "self-check: frame did not build\n";
    return 1;
  }
  if (std::strcmp(kLoginToken, "GNP1905C") != 0) return 1;
  if (plain.find("GNP1905C") == std::string::npos) return 1;
  if (plain[0] != gchar(5) || plain[1] != gchar(kAttemptKey)) return 1;
  if (plain[plain.size() - 1] != '\n') return 1;
  log_frame(frame);
  if (unknown_call("self-check-probe") != 0) return 1;
  std::cout << "self-check ok\n";
  return 0;
}

void print_list() {
  std::cout << "6.114 Worlds thin host\n";
  std::cout << "Unity player plus native Graal3DEngine. This program is neither.\n";
  std::cout << "No IL2CPP player. No Torque.\n";
  std::cout << "Token " << kLoginToken << " provisional.\n";
  std::cout << "Native export " << kNativeExport << ".\n";
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
    std::cout << "port out of range\n";
    return 2;
  }
  if (account.empty()) {
    std::cout << "missing --account\n";
    return 2;
  }
  const char *env = std::getenv("GRAAL_PW");
  std::string password = env ? env : "";
  std::string plain;
  std::vector<unsigned char> frame;
  if (!build_frame(account, password, plain, frame)) return 1;
  std::cout << "plain login shape provisional: type 5, key " << kAttemptKey
            << ", token " << kLoginToken << ", account " << account
            << ", password length " << password.size()
            << ", tail linux and four empty machine fields\n";
  log_frame(frame);
  std::cout.flush();
  char numeric[64];
  in_addr loop;
  loop.s_addr = htonl(INADDR_LOOPBACK);
  if (inet_ntop(AF_INET, &loop, numeric, sizeof numeric) == 0)
    std::snprintf(numeric, sizeof numeric, "loopback");
  std::cout << "connect " << numeric << ":" << port << "\n";
  int fd = connect_loopback(port);
  if (fd < 0) {
    std::cout << "connect failed\n";
    return 1;
  }
  if (send_all(fd, frame) != 0) {
    std::cout << "send failed\n";
    ::close(fd);
    return 1;
  }
  std::cout << "sent " << frame.size() << " bytes\n";
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
        std::cout << "bad port\n";
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
  std::cout << "worlds-host: thin host for 6.114. "
               "--port PORT --account NAME\n";
  return 0;
}
