// A non-blocking UDP socket for the 3D link: POSIX sockets on Linux and
// macOS, Winsock on Windows. Polled from runGraal3DEngine.
#pragma once

#include <cstdint>
#include <string>

namespace graal3d {

class UdpSocket {
 public:
  UdpSocket() = default;
  ~UdpSocket();
  UdpSocket(const UdpSocket&) = delete;
  UdpSocket& operator=(const UdpSocket&) = delete;

  // Binds a local port (0 picks one) on all addresses, or on loopback.
  bool open(uint16_t localPort = 0, bool loopbackOnly = false);
  // The peer every send goes to and the only one receive accepts.
  bool setPeer(const std::string& host, uint16_t port);
  void close();
  bool isOpen() const { return fd_ >= 0; }

  bool send(const std::string& datagram);
  // One datagram from the peer, if one is waiting. Datagrams from other
  // addresses are dropped.
  bool receive(std::string& out);
  // Server side for tests: one datagram from anyone; `from` says who, for
  // sendTo.
  bool receiveFrom(std::string& out, std::string& from);
  bool sendTo(const std::string& datagram, const std::string& to);
  // Waits up to `ms` for a datagram.
  void wait(int ms);
  uint16_t localPort() const;

 private:
  long long fd_ = -1;
  std::string peer_;  // the peer's sockaddr bytes
};

}  // namespace graal3d
