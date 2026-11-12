// A plain TCP socket, polled from the program's tick (the original's
// TSocket is a script object with connect, bind, accept and close; the game
// session uses one). POSIX sockets on Linux and macOS, Winsock on Windows.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace Quattro::Net {

class Socket {
 public:
  Socket() = default;
  ~Socket();
  Socket(const Socket&) = delete;
  Socket& operator=(const Socket&) = delete;

  // Blocking connect with a timeout, then the socket is made non-blocking.
  bool connect(const std::string& host, uint16_t port, int timeout_ms = 5000);
  void close();
  bool connected() const { return fd_ >= 0; }

  // Queues and sends what the kernel takes now; the rest is kept and sent by
  // later calls to send or poll.
  bool send(std::string_view bytes);
  // Reads whatever is available into `out` (appended). Returns false when
  // the peer closed or an error happened; the socket is then closed.
  bool poll(std::string& out);
  // Waits up to `ms` for data or writability. For tests and headless runs.
  void wait(int ms);

  const std::string& error() const { return error_; }
  size_t pending_out() const { return out_.size(); }

  // Server side for loopback tests: listen on 127.0.0.1 (port 0 picks one).
  bool listen_loopback(uint16_t port = 0);
  uint16_t local_port() const;
  bool accept_from(Socket& listener, int timeout_ms = 5000);

 private:
  bool drain();
  long long fd_ = -1;
  std::string out_;
  std::string error_;
};

}  // namespace Quattro::Net
