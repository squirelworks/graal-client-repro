#include "seclogin.hpp"

#include "seccrypto.hpp"

#include <cctype>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <system_error>
#include <vector>

namespace fs = std::filesystem;

namespace Quattro::Net::Sec {

std::string pin_dir_override;

namespace {

const char kSigContext[] = "seihai-login-v1/server-hello";  // and a 0 byte
const char kKeyInfo[] = "seihai-login-v1/c2s key";
constexpr size_t kKeyB64 = 43;
constexpr size_t kSigB64 = 86;
constexpr size_t kPadTo = 64;

std::string env(const char* name) {
  const char* v = std::getenv(name);
  return v ? std::string(v) : std::string();
}

std::string trim(std::string_view s) {
  size_t a = 0, b = s.size();
  while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
  while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
  return std::string(s.substr(a, b - a));
}

std::string u16le(size_t n) {
  std::string s;
  s.push_back(static_cast<char>(n & 0xFF));
  s.push_back(static_cast<char>((n >> 8) & 0xFF));
  return s;
}

std::string join(const std::string& dir, const char* name) { return (fs::path(dir) / name).string(); }

// Missing files are empty; an existing non-file or an I/O error is a failure.
bool try_read_lines(const std::string& path, std::vector<std::string>& lines) {
  lines.clear();
  std::error_code ec;
  fs::file_status st = fs::status(path, ec);
  if (ec && ec != std::errc::no_such_file_or_directory) {
    // A parent that is a file, for one, is not a first use.
    if (ec == std::errc::not_a_directory) return false;
  }
  if (!fs::exists(st)) {
    // An ancestor that exists and is not a folder is a failure too.
    fs::path p = fs::path(path).parent_path();
    while (!p.empty()) {
      std::error_code e2;
      fs::file_status ps = fs::status(p, e2);
      if (fs::exists(ps)) return fs::is_directory(ps);
      fs::path up = p.parent_path();
      if (up == p) break;
      p = up;
    }
    return true;
  }
  if (!fs::is_regular_file(st)) return false;
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  std::string line;
  while (std::getline(f, line)) {
    std::string t = trim(line);
    if (t.empty() || t[0] == '#') continue;
    lines.push_back(t);
  }
  return !f.bad();
}

std::vector<std::string> read_lines(const std::string& path) {
  std::vector<std::string> l;
  try_read_lines(path, l);
  return l;
}

bool append_line(const std::string& path, const std::string& line) {
  std::error_code ec;
  fs::path dir = fs::path(path).parent_path();
  if (!dir.empty()) {
    fs::create_directories(dir, ec);
    if (ec || !fs::is_directory(dir, ec)) return false;
  }
  std::ofstream f(path, std::ios::binary | std::ios::app);
  if (!f) return false;
  f << line << '\n';
  f.close();
  return !f.fail();
}

bool split_pin(const std::string& line, std::string& server, std::string& key) {
  size_t p = line.find(' ');
  if (p == std::string::npos) p = line.find('\t');
  if (p == std::string::npos) return false;
  server = line.substr(0, p);
  return decode_key(std::string_view(line).substr(p + 1), key);
}

}  // namespace

bool parse_mode(std::string_view s, Mode& out) {
  std::string l = trim(s);
  for (char& c : l) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  if (l == "off") out = Mode::Off;
  else if (l == "auto") out = Mode::Auto;
  else if (l == "required") out = Mode::Required;
  else return false;
  return true;
}

const char* mode_name(Mode m) {
  switch (m) {
    case Mode::Off: return "off";
    case Mode::Required: return "required";
    default: return "auto";
  }
}

std::string key_fingerprint(std::string_view key) { return "SHA256:" + b64_encode(sha256(key)); }

bool decode_key(std::string_view text, std::string& key) {
  if (!b64_decode(trim(text), key) || key.size() != 32) {
    key.clear();
    return false;
  }
  return true;
}

std::string pin_dir() {
  if (!pin_dir_override.empty()) return pin_dir_override;
  std::string d = env("GRAAL_SECURE_DIR");
  if (!d.empty()) return d;
#ifdef _WIN32
  d = env("APPDATA");
  if (d.empty()) d = ".";
  return join(d, "graal-delphi");
#else
  d = env("XDG_CONFIG_HOME");
  if (d.empty()) {
    d = env("HOME");
    d = d.empty() ? std::string(".") : join(d, ".config");
  }
  return join(d, "graal-delphi");
#endif
}

std::string pin_file() { return join(pin_dir(), "known_servers.txt"); }
std::string refused_file() { return join(pin_dir(), "refused_servers.txt"); }

PinResult pin_check(const std::string& server, const std::string& key, std::string& pinned) {
  pinned.clear();
  std::vector<std::string> lines;
  if (!try_read_lines(pin_file(), lines)) return PinResult::Unavailable;
  for (auto& l : lines) {
    std::string s, k;
    if (split_pin(l, s, k) && s == server) {
      pinned = k;
      return k == key ? PinResult::Matches : PinResult::Mismatch;
    }
  }
  return PinResult::Unknown;
}

bool is_pinned(const std::string& server) {
  std::string pinned;
  // An unavailable trust store must never enable a clear-text fallback.
  return pin_check(server, "", pinned) != PinResult::Unknown;
}

bool pin_append(const std::string& server, const std::string& key) {
  if (!append_line(pin_file(), server + " " + b64_encode(key))) return false;
  std::string pinned;
  return pin_check(server, key, pinned) == PinResult::Matches;
}

bool was_refused(const std::string& server) {
  for (auto& l : read_lines(refused_file()))
    if (l == server) return true;
  return false;
}

void remember_refused(const std::string& server) {
  if (!was_refused(server)) append_line(refused_file(), server);
}

Mode configured_mode() {
  std::string w = env("GRAAL_SECURE_LOGIN");
  if (w.empty()) {
    auto lines = read_lines(join(pin_dir(), "secure_login.txt"));
    if (!lines.empty()) {
      w = lines[0];
      size_t sp = w.find(' ');
      if (sp != std::string::npos) w.resize(sp);
    }
  }
  Mode m = Mode::Off;
  if (!parse_mode(w, m)) m = Mode::Off;
  return m;
}

bool should_probe(Mode m, const std::string& server) {
  switch (m) {
    case Mode::Off: return false;
    case Mode::Required: return true;
    default: return is_pinned(server) || !was_refused(server);
  }
}

bool may_fall_back(Mode m, const std::string& server) { return m == Mode::Auto && !is_pinned(server); }

// ---- Handshake ----

bool Handshake::start(const std::string& prefix, const std::string& inner, const std::string& suffix) {
  std::string s;
  if (!random_bytes(32, s)) {
    error_ = "no random bytes from the system";
    return false;
  }
  return start_with(prefix, inner, suffix, s);
}

bool Handshake::start_with(const std::string& prefix, const std::string& inner, const std::string& suffix,
                           const std::string& secret) {
  error_.clear();
  server_key_.clear();
  th_.clear();
  key_.clear();
  if (inner.size() != 8) {
    error_ = "inner token is not 8 bytes";
    return false;
  }
  if (secret.size() != 32) {
    error_ = "secret is not 32 bytes";
    return false;
  }
  secret_ = secret;
  hello_ = prefix + kToken + inner + b64_encode(x25519_base(secret_)) + suffix;
  return true;
}

bool Handshake::finish(std::string_view s1) {
  error_.clear();
  std::string_view l = s1;
  if (!l.empty() && l.back() == '\n') l.remove_suffix(1);
  if (l.substr(0, 8) != kToken) {
    error_ = "server hello does not start with the token";
    return false;
  }
  if (hello_.empty()) {
    error_ = "no hello was sent";
    return false;
  }
  std::string_view rest = l.substr(8);
  if (rest.size() != kKeyB64 * 2 + kSigB64) {
    error_ = "server hello has the wrong length";
    return false;
  }
  std::string eph, id, sig;
  if (!b64_decode(rest.substr(0, kKeyB64), eph) || eph.size() != 32 ||
      !b64_decode(rest.substr(kKeyB64, kKeyB64), id) || id.size() != 32 ||
      !b64_decode(rest.substr(kKeyB64 * 2, kSigB64), sig) || sig.size() != 64) {
    error_ = "bad base64 in the server hello";
    return false;
  }
  std::string signed_part = std::string(kSigContext, sizeof kSigContext) + u16le(hello_.size()) + hello_ + eph + id;
  if (!ed25519_verify(sig, signed_part, id)) {
    error_ = "the server's signature on the secure login does not verify";
    return false;
  }
  std::string shared = x25519(secret_, eph);
  if (is_zero32(shared)) {
    error_ = "the key exchange gave a weak shared secret";
    return false;
  }
  th_ = sha256(signed_part + sig);
  key_ = hkdf_sha256(th_, shared, kKeyInfo, 32);
  server_key_ = id;
  secret_.assign(32, '\0');
  return true;
}

std::string Handshake::seal(const std::string& tail) {
  if (key_.empty() || tail.size() > kMaxTail) return std::string();
  std::string p = u16le(tail.size()) + tail;
  if (p.size() % kPadTo) p.append(kPadTo - p.size() % kPadTo, '\0');
  std::string out = std::string(kToken) + b64_encode(aead_seal(key_, std::string(12, '\0'), th_, p));
  key_.clear();  // the key is used once
  return out;
}

bool accept_server(Handshake& h, std::string_view s1, const std::string& server, const std::string& given_key,
                   const NoteFn& note, std::string& why) {
  why.clear();
  if (!h.finish(s1)) {
    why = h.error();
    return false;
  }
  if (!given_key.empty()) {
    std::string want;
    if (!decode_key(given_key, want)) {
      why = "the given server key is not a key";
      return false;
    }
    if (want != h.server_key()) {
      why = "server key " + key_fingerprint(h.server_key()) + " is not the given key " + key_fingerprint(want) +
            "; not sending the password";
      return false;
    }
    return true;
  }
  std::string pinned;
  switch (pin_check(server, h.server_key(), pinned)) {
    case PinResult::Matches:
      return true;
    case PinResult::Unknown:
      if (!pin_append(server, h.server_key())) {
        why = "cannot save the server key for " + server + " in " + pin_file() + "; not sending the password";
        return false;
      }
      if (note)
        note("secure login: trusting " + server + " on first use, key " + key_fingerprint(h.server_key()) +
             " (saved in " + pin_file() + ")");
      return true;
    case PinResult::Mismatch:
      why = "server key " + key_fingerprint(h.server_key()) + " for " + server + " is not the pinned key " +
            key_fingerprint(pinned) + " in " + pin_file() + "; not sending the password";
      return false;
    case PinResult::Unavailable:
      why = "cannot read the server key file " + pin_file() + "; not sending the password";
      return false;
  }
  return false;
}

// ---- Session ----

Session::Session() {
  now_ms = [] {
    return static_cast<int64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                    std::chrono::steady_clock::now().time_since_epoch())
                                    .count());
  };
}

void Session::reset(const std::string& server) {
  server_ = server;
  state = State::None;
  why.clear();
  tail_.clear();
}

bool Session::want() const { return !force_classic && should_probe(mode, server_); }

bool Session::start(const std::string& prefix, const std::string& inner, const std::string& suffix,
                    const std::string& tail, std::string& c1) {
  c1.clear();
  if (tail.size() > kMaxTail || !hs_.start(prefix, inner, suffix)) {
    state = State::Failed;
    why = hs_.error().empty() ? std::string("the login is too long to seal") : hs_.error();
    return false;
  }
  tail_ = tail;
  state = State::AwaitS1;
  start_ms_ = now_ms();
  c1 = hs_.hello();
  if (note) note("secure login: SEI00001 hello sent (inner " + inner + ")");
  return true;
}

bool Session::answer(std::string_view plain, std::string& c2) {
  c2.clear();
  std::string_view l = plain;
  size_t nl = l.find('\n');
  if (nl != std::string_view::npos) l = l.substr(0, nl);
  if (l.substr(0, 8) != kToken) {
    state = State::Refused;
    why = l.empty() ? std::string() : std::string(l.substr(1));
    if (note) note("secure login refused: " + why);
    tail_.clear();
    return false;
  }
  std::string w;
  if (!accept_server(hs_, l, server_, server_key, note, w)) {
    state = State::Failed;
    why = w;
    tail_.clear();
    return false;
  }
  c2 = hs_.seal(tail_);
  tail_.clear();
  state = State::Done;
  if (note) note("secure login: server key " + key_fingerprint(hs_.server_key()) + " verified; login sealed");
  return true;
}

bool Session::check(bool connected) {
  if (state != State::AwaitS1) return false;
  if (!connected) {
    state = State::Refused;
    if (why.empty()) why = "the server closed the link";
    return false;
  }
  if (now_ms() - start_ms_ > kWaitMs) {
    state = State::NoAnswer;
    why = "the server did not answer the secure login within 5 s (it may not support SEI00001)";
    return true;
  }
  return false;
}

void Session::finish() {
  state = State::None;
  tail_.clear();
}

}  // namespace Quattro::Net::Sec
