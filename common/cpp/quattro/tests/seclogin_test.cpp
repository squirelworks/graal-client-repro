// The Seihai secure login (SEI00001) in the Quattro program: every primitive
// against its RFC vectors, the handshake against a stand-in server written
// from the spec, the pins, and whole logins on loopback (secure, auto's
// fallback, required's stop, a key mismatch).
#include "../net/connection.hpp"
#include "../net/gtypes.hpp"
#include "../net/seccrypto.hpp"
#include "../net/seclogin.hpp"
#include "check.hpp"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>

using namespace Quattro::Net;
namespace fs = std::filesystem;

namespace {

std::string unhex(const std::string& h) {
  std::string out;
  for (size_t i = 0; i + 1 < h.size(); i += 2) out.push_back(static_cast<char>(std::stoi(h.substr(i, 2), nullptr, 16)));
  return out;
}

std::string hex(const std::string& s) {
  static const char* d = "0123456789abcdef";
  std::string out;
  for (unsigned char c : s) {
    out.push_back(d[c >> 4]);
    out.push_back(d[c & 15]);
  }
  return out;
}

void test_vectors() {
  using namespace Sec;
  CHECK(hex(sha256("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  CHECK(hex(sha256("")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  CHECK(hex(sha256(std::string(1000000, 'a'))) ==
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
  CHECK(hex(sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")) ==
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  CHECK(hex(sha512("abc")) ==
        "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd"
        "454d4423643ce80e2a9ac94fa54ca49f");
  CHECK(hex(sha512("")) ==
        "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f"
        "63b931bd47417a81a538327af927da3e");
  CHECK(hex(hmac_sha256(std::string(20, '\x0b'), "Hi There")) ==
        "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
  CHECK(hex(hmac_sha256("Jefe", "what do ya want for nothing?")) ==
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
  CHECK(hex(hkdf_sha256(unhex("000102030405060708090a0b0c"), std::string(22, '\x0b'),
                        unhex("f0f1f2f3f4f5f6f7f8f9"), 42)) ==
        "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865");

  CHECK(hex(x25519(unhex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
                   unhex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"))) ==
        "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552");
  std::string alice = unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
  std::string bob = unhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
  CHECK(hex(x25519_base(alice)) == "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a");
  CHECK(hex(x25519_base(bob)) == "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f");
  CHECK(hex(x25519(alice, x25519_base(bob))) ==
        "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742");
  CHECK(is_zero32(x25519(alice, std::string(32, '\0'))));

  std::string seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
  std::string pk = ed25519_public_key(seed);
  CHECK(hex(pk) == "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
  std::string sig = ed25519_sign("", seed);
  CHECK(hex(sig) ==
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46b"
        "d25bf5f0595bbe24655141438e7a100b");
  CHECK(ed25519_verify(sig, "", pk));
  std::string seed2 = unhex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb");
  std::string sig2 = ed25519_sign(std::string(1, '\x72'), seed2);
  CHECK(hex(sig2) ==
        "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c"
        "387b2eaeb4302aeeb00d291612bb0c00");
  CHECK(ed25519_verify(sig2, std::string(1, '\x72'), ed25519_public_key(seed2)));
  CHECK(!ed25519_verify(sig2, std::string(1, '\x73'), ed25519_public_key(seed2)));
  std::string bad = sig;
  bad[10] ^= 1;
  CHECK(!ed25519_verify(bad, "", pk));
  // S = S + L is rejected (malleability).
  std::string sl = sig;
  {
    static const unsigned char L[32] = {0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7,
                                        0xa2, 0xde, 0xf9, 0xde, 0x14, 0,    0,    0,    0,    0,    0,
                                        0,    0,    0,    0,    0,    0,    0,    0,    0,    0x10};
    int carry = 0;
    for (int i = 0; i < 32; ++i) {
      int v = static_cast<unsigned char>(sl[32 + i]) + L[i] + carry;
      sl[32 + i] = static_cast<char>(v & 0xFF);
      carry = v >> 8;
    }
  }
  CHECK(!ed25519_verify(sl, "", pk));
  // A small-order public key (the identity) is rejected.
  std::string ident(32, '\0');
  ident[0] = 1;
  CHECK(!ed25519_verify(sig, "", ident));

  CHECK(hex(poly1305_mac(unhex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"),
                         "Cryptographic Forum Research Group")) == "a8061dc1305136c6c22b8baf0c0127a9");
  std::string key = unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f");
  std::string nonce = unhex("070000004041424344454647");
  std::string aad = unhex("50515253c0c1c2c3c4c5c6c7");
  std::string plain =
      "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen "
      "would be it.";
  std::string sealed = aead_seal(key, nonce, aad, plain);
  CHECK(sealed.size() == plain.size() + 16);
  CHECK(hex(sealed.substr(0, 16)) == "d31a8d34648e60db7b86afbc53ef7ec2");
  CHECK(hex(sealed.substr(sealed.size() - 16)) == "1ae10b594f09e26a7e902ecbd0600691");
  std::string opened;
  CHECK(aead_open(key, nonce, aad, sealed, opened) && opened == plain);
  sealed[3] ^= 1;
  CHECK(!aead_open(key, nonce, aad, sealed, opened));

  CHECK(b64_encode("") == "" && b64_encode("f") == "Zg" && b64_encode("fo") == "Zm8" && b64_encode("foo") == "Zm9v");
  std::string d;
  CHECK(b64_decode("Zm9vYg", d) && d == "foob");
  CHECK(b64_decode("Zm9vYg==", d) && d == "foob");
  CHECK(!b64_decode("Zm9vYh", d));  // non-zero trailing bits
  CHECK(!b64_decode("Zm9v!", d));
  CHECK(!b64_decode("Z", d));
  std::string r1, r2;
  CHECK(random_bytes(32, r1) && random_bytes(32, r2) && r1.size() == 32 && r1 != r2);
}

// ---- a server side, from the spec ----

const char* kServerSeed = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
const char* kServerEph = "a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf";

struct StandIn {
  std::string seed = unhex(kServerSeed);
  std::string th, key;

  static std::string u16(size_t n) { return std::string{static_cast<char>(n & 0xFF), static_cast<char>(n >> 8)}; }

  // S1 for C1 (no line feed); prefix_len bytes come before the token.
  std::string hello(const std::string& c1, size_t prefix_len) {
    using namespace Sec;
    std::string client_pub;
    b64_decode(c1.substr(prefix_len + 16, 43), client_pub);
    std::string eph = x25519_base(unhex(kServerEph));
    std::string id = ed25519_public_key(seed);
    std::string signed_part = std::string("seihai-login-v1/server-hello") + '\0' + u16(c1.size()) + c1 + eph + id;
    std::string sig = ed25519_sign(signed_part, seed);
    th = sha256(signed_part + sig);
    key = hkdf_sha256(th, x25519(unhex(kServerEph), client_pub), "seihai-login-v1/c2s key", 32);
    return "SEI00001" + b64_encode(eph) + b64_encode(id) + b64_encode(sig);
  }

  bool open(const std::string& c2, std::string& tail) {
    using namespace Sec;
    if (c2.substr(0, 8) != "SEI00001") return false;
    std::string ct, p;
    if (!b64_decode(c2.substr(8), ct)) return false;
    if (!aead_open(key, std::string(12, '\0'), th, ct, p)) return false;
    if (p.size() % 64) return false;
    size_t n = static_cast<unsigned char>(p[0]) | static_cast<unsigned char>(p[1]) << 8;
    for (size_t i = n + 2; i < p.size(); ++i)
      if (p[i]) return false;
    tail = p.substr(2, n);
    return true;
  }
};

// The fixed vector seihai-gserver-v2's tests carry (made separately from
// the document, in Python): client secret 0x80..0x9f, inner GNW28015.
void test_fixed_vector() {
  using namespace Sec;
  std::string secret;
  for (int i = 0; i < 32; ++i) secret.push_back(static_cast<char>(0x80 + i));
  Handshake h;
  CHECK(h.start_with("%a", "GNW28015", "", secret));
  CHECK(h.hello() == "%aSEI00001GNW28015ST6C/HRGSlkmiBdiPSBTxeuOLMSpiLT+4XnsawENUx0");
  CHECK(h.finish(
      "SEI00001eaYx7t4b+cmPEgMs3q3Q56B5OY/HhriMyEbsia+FpRoA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg7zJvV7qQwbY7KXGIQCk9"
      "6lPo4Yz5k+hwUWN7yoAwyQvBbQYKvXjC95DPSXczo38vlSw7jgbWAVpcA8syQbicBw"));
  CHECK(hex(h.server_key()) == "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8");
  CHECK(key_fingerprint(h.server_key()) == "SHA256:Vkdap1RjR0wChd9dvyvKtz2mUTWIOem3dIGy6rEHcIw");
  CHECK(h.seal("%test1%labpw") ==
        "SEI00001D9yUpUUI0R6VgG1QcRbQ5LtnZZDUOCJGnpXvFnAuE22eNVszliBIRzULlkn3lIeZLgFQLYiFyNuE5907zEQReQOFOsIkzAljPbqnfi"
        "ME1Ok");
}

void test_handshake() {
  using namespace Sec;
  Handshake h;
  std::string secret = unhex("c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf");
  CHECK(h.start_with("%!", "G3D0511C", "", secret));
  CHECK(h.hello().substr(0, 18) == "%!SEI00001G3D0511C");
  CHECK(h.hello().size() == 2 + 8 + 8 + 43);
  StandIn srv;
  std::string s1 = srv.hello(h.hello(), 2);
  CHECK(s1.size() == 8 + 43 + 43 + 86);
  CHECK(h.finish(s1 + "\n"));
  CHECK(h.server_key() == ed25519_public_key(srv.seed));
  std::string c2 = h.seal("tail bytes");
  std::string tail;
  CHECK(srv.open(c2, tail) && tail == "tail bytes");
  CHECK(h.seal("again").empty());  // the key is used once

  // A tampered S1 does not verify.
  Handshake h2;
  CHECK(h2.start_with("%!", "G3D0511C", "", secret));
  std::string s1b = srv.hello(h2.hello(), 2);
  s1b[20] = s1b[20] == 'A' ? 'B' : 'A';
  CHECK(!h2.finish(s1b));
  CHECK(!h2.finish("SEI00001short"));
  CHECK(!h2.finish("nope"));
  Handshake h3;
  CHECK(!h3.start_with("%!", "SHORT", "", secret));
}

std::string g_dir;

void fresh_dir() {
  std::error_code ec;
  fs::remove_all(g_dir, ec);
  fs::create_directories(g_dir, ec);
  Sec::pin_dir_override = g_dir;
}

void test_pins() {
  using namespace Sec;
  fresh_dir();
  std::string k1(32, 'a'), k2(32, 'b'), pinned;
  CHECK(pin_check("h:1", k1, pinned) == PinResult::Unknown);
  CHECK(!is_pinned("h:1"));
  CHECK(pin_append("h:1", k1));
  CHECK(pin_check("h:1", k1, pinned) == PinResult::Matches);
  CHECK(pin_check("h:1", k2, pinned) == PinResult::Mismatch && pinned == k1);
  CHECK(is_pinned("h:1"));
  CHECK(!was_refused("h:2"));
  remember_refused("h:2");
  remember_refused("h:2");
  CHECK(was_refused("h:2"));
  CHECK(!should_probe(Mode::Off, "h:3"));
  CHECK(should_probe(Mode::Required, "h:2"));
  CHECK(!should_probe(Mode::Auto, "h:2"));
  CHECK(should_probe(Mode::Auto, "h:3"));
  CHECK(may_fall_back(Mode::Auto, "h:3"));
  CHECK(!may_fall_back(Mode::Auto, "h:1"));  // pinned: never in the clear again
  CHECK(!may_fall_back(Mode::Required, "h:3"));
  // The same line form as the Pascal clients and Seihai's own file.
  std::ifstream f(pin_file());
  std::string line;
  std::getline(f, line);
  CHECK(line == "h:1 " + b64_encode(k1));
  Mode m;
  CHECK(parse_mode(" Auto ", m) && m == Mode::Auto);
  CHECK(parse_mode("required", m) && m == Mode::Required);
  CHECK(!parse_mode("maybe", m));
  {
    std::ofstream s(g_dir + "/secure_login.txt");
    s << "# comment\nrequired please\n";
  }
#ifdef _WIN32
  _putenv("GRAAL_SECURE_LOGIN=");
#else
  unsetenv("GRAAL_SECURE_LOGIN");
#endif
  CHECK(configured_mode() == Mode::Required);
  // A folder where the pin file should be: the store is unavailable, so it
  // counts as pinned and auto never falls back to the clear login.
  fresh_dir();
  fs::create_directories(g_dir + "/known_servers.txt");
  CHECK(pin_check("h:9", k1, pinned) == PinResult::Unavailable);
  CHECK(is_pinned("h:9"));
  fresh_dir();
}

// ---- whole logins on loopback ----

// A server that speaks the secure login (or refuses it) and then gen-5.
struct SecServer {
  enum Kind { Secure, Refuse, Silent } kind = Secure;
  Socket listener, conn;
  std::string buf;
  int frames = 0;  // plain login frames seen
  std::string c1, c2_tail, classic_line;
  uint8_t key = 0;
  std::unique_ptr<FrameDecoder> dec;
  std::vector<std::pair<int, std::string>> got;
  StandIn stand;
  int accepts = 0;

  bool start() { return listener.listen_loopback(); }

  static std::string plain_frame(const std::string& plain) {
    std::string z = zlib_compress(plain);
    return std::string{static_cast<char>(z.size() >> 8), static_cast<char>(z.size() & 0xFF)} + z;
  }

  void pump() {
    if (!conn.connected()) {
      if (conn.accept_from(listener, 0)) {
        ++accepts;
        buf.clear();
        frames = 0;
        dec.reset();
      }
      return;
    }
    std::string in;
    conn.poll(in);
    buf += in;
    while (!dec && buf.size() >= 2) {
      size_t len = (static_cast<unsigned char>(buf[0]) << 8) | static_cast<unsigned char>(buf[1]);
      if (buf.size() < 2 + len) return;
      std::string plain;
      if (!zlib_decompress(std::string_view(buf).substr(2, len), plain)) return;
      buf.erase(0, 2 + len);
      ++frames;
      std::string line = plain.substr(0, plain.find('\n'));
      if (line.size() > 10 && line.compare(2, 8, "SEI00001") == 0 && frames == 1) {
        c1 = line;
        key = static_cast<uint8_t>((static_cast<unsigned char>(line[1]) - 32) & 0x7F);
        if (kind == Secure) conn.send(plain_frame(stand.hello(c1, 2) + "\n"));
        if (kind == Refuse) {
          conn.send(plain_frame(std::string(1, char(16 + 32)) + "unknown token\n"));
          conn.close();
          return;
        }
        continue;
      }
      if (frames == 2 && !c1.empty()) {
        stand.open(line, c2_tail);
      } else {
        key = static_cast<uint8_t>((static_cast<unsigned char>(line[1]) - 32) & 0x7F);
        classic_line = line.substr(2);
      }
      dec = std::make_unique<FrameDecoder>(key, [this](int id, std::string_view b) { got.emplace_back(id, std::string(b)); });
    }
    if (dec && !buf.empty()) {
      dec->feed(buf);
      buf.clear();
    }
  }
};

template <typename Pred>
bool run(Session& s, SecServer& srv, Pred done, int ms = 4000) {
  auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(ms);
  while (std::chrono::steady_clock::now() < end) {
    s.tick();
    srv.pump();
    if (done()) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  }
  return false;
}

void test_secure_login() {
  const BuildProfile* prof = find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  fresh_dir();
  SecServer srv;
  CHECK(srv.start());
  std::string disconnected, notes;
  Session::Events ev;
  ev.disconnected = [&](const std::string& w) { disconnected = w; };
  ev.note = [&](const std::string& l) { notes += l + "\n"; };
  Session s(*prof, ev);
  s.set_secure(Sec::Mode::Required);
  CHECK(s.start("127.0.0.1", srv.listener.local_port(), "acct", "pw secret"));
  CHECK(run(s, srv, [&] { return !srv.got.empty(); }));
  CHECK(srv.c1.substr(2, 16) == "SEI00001" + prof->token);
  // The sealed tail is the classic line after the token, byte for byte.
  CHECK(srv.c2_tail == s.connection().login_tail("acct", "pw secret"));
  CHECK(srv.c2_tail.find("pw secret") != std::string::npos);
  CHECK(srv.classic_line.empty());
  CHECK(!srv.got.empty() && srv.got[0].first == 37 && srv.got[0].second == "English");
  CHECK(s.connection().sec().state == Sec::State::Done);
  CHECK(Sec::is_pinned("127.0.0.1:" + std::to_string(srv.listener.local_port())));
  CHECK(notes.find("trusting 127.0.0.1:") != std::string::npos);
  CHECK(disconnected.empty());
  s.connection().close();
}

void test_auto_fallback() {
  const BuildProfile* prof = find_profile("6.03r7");
  if (!prof) return;
  fresh_dir();
  SecServer srv;
  srv.kind = SecServer::Refuse;
  CHECK(srv.start());
  std::string notes;
  Session::Events ev;
  ev.note = [&](const std::string& l) { notes += l + "\n"; };
  Session s(*prof, ev);
  s.set_secure(Sec::Mode::Auto);
  CHECK(s.start("127.0.0.1", srv.listener.local_port(), "acct", "pw"));
  CHECK(run(s, srv, [&] { return !srv.classic_line.empty() && !srv.got.empty(); }));
  CHECK(srv.accepts == 2);
  CHECK(srv.classic_line == s.connection().login_line("acct", "pw").substr(1));
  CHECK(notes.find("logging in the original way") != std::string::npos);
  CHECK(Sec::was_refused("127.0.0.1:" + std::to_string(srv.listener.local_port())));
  s.connection().close();
}

void test_required_stops() {
  const BuildProfile* prof = find_profile("6.03r7");
  if (!prof) return;
  fresh_dir();
  SecServer srv;
  srv.kind = SecServer::Refuse;
  CHECK(srv.start());
  std::string disconnected;
  Session::Events ev;
  ev.disconnected = [&](const std::string& w) { disconnected = w; };
  Session s(*prof, ev);
  s.set_secure(Sec::Mode::Required);
  CHECK(s.start("127.0.0.1", srv.listener.local_port(), "acct", "pw"));
  CHECK(run(s, srv, [&] { return !disconnected.empty(); }));
  CHECK(disconnected.find("secure login") == 0);
  CHECK(srv.classic_line.empty());
  CHECK(srv.accepts == 1);
}

void test_pinned_mismatch() {
  const BuildProfile* prof = find_profile("6.03r7");
  if (!prof) return;
  fresh_dir();
  SecServer srv;
  CHECK(srv.start());
  std::string addr = "127.0.0.1:" + std::to_string(srv.listener.local_port());
  CHECK(Sec::pin_append(addr, std::string(32, 'z')));
  std::string disconnected;
  Session::Events ev;
  ev.disconnected = [&](const std::string& w) { disconnected = w; };
  Session s(*prof, ev);
  s.set_secure(Sec::Mode::Auto);  // pinned: auto must not fall back
  CHECK(s.start("127.0.0.1", srv.listener.local_port(), "acct", "pw"));
  CHECK(run(s, srv, [&] { return !disconnected.empty(); }));
  CHECK(disconnected.find("not the pinned key") != std::string::npos);
  CHECK(srv.classic_line.empty() && srv.c2_tail.empty());
}

void test_no_answer() {
  const BuildProfile* prof = find_profile("6.03r7");
  if (!prof) return;
  fresh_dir();
  SecServer srv;
  srv.kind = SecServer::Silent;
  CHECK(srv.start());
  std::string notes;
  Session::Events ev;
  ev.note = [&](const std::string& l) { notes += l + "\n"; };
  Session s(*prof, ev);
  s.set_secure(Sec::Mode::Auto);
  int64_t fake = 0;
  s.connection().sec().now_ms = [&] { return fake; };
  CHECK(s.start("127.0.0.1", srv.listener.local_port(), "acct", "pw"));
  CHECK(run(s, srv, [&] { return !srv.c1.empty(); }));
  fake = 6000;
  srv.conn.close();  // the old link goes; the client reconnects classic
  CHECK(run(s, srv, [&] { return !srv.classic_line.empty(); }));
  CHECK(notes.find("did not answer") != std::string::npos || notes.find("closed the link") != std::string::npos);
  s.connection().close();
}

void test_off_is_classic() {
  const BuildProfile* prof = find_profile("6.03r7");
  if (!prof) return;
  fresh_dir();
  SecServer srv;
  CHECK(srv.start());
  Session s(*prof, {});
  CHECK(s.start("127.0.0.1", srv.listener.local_port(), "acct", "pw"));
  CHECK(run(s, srv, [&] { return !srv.classic_line.empty(); }));
  CHECK(srv.c1.empty());
  s.connection().close();
}

}  // namespace

int main() {
  g_dir = (fs::temp_directory_path() / ("quattro-seclogin-" + std::to_string(std::rand()) + std::to_string(
                                                                    std::chrono::steady_clock::now().time_since_epoch().count())))
              .string();
  test_vectors();
  test_fixed_vector();
  test_handshake();
  test_pins();
  test_secure_login();
  test_auto_fallback();
  test_required_stops();
  test_pinned_mismatch();
  test_no_answer();
  test_off_is_classic();
  std::error_code ec;
  fs::remove_all(g_dir, ec);
  TEST_MAIN_END();
}
