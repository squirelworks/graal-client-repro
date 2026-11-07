#include "login.hpp"

#include <arpa/inet.h>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <sstream>
#include <vector>

#include <zlib.h>

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
                     LoginFrame &out, std::string &error) {
  if (key < 0 || key > 127) {
    error = "key must be 0..127";
    return false;
  }
  if (account.find('\n') != std::string::npos || password.find('\n') != std::string::npos) {
    error = "login fields must not contain a newline";
    return false;
  }

  // First frame only: id 5. GCHAR(id) is id + 0x20.
  // PROVISIONAL token G3D20126: folder name, not re-read from the DLL.
  // PROVISIONAL machine fields: empty, as in Test420, not real hashes.
  // Ids 37 and 23 are later gen-5 frames and are not appended here.
  const int kLogin = 5;

  std::string plain;
  plain += gChar(kLogin);
  plain += gChar(key);
  plain += "G3D20126";
  plain += gString(account);
  plain += gString(password);
  plain += "win,\"\",\"\",\"\"";
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
  if (back.find("G3D20126") == std::string::npos) {
    error = "login plain is missing G3D20126";
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

  const int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    result.detail = "socket failed";
    return result;
  }
  const int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
    close(fd);
    result.detail = "could not set non-blocking";
    return result;
  }

  const int cr = connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr);
  if (cr < 0 && errno != EINPROGRESS) {
    const int err = errno;
    close(fd);
    if (err == ECONNREFUSED || err == ENETUNREACH || err == EHOSTUNREACH) {
      result.status = SendStatus::Refused;
      result.detail = "no listener on " + formatAddr(addr);
      return result;
    }
    result.detail = std::string("connect failed: ") + std::strerror(err);
    return result;
  }

  pollfd pfd;
  pfd.fd = fd;
  pfd.events = POLLOUT;
  pfd.revents = 0;
  const int pr = poll(&pfd, 1, 500);
  if (pr <= 0) {
    close(fd);
    result.status = SendStatus::Refused;
    result.detail = "no listener on " + formatAddr(addr);
    return result;
  }
  int soerr = 0;
  socklen_t slen = sizeof soerr;
  getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen);
  if (soerr != 0) {
    close(fd);
    if (soerr == ECONNREFUSED || soerr == ENETUNREACH || soerr == EHOSTUNREACH) {
      result.status = SendStatus::Refused;
      result.detail = "no listener on " + formatAddr(addr);
      return result;
    }
    result.detail = std::string("connect failed: ") + std::strerror(soerr);
    return result;
  }

  std::size_t sent = 0;
  while (sent < wire.size()) {
    const ssize_t n = send(fd, wire.data() + sent, wire.size() - sent, MSG_NOSIGNAL);
    if (n < 0) {
      if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
        continue;
      }
      const int err = errno;
      close(fd);
      result.detail = std::string("send failed: ") + std::strerror(err);
      return result;
    }
    if (n == 0) {
      close(fd);
      result.detail = "send returned no bytes";
      return result;
    }
    sent += static_cast<std::size_t>(n);
  }
  shutdown(fd, SHUT_WR);
  close(fd);
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
