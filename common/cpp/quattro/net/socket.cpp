#include "socket.hpp"

#include <cstring>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
using sock_t = SOCKET;
#define QSOCK_INVALID INVALID_SOCKET
#define QSOCK_CLOSE closesocket
#define QSOCK_WOULDBLOCK() (WSAGetLastError() == WSAEWOULDBLOCK)
#define QSOCK_INPROGRESS() (WSAGetLastError() == WSAEWOULDBLOCK)
#else
#include <arpa/inet.h>
#include <cerrno>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
using sock_t = int;
#define QSOCK_INVALID (-1)
#define QSOCK_CLOSE ::close
#define QSOCK_WOULDBLOCK() (errno == EAGAIN || errno == EWOULDBLOCK)
#define QSOCK_INPROGRESS() (errno == EINPROGRESS)
#endif

namespace Quattro::Net {

namespace {

#ifdef _WIN32
struct WinsockInit {
  bool ok = false;
  WinsockInit() {
    WSADATA d;
    ok = WSAStartup(MAKEWORD(2, 2), &d) == 0;
  }
  ~WinsockInit() {
    if (ok) WSACleanup();
  }
};
bool winsock() {
  static WinsockInit init;
  return init.ok;
}
#else
bool winsock() { return true; }
#endif

void set_nonblocking(sock_t s) {
#ifdef _WIN32
  u_long on = 1;
  ioctlsocket(s, FIONBIO, &on);
#else
  int fl = fcntl(s, F_GETFL, 0);
  fcntl(s, F_SETFL, fl | O_NONBLOCK);
#endif
}

void set_nodelay(sock_t s) {
  int on = 1;
  setsockopt(s, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&on), sizeof on);
#ifdef SO_NOSIGPIPE
  setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#endif
}

// Waits for `s` to become readable (`write` false) or writable.
bool wait_on(sock_t s, bool write, int ms) {
#ifdef _WIN32
  fd_set set;
  FD_ZERO(&set);
  FD_SET(s, &set);
  timeval tv{ms / 1000, (ms % 1000) * 1000};
  return select(0, write ? nullptr : &set, write ? &set : nullptr, nullptr, &tv) > 0;
#else
  pollfd p{s, static_cast<short>(write ? POLLOUT : POLLIN), 0};
  return ::poll(&p, 1, ms) > 0;
#endif
}

int send_flags() {
#ifdef MSG_NOSIGNAL
  return MSG_NOSIGNAL;
#else
  return 0;
#endif
}

}  // namespace

Socket::~Socket() { close(); }

void Socket::close() {
  if (fd_ >= 0) {
    sock_t s = static_cast<sock_t>(fd_);
#ifdef _WIN32
    shutdown(s, SD_BOTH);
#else
    shutdown(s, SHUT_RDWR);
#endif
    QSOCK_CLOSE(s);
  }
  fd_ = -1;
  out_.clear();
}

bool Socket::connect(const std::string& host, uint16_t port, int timeout_ms) {
  close();
  error_.clear();
  if (!winsock()) {
    error_ = "winsocket startup failed";
    return false;
  }
  addrinfo hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  addrinfo* res = nullptr;
  std::string service = std::to_string(port);
  if (getaddrinfo(host.c_str(), service.c_str(), &hints, &res) != 0 || !res) {
    error_ = "cannot resolve the host";
    return false;
  }
  sock_t s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  if (s == QSOCK_INVALID) {
    freeaddrinfo(res);
    error_ = "cannot create a socket";
    return false;
  }
  set_nonblocking(s);
  int rc = ::connect(s, res->ai_addr, static_cast<int>(res->ai_addrlen));
  freeaddrinfo(res);
  if (rc != 0 && !QSOCK_INPROGRESS()) {
    QSOCK_CLOSE(s);
    error_ = "connect failed";
    return false;
  }
  if (rc != 0) {
    if (!wait_on(s, true, timeout_ms)) {
      QSOCK_CLOSE(s);
      error_ = "connect timed out";
      return false;
    }
    int err = 0;
    socklen_t len = sizeof err;
    getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&err), &len);
    if (err != 0) {
      QSOCK_CLOSE(s);
      error_ = "connect failed";
      return false;
    }
  }
  set_nodelay(s);
  fd_ = static_cast<long long>(s);
  return true;
}

bool Socket::drain() {
  sock_t s = static_cast<sock_t>(fd_);
  while (!out_.empty()) {
    auto n = ::send(s, out_.data(), static_cast<int>(out_.size()), send_flags());
    if (n > 0) {
      out_.erase(0, static_cast<size_t>(n));
      continue;
    }
    if (n < 0 && QSOCK_WOULDBLOCK()) return true;
    error_ = "send failed";
    close();
    return false;
  }
  return true;
}

bool Socket::send(std::string_view bytes) {
  if (fd_ < 0) return false;
  out_.append(bytes);
  return drain();
}

bool Socket::poll(std::string& out) {
  if (fd_ < 0) return false;
  if (!drain()) return false;
  sock_t s = static_cast<sock_t>(fd_);
  char buf[16384];
  for (;;) {
    auto n = ::recv(s, buf, sizeof buf, 0);
    if (n > 0) {
      out.append(buf, static_cast<size_t>(n));
      continue;
    }
    if (n == 0) {
      error_ = "connection closed";
      close();
      return false;
    }
    if (QSOCK_WOULDBLOCK()) return true;
    error_ = "receive failed";
    close();
    return false;
  }
}

void Socket::wait(int ms) {
  if (fd_ < 0) return;
  wait_on(static_cast<sock_t>(fd_), false, ms);
}

bool Socket::listen_loopback(uint16_t port) {
  close();
  if (!winsock()) return false;
  sock_t s = socket(AF_INET, SOCK_STREAM, 0);
  if (s == QSOCK_INVALID) return false;
  int on = 1;
  setsockopt(s, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&on), sizeof on);
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_port = htons(port);
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(s, reinterpret_cast<sockaddr*>(&a), sizeof a) != 0 || listen(s, 4) != 0) {
    QSOCK_CLOSE(s);
    return false;
  }
  fd_ = static_cast<long long>(s);
  return true;
}

uint16_t Socket::local_port() const {
  if (fd_ < 0) return 0;
  sockaddr_in a{};
  socklen_t len = sizeof a;
  if (getsockname(static_cast<sock_t>(fd_), reinterpret_cast<sockaddr*>(&a), &len) != 0) return 0;
  return ntohs(a.sin_port);
}

bool Socket::accept_from(Socket& listener, int timeout_ms) {
  close();
  if (listener.fd_ < 0) return false;
  sock_t l = static_cast<sock_t>(listener.fd_);
  if (!wait_on(l, false, timeout_ms)) return false;
  sock_t s = ::accept(l, nullptr, nullptr);
  if (s == QSOCK_INVALID) return false;
  set_nonblocking(s);
  set_nodelay(s);
  fd_ = static_cast<long long>(s);
  return true;
}

}  // namespace Quattro::Net
