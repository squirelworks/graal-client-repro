// The client side of the Seihai secure login, version token SEI00001
// (Seihai documentation/secure-login.md, revision 1), for the Quattro
// program. Not part of any Graal client.
//
// The same protocol, modes and files as the Pascal clients' common/GSecLogin.pas,
// so a player's pins are shared between the start screen and quattro-play:
//
// - C1: the classic login prefix (type and key byte), SEI00001, the build's
//   own token and a fresh X25519 key, in the plain zlib login frame.
// - S1 (a plain zlib frame): the server's X25519 key, its Ed25519 key and a
//   signature over C1. The client checks it and the pinned key, derives one
//   key with HKDF and sends C2 in a second plain login frame: the account,
//   the password and the rest of the classic login tail sealed with
//   ChaCha20-Poly1305. The session then goes on in gen-5 as usual.
// - Modes: off (the original login, byte for byte), auto (try SEI00001,
//   fall back to the original login when the server refuses, closes or
//   says nothing for 5 s, unless its key is pinned), required (never send a
//   password in the clear).
// - Files in one per-user folder (GRAAL_SECURE_DIR, else %APPDATA%\graal-delphi
//   or $XDG_CONFIG_HOME/graal-delphi / ~/.config/graal-delphi):
//   known_servers.txt ("host:port key"), refused_servers.txt, secure_login.txt.
#pragma once

#include <cstdint>
#include <functional>
#include <string>
#include <string_view>

namespace Quattro::Net::Sec {

constexpr const char* kToken = "SEI00001";
constexpr size_t kMaxTail = 1024;
constexpr int kWaitMs = 5000;

enum class Mode { Off, Auto, Required };
enum class PinResult { Unknown, Matches, Mismatch, Unavailable };
enum class State { None, AwaitS1, Done, Refused, NoAnswer, Failed };

bool parse_mode(std::string_view s, Mode& out);
const char* mode_name(Mode m);

// "SHA256:" and the unpadded base64 of the key's SHA-256.
std::string key_fingerprint(std::string_view key);
bool decode_key(std::string_view text, std::string& key);

// Set by tests: used in place of the folder search when not empty.
extern std::string pin_dir_override;
std::string pin_dir();
std::string pin_file();
std::string refused_file();
PinResult pin_check(const std::string& server, const std::string& key, std::string& pinned);
bool is_pinned(const std::string& server);
bool pin_append(const std::string& server, const std::string& key);
bool was_refused(const std::string& server);
void remember_refused(const std::string& server);

// GRAAL_SECURE_LOGIN if set, else the first word of secure_login.txt, else off.
Mode configured_mode();

bool should_probe(Mode m, const std::string& server);
bool may_fall_back(Mode m, const std::string& server);

// One handshake, C1 to C2.
class Handshake {
 public:
  // False if the inner token is not 8 bytes or no random bytes could be read.
  bool start(const std::string& prefix, const std::string& inner, const std::string& suffix);
  bool start_with(const std::string& prefix, const std::string& inner, const std::string& suffix,
                  const std::string& secret);
  const std::string& hello() const { return hello_; }  // C1, no line feed
  // Checks S1 (the token, the lengths, the signature, a non-zero secret).
  bool finish(std::string_view s1);
  // C2 without its line feed; empty when there is no key or the tail is long.
  std::string seal(const std::string& tail);
  const std::string& server_key() const { return server_key_; }
  const std::string& error() const { return error_; }

 private:
  std::string secret_, hello_, th_, key_, server_key_, error_;
};

using NoteFn = std::function<void(const std::string&)>;

// The whole check after S1: the handshake, then the pin (a non-empty
// given_key is the only key trusted and the file is left alone).
bool accept_server(Handshake& h, std::string_view s1, const std::string& server, const std::string& given_key,
                   const NoteFn& note, std::string& why);

// One link's secure login, from the choice to probe to C2.
class Session {
 public:
  Mode mode = Mode::Off;
  std::string server_key;      // --server-key: base64, the only key trusted
  bool force_classic = false;  // the next login is the original one
  State state = State::None;
  std::string why;
  NoteFn note;
  // Milliseconds since some fixed point; tests replace it.
  std::function<int64_t()> now_ms;

  Session();
  void reset(const std::string& server);
  bool want() const;
  // C1 for the plain login frame; false (state Failed) if it cannot start.
  bool start(const std::string& prefix, const std::string& inner, const std::string& suffix,
             const std::string& tail, std::string& c1);
  bool awaiting() const { return state == State::AwaitS1; }
  // The first line of the first plain frame after C1. True with C2 to send;
  // false when the server refused (Refused) or the check failed (Failed).
  bool answer(std::string_view plain, std::string& c2);
  // Each tick: a close while waiting is a refusal, 5 s of silence no answer.
  // True when the link should be dropped.
  bool check(bool connected);
  void finish();
  const std::string& server() const { return server_; }

 private:
  Handshake hs_;
  std::string tail_, server_;
  int64_t start_ms_ = 0;
};

}  // namespace Quattro::Net::Sec
