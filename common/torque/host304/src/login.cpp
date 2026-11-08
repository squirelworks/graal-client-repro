#include "login.hpp"

#include <cerrno>
#include <cstdio>
#include <cstring>

#include <sstream>
#include <vector>

#include <zlib.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
using sock_t = SOCKET;
static const sock_t kBadSock = INVALID_SOCKET;
static void close_sock(sock_t fd) { closesocket(fd); }
static int sock_err() { return WSAGetLastError(); }
static bool sock_start(std::string &error) {
  static bool ready = false;
  if (ready) {
    return true;
  }
  WSADATA data;
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
    error = "WSAStartup failed";
    return false;
  }
  ready = true;
  return true;
}
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
using sock_t = int;
static const sock_t kBadSock = -1;
static void close_sock(sock_t fd) { close(fd); }
static int sock_err() { return errno; }
static bool sock_start(std::string &) { return true; }
// Linux defines this in sys/socket.h. macOS does not. Defining it as 0
// leaves the Linux send flags alone.
#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif
#endif

namespace {

std::string gChar(int v) {
  if (v < 0) {
    v = 0;
  }
  if (v > 223) {
    v = 223;
  }
  return std::string(1, static_cast<char>(v + 0x20));
}

std::string gString(const std::string &s) {
  const std::string t = s.size() > 223 ? s.substr(0, 223) : s;
  return gChar(static_cast<int>(t.size())) + t;
}

// Five-byte GINT5. Zero is five 0x20 bytes. See the provisional note
// on the filename prefix in login.hpp.
std::string gInt5(std::uint32_t v) {
  std::string out;
  out.push_back(static_cast<char>(((v >> 28) & 0x0F) + 0x20));
  out.push_back(static_cast<char>(((v >> 21) & 0x7F) + 0x20));
  out.push_back(static_cast<char>(((v >> 14) & 0x7F) + 0x20));
  out.push_back(static_cast<char>(((v >> 7) & 0x7F) + 0x20));
  out.push_back(static_cast<char>((v & 0x7F) + 0x20));
  return out;
}

bool zlibCompress(const std::string &plain, std::string &out, std::string &error) {
  uLong bound = compressBound(static_cast<uLong>(plain.size()));
  std::vector<unsigned char> buf(bound);
  uLongf dest = bound;
  const int rc =
      compress2(buf.data(), &dest, reinterpret_cast<const Bytef *>(plain.data()),
                static_cast<uLong>(plain.size()), Z_DEFAULT_COMPRESSION);
  if (rc != Z_OK) {
    error = "zlib compress failed";
    return false;
  }
  out.assign(reinterpret_cast<const char *>(buf.data()), dest);
  return true;
}

bool zlibUncompress(const std::string &in, std::size_t plainSize, std::string &out,
                    std::string &error) {
  if (plainSize > 1024 * 1024) {
    error = "plain login is unexpectedly large";
    return false;
  }
  std::vector<unsigned char> buf(plainSize + 64);
  uLongf dest = static_cast<uLongf>(buf.size());
  const int rc =
      uncompress(buf.data(), &dest, reinterpret_cast<const Bytef *>(in.data()),
                 static_cast<uLong>(in.size()));
  if (rc != Z_OK) {
    error = "zlib uncompress failed";
    return false;
  }
  out.assign(reinterpret_cast<const char *>(buf.data()), dest);
  return true;
}

bool isLoopback(std::uint32_t hostOrder) {
  return (hostOrder >> 24) == 127;
}

std::string formatAddr(const sockaddr_in &addr) {
  char text[INET_ADDRSTRLEN];
  if (inet_ntop(AF_INET, &addr.sin_addr, text, sizeof text) == 0) {
    return "loopback";
  }
  std::ostringstream o;
  o << text << ":" << ntohs(addr.sin_port);
  return o.str();
}

} // namespace

bool buildLoginFrame(int key, const std::string &account, const std::string &password,
                     const std::string &language, LoginFrame &out, std::string &error) {
  if (key < 0 || key > 127) {
    error = "key must be 0..127";
    return false;
  }
  if (language.find('\n') != std::string::npos ||
      account.find('\n') != std::string::npos ||
      password.find('\n') != std::string::npos) {
    error = "login fields must not contain a newline";
    return false;
  }

  // Packet id is GCHAR(id), which is id + 0x20. Id 5 is the login line.
  // Ids 37 and 34 are the language and the two file requests.
  const int kLogin = 5;
  const int kLanguage = 37;
  const int kUpdateFile = 34;

  std::string plain;
  plain += gChar(kLogin);
  plain += gChar(key);
  plain += "G3D03014";
  plain += gString(account);
  plain += gString(password);
  plain += '\n';
  plain += gChar(kLanguage);
  plain += language;
  plain += '\n';
  // PROVISIONAL filename prefix: GINT5 zero, then the name. See login.hpp.
  plain += gChar(kUpdateFile);
  plain += gInt5(0);
  plain += "bigmap.txt";
  plain += '\n';
  plain += gChar(kUpdateFile);
  plain += gInt5(0);
  plain += "minimap.txt";
  plain += '\n';

  std::string z;
  if (!zlibCompress(plain, z, error)) {
    return false;
  }
  if (z.size() > 0xFFFF) {
    error = "zlib member does not fit a u16 length";
    return false;
  }

  std::string wire;
  wire.push_back(static_cast<char>((z.size() >> 8) & 0xFF));
  wire.push_back(static_cast<char>(z.size() & 0xFF));
  wire += z;

  out.plain = plain;
  out.wire = wire;
  out.key = key;
  return true;
}

bool loginFrameRoundTrip(const LoginFrame &frame, std::string &error) {
  if (frame.wire.size() < 2) {
    error = "frame is shorter than a length";
    return false;
  }
  const unsigned len = (static_cast<unsigned char>(frame.wire[0]) << 8) |
                       static_cast<unsigned char>(frame.wire[1]);
  if (frame.wire.size() != len + 2) {
    error = "frame length does not match the u16";
    return false;
  }
  std::string back;
  if (!zlibUncompress(frame.wire.substr(2), frame.plain.size(), back, error)) {
    return false;
  }
  if (back != frame.plain) {
    error = "inflated login does not match the plain body";
    return false;
  }
  if (back.find("G3D03014") == std::string::npos) {
    error = "login plain is missing G3D03014";
    return false;
  }
  return true;
}

SendResult sendLoginFrame(const std::string &host, std::uint16_t port,
                          const std::string &wire) {
  SendResult result;
  result.status = SendStatus::Error;

  sockaddr_in addr;
  std::memset(&addr, 0, sizeof addr);
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);

  if (host.empty()) {
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  } else {
    addrinfo hints;
    std::memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo *got = 0;
    const int rc = getaddrinfo(host.c_str(), 0, &hints, &got);
    if (rc != 0 || got == 0) {
      result.detail = "could not resolve host";
      return result;
    }
    const sockaddr_in *in = reinterpret_cast<sockaddr_in *>(got->ai_addr);
    addr.sin_addr = in->sin_addr;
    freeaddrinfo(got);
  }

  const std::uint32_t hostOrder = ntohl(addr.sin_addr.s_addr);
  if (!isLoopback(hostOrder)) {
    result.status = SendStatus::RejectedHost;
    result.detail = "refusing non-loopback " + formatAddr(addr);
    return result;
  }

  if (!sock_start(result.detail)) {
    return result;
  }
  const sock_t fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd == kBadSock) {
    result.detail = "socket failed";
    return result;
  }
#ifdef _WIN32
  u_long nb = 1;
  if (ioctlsocket(fd, FIONBIO, &nb) != 0) {
    close_sock(fd);
    result.detail = "could not set non-blocking";
    return result;
  }
  const int would_block = WSAEWOULDBLOCK;
  const int again = WSAEWOULDBLOCK;
#else
  const int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    close_sock(fd);
    result.detail = "could not set non-blocking";
    return result;
  }
  const int would_block = EINPROGRESS;
  const int again = EAGAIN;
#endif

  const int cr = connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr);
  if (cr < 0 && sock_err() != would_block) {
    const int err = sock_err();
    close_sock(fd);
    if (err == ECONNREFUSED || err == ENETUNREACH || err == EHOSTUNREACH
#ifdef _WIN32
        || err == WSAECONNREFUSED || err == WSAENETUNREACH || err == WSAEHOSTUNREACH
#endif
    ) {
      result.status = SendStatus::Refused;
      result.detail = "no listener on " + formatAddr(addr);
      return result;
    }
    result.detail = "connect failed";
    return result;
  }

#ifdef _WIN32
  WSAPOLLFD pfd;
  pfd.fd = fd;
  pfd.events = POLLOUT;
  pfd.revents = 0;
  const int pr = WSAPoll(&pfd, 1, 500);
#else
  pollfd pfd;
  pfd.fd = fd;
  pfd.events = POLLOUT;
  pfd.revents = 0;
  const int pr = poll(&pfd, 1, 500);
#endif
  if (pr <= 0) {
    close_sock(fd);
    result.status = SendStatus::Refused;
    result.detail = "no listener on " + formatAddr(addr);
    return result;
  }
  int soerr = 0;
  socklen_t slen = sizeof soerr;
  getsockopt(fd, SOL_SOCKET, SO_ERROR, reinterpret_cast<char *>(&soerr), &slen);
  if (soerr != 0) {
    close_sock(fd);
    if (soerr == ECONNREFUSED || soerr == ENETUNREACH || soerr == EHOSTUNREACH
#ifdef _WIN32
        || soerr == WSAECONNREFUSED || soerr == WSAENETUNREACH || soerr == WSAEHOSTUNREACH
#endif
    ) {
      result.status = SendStatus::Refused;
      result.detail = "no listener on " + formatAddr(addr);
      return result;
    }
    result.detail = "connect failed";
    return result;
  }

  std::size_t sent = 0;
  while (sent < wire.size()) {
    const int n = static_cast<int>(send(fd, wire.data() + sent, static_cast<int>(wire.size() - sent), MSG_NOSIGNAL));
    if (n < 0) {
      const int err = sock_err();
      if (err == EINTR || err == again
#ifdef _WIN32
          || err == WSAEINTR
#endif
      ) {
        continue;
      }
      close_sock(fd);
      result.detail = "send failed";
      return result;
    }
    if (n == 0) {
      close_sock(fd);
      result.detail = "send returned no bytes";
      return result;
    }
    sent += static_cast<std::size_t>(n);
  }
#ifdef _WIN32
  shutdown(fd, SD_SEND);
#else
  shutdown(fd, SHUT_WR);
#endif
  close_sock(fd);
  result.status = SendStatus::Sent;
  result.detail = "sent " + std::to_string(wire.size()) + " bytes to " + formatAddr(addr);
  return result;
}

std::string hexBytes(const std::string &bytes) {
  std::ostringstream o;
  for (std::size_t i = 0; i < bytes.size(); ++i) {
    if (i) {
      o << ' ';
    }
    char buf[4];
    std::snprintf(buf, sizeof buf, "%02x", static_cast<unsigned char>(bytes[i]));
    o << buf;
  }
  return o.str();
}

std::string escapeBytes(const std::string &bytes) {
  std::string o;
  for (unsigned char c : bytes) {
    if (c == '\n') {
      o += "\\n";
    } else if (c == '\r') {
      o += "\\r";
    } else if (c < 32 || c > 126) {
      char buf[8];
      std::snprintf(buf, sizeof buf, "\\x%02x", c);
      o += buf;
    } else {
      o.push_back(static_cast<char>(c));
    }
  }
  return o;
}
