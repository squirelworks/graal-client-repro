// A fake gen-5 game server on loopback, for the session and program tests.
#pragma once

#include "../net/connection.hpp"
#include "../net/gtypes.hpp"

#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace QuattroTest {

using namespace Quattro::Net;

// A fake game server: one connection, gen-5 both ways.
struct FakeServer {
  Socket listener;
  Socket conn;
  uint8_t key = 0;
  std::string login_line;
  std::vector<std::pair<int, std::string>> got;
  std::unique_ptr<FrameEncoder> enc;
  std::unique_ptr<FrameDecoder> dec;
  std::string buf;
  bool have_login = false;
  // A server for a 5.12 profile steps packed frames as 5.12 does, and the
  // frame types the client used are kept.
  bool round_down = false;
  std::vector<int> frame_types;

  bool start() { return listener.listen_loopback(); }
  uint16_t port() const { return listener.local_port(); }

  // Pumps the socket; the first frame is the client's login frame.
  void pump() {
    std::string in;
    conn.poll(in);
    buf += in;
    if (!have_login && buf.size() >= 2) {
      size_t len = (static_cast<unsigned char>(buf[0]) << 8) | static_cast<unsigned char>(buf[1]);
      if (buf.size() < 2 + len) return;
      std::string plain;
      if (!zlib_decompress(std::string_view(buf).substr(2, len), plain)) return;
      buf.erase(0, 2 + len);
      have_login = true;
      // "%" + key + line + "\n"
      if (plain.size() >= 3 && plain[0] == '%') {
        key = static_cast<uint8_t>((static_cast<unsigned char>(plain[1]) - 32) & 0x7F);
        login_line = plain.substr(2, plain.size() - 3);
      }
      enc = std::make_unique<FrameEncoder>(key, false);
      dec = std::make_unique<FrameDecoder>(key, [this](int id, std::string_view b) { got.emplace_back(id, std::string(b)); });
      enc->set_packed_round_down(round_down);
      enc->set_compress_always(round_down);
      dec->set_packed_round_down(round_down);
    }
    if (have_login && !buf.empty()) {
      // The compression byte of each whole frame in the buffer.
      for (size_t p = 0; p + 2 < buf.size();) {
        size_t len = (static_cast<unsigned char>(buf[p]) << 8) | static_cast<unsigned char>(buf[p + 1]);
        if (len == 0xFFFF || p + 2 + len > buf.size()) break;
        frame_types.push_back(static_cast<unsigned char>(buf[p + 2]));
        p += 2 + len;
      }
      dec->feed(buf);
      buf.clear();
    }
  }

  void send(const std::string& plain) { conn.send(enc->encode(plain)); }

  bool saw(int id, const std::string& body) const {
    for (auto& [i, b] : got)
      if (i == id && b == body) return true;
    return false;
  }
};

}  // namespace QuattroTest
