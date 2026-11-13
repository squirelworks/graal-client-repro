#include "udp.hpp"

#include <cstring>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
using sock_t = SOCKET;
#define USOCK_INVALID INVALID_SOCKET
#define USOCK_CLOSE closesocket
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
using sock_t = int;
#define USOCK_INVALID (-1)
#define USOCK_CLOSE ::close
#endif

namespace graal3d {

namespace {

#ifdef _WIN32
bool winsock() {
  struct Init {
    bool ok = false;
    Init() {
      WSADATA d;
      ok = WSAStartup(MAKEWORD(2, 2), &d) == 0;
    }
    ~Init() {
      if (ok) WSACleanup();
    }
  };
  static Init init;
  return init.ok;
}
#else
bool winsock() { return true; }
#endif

sock_t S(long long fd) { return static_cast<sock_t>(fd); }

}  // namespace

UdpSocket::~UdpSocket() { close(); }

bool UdpSocket::open(uint16_t localPort, bool loopbackOnly) {
  close();
  if (!winsock()) return false;
  sock_t s = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (s == USOCK_INVALID) return false;
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_port = htons(localPort);
  a.sin_addr.s_addr = htonl(loopbackOnly ? INADDR_LOOPBACK : INADDR_ANY);
  if (::bind(s, reinterpret_cast<sockaddr*>(&a), sizeof a) != 0) {
    USOCK_CLOSE(s);
    return false;
  }
#ifdef _WIN32
  u_long on = 1;
  ioctlsocket(s, FIONBIO, &on);
#else
  fcntl(s, F_SETFL, fcntl(s, F_GETFL, 0) | O_NONBLOCK);
#endif
  fd_ = static_cast<long long>(s);
  return true;
}

bool UdpSocket::setPeer(const std::string& host, uint16_t port) {
  addrinfo hints{};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_DGRAM;
  addrinfo* res = nullptr;
  if (getaddrinfo(host.c_str(), nullptr, &hints, &res) != 0 || !res) return false;
  sockaddr_in a{};
  std::memcpy(&a, res->ai_addr, sizeof a);
  freeaddrinfo(res);
  a.sin_port = htons(port);
  peer_.assign(reinterpret_cast<const char*>(&a), sizeof a);
  return true;
}

void UdpSocket::close() {
  if (fd_ >= 0) USOCK_CLOSE(S(fd_));
  fd_ = -1;
}

bool UdpSocket::send(const std::string& d) {
  if (fd_ < 0 || peer_.empty()) return false;
  return sendTo(d, peer_);
}

bool UdpSocket::sendTo(const std::string& d, const std::string& to) {
  if (fd_ < 0 || to.size() != sizeof(sockaddr_in)) return false;
  return ::sendto(S(fd_), d.data(), static_cast<int>(d.size()), 0, reinterpret_cast<const sockaddr*>(to.data()),
                  static_cast<int>(to.size())) == static_cast<int>(d.size());
}

bool UdpSocket::receiveFrom(std::string& out, std::string& from) {
  if (fd_ < 0) return false;
  char buf[2048];
  sockaddr_in a{};
#ifdef _WIN32
  int alen = sizeof a;
#else
  socklen_t alen = sizeof a;
#endif
  const auto n = ::recvfrom(S(fd_), buf, sizeof buf, 0, reinterpret_cast<sockaddr*>(&a), &alen);
  if (n <= 0) return false;
  out.assign(buf, static_cast<size_t>(n));
  from.assign(reinterpret_cast<const char*>(&a), sizeof a);
  return true;
}

bool UdpSocket::receive(std::string& out) {
  std::string from;
  while (receiveFrom(out, from)) {
    if (peer_.empty() || from == peer_) return true;
    // Compare address and port only (padding may differ).
    const auto* f = reinterpret_cast<const sockaddr_in*>(from.data());
    const auto* p = reinterpret_cast<const sockaddr_in*>(peer_.data());
    if (f->sin_port == p->sin_port && f->sin_addr.s_addr == p->sin_addr.s_addr) return true;
  }
  return false;
}

void UdpSocket::wait(int ms) {
  if (fd_ < 0) return;
#ifdef _WIN32
  fd_set r;
  FD_ZERO(&r);
  FD_SET(S(fd_), &r);
  timeval tv{ms / 1000, (ms % 1000) * 1000};
  select(0, &r, nullptr, nullptr, &tv);
#else
  pollfd p{S(fd_), POLLIN, 0};
  ::poll(&p, 1, ms);
#endif
}

uint16_t UdpSocket::localPort() const {
  if (fd_ < 0) return 0;
  sockaddr_in a{};
#ifdef _WIN32
  int alen = sizeof a;
#else
  socklen_t alen = sizeof a;
#endif
  if (getsockname(S(fd_), reinterpret_cast<sockaddr*>(&a), &alen) != 0) return 0;
  return ntohs(a.sin_port);
}

}  // namespace graal3d
