// The Graal3D UDP link, left enabled in a 6.037 host.
//
// Stock 6.x has no UDP: its connect path opens no datagram socket
// (docs/v6-repro.md, UDP). This client keeps the 5.12 one. The link itself
// is the 5.12 repro's (common/cpp/graal3dengine, protocol 24): the same
// handshake, packets, events, ghosts and login steps. This file is only the
// glue the 5.12 library's exports.cpp is for the engine library: a UDP
// socket on one side, the host's callbacks on the other.
#pragma once

#include "link.hpp"
#include "udp.hpp"

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

namespace Frank {

class Link3D {
 public:
  struct Callbacks {
    std::function<void(const std::string&)> log;
    std::function<void(int)> login_step;
    std::function<void(const std::string&)> error;
    std::function<void(const graal3d::BigText&)> text;
  };

  explicit Link3D(Callbacks cb) : cb_(std::move(cb)) {}
  ~Link3D() { close(); }

  // Opens the socket and sends the challenge to host:port (the game
  // server's port + 1). The challenge leaves before the TCP connect, as
  // in 5.12 (torque/udp-session.md §1). False when no socket could be
  // opened or the host is not known; error() has been called.
  bool open(const std::string& host, uint16_t port, const graal3d::LinkLogin& login);
  // Reads what has arrived, runs the link's clock and sends what it has.
  void pump();
  void close();

  void event_lines(const std::string& lines);
  // Moves the own object (graal3d::Link::moveControlTo) and sends it.
  void move_control(const graal3d::Vec3& at);
  bool active() const { return link_ != nullptr; }
  const graal3d::Link* link() const { return link_.get(); }
  graal3d::Link* link() { return link_.get(); }
  uint16_t local_port() const { return socket_.localPort(); }

  static uint32_t now_ms();

 private:
  void flush();
  void settle();  // drops a failed or closed link, then tells the host

  Callbacks cb_;
  std::string failed_;
  std::unique_ptr<graal3d::Link> link_;
  graal3d::UdpSocket socket_;
};

}  // namespace Frank
