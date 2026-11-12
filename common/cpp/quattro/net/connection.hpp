// The game connection of the 6.01 and 6.03 programs (the original's
// TGraalConnection on a TSocket), and the session around it.
//
// Behaviour, from Graal_analysis protocol/v6x-clients.md and
// protocol/v5v6-lab-play.md:
// - Login: id 5 alone in the login frame (key, token, account, password,
//   then an unprefixed comma list: platform and machine fields), flushed by
//   itself, then id 37 (language) in the first gen-5 frame. No tamper check.
// - Outgoing data with a newline is refused ("Illegal characters in the
//   outgoing data"). Ids 93 and 163 go after id 50 with a GINT3 length.
//   The out buffer is flushed at the end of a tick, or first when it would
//   pass 0x1000 bytes.
// - Ids 100 and 108 are taken before the receive switch. 108 sub 0 is a ping
//   answered with 162 ("!" + GSHORT min(value, 0x6FFF)); sub 1 is stored.
//   Ids outside the build's set are dropped.
// - The first server is named "Login". While the name starts with "login"
//   the program is in the lobby mode. 178 (server warp, "x,name,host,port")
//   closes the link and logs in again to that server under the new name,
//   with a new key.
#pragma once

#include "gen5.hpp"
#include "profile.hpp"
#include "socket.hpp"

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

namespace Quattro::Net {

constexpr size_t kFlushAt = 0x1000;
constexpr size_t kDropAt = 0x40000;  // rebuild limit: more queued drops the link

class Connection {
 public:
  using MessageFn = std::function<void(int id, std::string_view body)>;

  explicit Connection(const BuildProfile& profile) : profile_(profile) {}

  // Opens the socket and resets both ciphers with `key` (masked to 7 bits).
  bool connect(const std::string& host, uint16_t port, uint8_t key);
  void close();
  bool connected() const { return socket_.connected(); }

  // Sends id 5 in the login frame and flushes it, then queues 37.
  void login(const std::string& account, const std::string& password, const std::string& language);

  // Queues one message. False when the build does not send `id`, when the
  // body holds a newline, or when the link is down.
  bool send(int id, std::string_view body);
  void flush();
  // Reads the socket and delivers messages. False once the link is closed.
  bool poll();

  void on_message(MessageFn fn) { on_message_ = std::move(fn); }

  const std::string& error() const { return error_; }
  uint8_t key() const { return key_; }
  uint32_t ping_value() const { return ping_value_; }  // last 108 sub 1
  size_t dropped() const { return dropped_; }          // ids outside the set
  Socket& socket() { return socket_; }

  // The login line after the id byte (key, token, account, password, list).
  std::string login_line(const std::string& account, const std::string& password) const;

 private:
  void deliver(int id, std::string_view body);
  bool queue(int id, std::string_view body);

  const BuildProfile& profile_;
  Socket socket_;
  std::unique_ptr<FrameEncoder> enc_;
  std::unique_ptr<FrameDecoder> dec_;
  std::string out_;
  MessageFn on_message_;
  std::string error_;
  uint8_t key_ = 0;
  uint32_t ping_value_ = 0;
  size_t dropped_ = 0;
};

struct ServerWarp {
  std::string name;
  std::string host;
  uint16_t port = 0;
};
// Parses a 178 body ("x,name,host,port"), split on commas only.
bool parse_server_warp(std::string_view body, ServerWarp& out);

// The session: connection, current server name, and the 178 reconnect.
class Session {
 public:
  struct Events {
    std::function<void(const std::string& name, const std::string& address)> connecting;
    std::function<void()> connected;
    std::function<void(const std::string& why)> connect_failed;
    std::function<void(int id, std::string_view body)> message;
    std::function<void(const std::string& why)> disconnected;
  };

  Session(const BuildProfile& profile, Events events);
  void set_events(Events events) { ev_ = std::move(events); }

  // Connects to the first server, named "Login", and logs in.
  bool start(const std::string& host, uint16_t port, const std::string& account,
             const std::string& password, const std::string& language = "English");
  // One tick: read, handle a pending warp, flush.
  void tick();

  bool lobby_mode() const;  // the server name starts with "login"
  const std::string& server_name() const { return server_name_; }
  const std::string& server_host() const { return server_host_; }
  Connection& connection() { return conn_; }
  int logins() const { return logins_; }

  // The key for the next connection. Tests set it; the default is random.
  std::function<uint8_t()> next_key;

 private:
  bool open(const std::string& name, const std::string& host, uint16_t port);

  const BuildProfile& profile_;
  Events ev_;
  Connection conn_;
  std::string server_name_;
  std::string server_host_;
  std::string account_, password_, language_;
  bool warp_pending_ = false;
  ServerWarp warp_;
  int logins_ = 0;
};

}  // namespace Quattro::Net
