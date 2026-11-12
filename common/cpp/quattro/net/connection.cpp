#include "connection.hpp"

#include "gtypes.hpp"

#include <algorithm>
#include <cctype>
#include <random>
#include <vector>

namespace Quattro::Net {

bool Connection::connect(const std::string& host, uint16_t port, uint8_t key) {
  close();
  error_.clear();
  key_ = key & 0x7F;
  if (!socket_.connect(host, port)) {
    error_ = socket_.error();
    return false;
  }
  enc_ = std::make_unique<FrameEncoder>(key_);
  dec_ = std::make_unique<FrameDecoder>(key_, [this](int id, std::string_view body) { deliver(id, body); });
  return true;
}

void Connection::close() {
  socket_.close();
  enc_.reset();
  dec_.reset();
  out_.clear();
}

std::string Connection::login_line(const std::string& account, const std::string& password) const {
  std::string line = gchar(key_) + profile_.token + gstring(account) + gstring(password) + profile_.platform;
  for (int i = 0; i < profile_.machine_fields; ++i) line += ",\"\"";
  return line;
}

void Connection::login(const std::string& account, const std::string& password, const std::string& language) {
  // The login message is id 5; the build's send set has 5 (PLI_BOMBDEL).
  queue(5, login_line(account, password));
  flush();
  send(37, language);
}

bool Connection::queue(int id, std::string_view body) {
  if (!connected()) return false;
  if (body.find('\n') != std::string_view::npos) {
    error_ = "Illegal characters in the outgoing data";
    return false;
  }
  std::string msg = gchar(static_cast<unsigned>(id)) + std::string(body) + "\n";
  if (!out_.empty() && out_.size() + msg.size() > kFlushAt) flush();
  out_ += msg;
  if (out_.size() > kDropAt) {
    error_ = "more than 256 KB queued";
    close();
    return false;
  }
  return true;
}

bool Connection::send(int id, std::string_view body) {
  if (id < 0 || id > 255 || !profile_.pli.test(static_cast<size_t>(id))) {
    if (!needs_raw_prefix(id)) return false;
  }
  if (needs_raw_prefix(id)) {
    // PLI 50 announces the next message's size, capped at 0x37FFFF
    // (v6x-clients.md). That the size counts the id byte, the body and the
    // newline is the rebuild's reading; the note does not say. GINT3 keeps
    // 21 bits, so sizes past 0x1FFFFF are not sent as one message here.
    size_t len = body.size() + 2;
    if (len > 0x1FFFFF) return false;
    if (!queue(50, gint3(static_cast<uint32_t>(len)))) return false;
    std::string msg = gchar(static_cast<unsigned>(id)) + std::string(body) + "\n";
    if (!out_.empty() && out_.size() + msg.size() > kFlushAt) flush();
    out_ += msg;
    return true;
  }
  return queue(id, body);
}

void Connection::flush() {
  if (out_.empty() || !connected() || !enc_) return;
  std::string frame = enc_->encode(out_);
  out_.clear();
  if (!socket_.send(frame)) error_ = socket_.error();
}

bool Connection::poll() {
  if (!connected()) return false;
  std::string got;
  bool alive = socket_.poll(got);
  if (!got.empty() && dec_) {
    dec_->feed(got);
    if (dec_->failed()) {
      error_ = dec_->error();
      close();
      return false;
    }
  }
  if (!alive) {
    error_ = socket_.error();
    close();
  }
  return alive;
}

void Connection::deliver(int id, std::string_view body) {
  if (id == 108 && profile_.answers_ping) {
    Reader r(body);
    unsigned sub = r.gchar();
    unsigned value = r.gshort();
    if (!r.ok()) return;
    if (sub == 0)
      send(162, "!" + gshort(std::min(value, 0x6FFFu)));
    else if (sub == 1)
      ping_value_ = value;
    return;
  }
  if (id < 0 || id > 255 || !profile_.plo.test(static_cast<size_t>(id))) {
    ++dropped_;
    return;
  }
  if (on_message_) on_message_(id, body);
}

bool parse_server_warp(std::string_view body, ServerWarp& out) {
  // Commas only: the lab's unquoted "0,Lab Server,127.0.0.1,14900" reached
  // the named host under the name "Lab Server" in every lobby build
  // (Seihai documentation/v5v6-profiles.md, from the 5.x and 6.x labs).
  std::vector<std::string> fields;
  std::string cur;
  for (char c : body) {
    if (c == ',') {
      fields.push_back(cur);
      cur.clear();
    } else {
      cur.push_back(c);
    }
  }
  fields.push_back(cur);
  if (fields.size() < 4) return false;
  out.name = fields[1];
  out.host = fields[2];
  const std::string& p = fields[3];
  if (p.empty() || p.size() > 5 || !std::all_of(p.begin(), p.end(), [](char c) { return std::isdigit(static_cast<unsigned char>(c)); }))
    return false;
  unsigned long port = std::stoul(p);
  if (port == 0 || port > 65535 || out.host.empty()) return false;
  out.port = static_cast<uint16_t>(port);
  return true;
}

Session::Session(const BuildProfile& profile, Events events)
    : profile_(profile), ev_(std::move(events)), conn_(profile) {
  next_key = [] {
    static std::mt19937 rng{std::random_device{}()};
    return static_cast<uint8_t>(rng() & 0x7F);
  };
  conn_.on_message([this](int id, std::string_view body) {
    if (id == 178) {
      ServerWarp w;
      if (parse_server_warp(body, w)) {
        warp_ = w;
        warp_pending_ = true;
      }
    }
    if (ev_.message) ev_.message(id, body);
  });
}

bool Session::open(const std::string& name, const std::string& host, uint16_t port) {
  server_name_ = name;
  server_host_ = host;
  if (ev_.connecting) ev_.connecting(name, host + ":" + std::to_string(port));
  if (!conn_.connect(host, port, next_key())) {
    if (ev_.connect_failed) ev_.connect_failed(conn_.error());
    return false;
  }
  if (ev_.connected) ev_.connected();
  conn_.login(account_, password_, language_);
  conn_.flush();
  ++logins_;
  return true;
}

bool Session::start(const std::string& host, uint16_t port, const std::string& account,
                    const std::string& password, const std::string& language) {
  account_ = account;
  password_ = password;
  language_ = language;
  logins_ = 0;
  return open("Login", host, port);
}

void Session::tick() {
  if (conn_.connected() && !conn_.poll()) {
    if (!warp_pending_ && ev_.disconnected) ev_.disconnected(conn_.error());
  }
  if (warp_pending_) {
    warp_pending_ = false;
    conn_.close();
    open(warp_.name, warp_.host, warp_.port);
    return;
  }
  conn_.flush();
}

bool Session::lobby_mode() const {
  if (server_name_.size() < 5) return false;
  std::string head = server_name_.substr(0, 5);
  for (char& c : head) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return head == "login";
}

}  // namespace Quattro::Net
