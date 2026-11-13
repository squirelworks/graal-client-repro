// Wire integers, the gen-5 codec and the build rows, from synthetic data.
#include "../net/gen5.hpp"
#include "../net/gtypes.hpp"
#include "../net/profile.hpp"
#include "check.hpp"

#include <random>
#include <string>
#include <vector>

using namespace Quattro::Net;

namespace {

void test_gtypes() {
  CHECK(gchar(5) == "%");
  CHECK(gshort(1234) == std::string{char(32 + (1234 >> 7)), char(32 + (1234 & 0x7F))});
  const std::string all = gchar(7) + gshort(0x3FFF) + gint3(0x1FFFFF) + gint5(0x7FFFFFFFFULL) + gstring("abc") + "tail";
  Reader r(all);
  CHECK(r.gchar() == 7);
  CHECK(r.gshort() == 0x3FFF);
  CHECK(r.gint3() == 0x1FFFFF);
  CHECK(r.gint5() == 0x7FFFFFFFFULL);
  CHECK(r.gstring() == "abc");
  CHECK(r.rest() == "tail");
  CHECK(r.ok());
  const std::string short_str = gchar(9) + "ab";
  Reader past(short_str);
  CHECK(past.gstring().empty());
  CHECK(!past.ok());
  // 0xE0 bytes or more: 0xFF and the first 0xDF bytes.
  std::string long_pw(0xE5, 'x');
  std::string g = gstring(long_pw);
  CHECK(static_cast<unsigned char>(g[0]) == 0xFF);
  CHECK(g.size() == 1 + 0xDF);
}

void test_cipher() {
  // One LCG step per 4-byte group, capped at 12 (raw) or 4 (packed).
  Cipher c(0x55);
  std::string body(60, '\0');
  c.apply(body, kRaw);
  uint32_t it = kCipherSeed;
  for (int g = 0; g < 12; ++g) {
    it = it * kCipherMul + 0x55;
    for (int j = 0; j < 4; ++j)
      CHECK(static_cast<unsigned char>(body[static_cast<size_t>(g * 4 + j)]) == ((it >> (8 * j)) & 0xFF));
  }
  for (size_t p = 48; p < 60; ++p) CHECK(body[p] == 0);
  CHECK(c.iterator() == it);

  Cipher packed(0x55);
  std::string pb(40, '\0');
  packed.apply(pb, kZlib);
  for (size_t p = 16; p < 40; ++p) CHECK(pb[p] == 0);

  // A short last group still steps the iterator once.
  Cipher a(1), b(1);
  std::string five(5, '\0');
  a.apply(five, kRaw);
  std::string eight(8, '\0');
  b.apply(eight, kRaw);
  CHECK(a.iterator() == b.iterator());

  // Odd codes are not XORed and do not step.
  Cipher odd(3);
  std::string o(16, 'a');
  odd.apply(o, 3);
  CHECK(o == std::string(16, 'a'));
  CHECK(odd.iterator() == kCipherSeed);

  // The key is masked to 7 bits.
  CHECK(Cipher(0xFF).key() == 0x7F);
}

void test_compression_choice() {
  CHECK(choose_compression(0x2F, 0x40) == kRaw);
  CHECK(choose_compression(0x2F, 0x20) == kZlib);
  CHECK(choose_compression(0x30, 0x40) == kZlib);
  CHECK(choose_compression(0x1000, 0x10) == kBzip2);
}

void test_frame_length() {
  CHECK(frame_length(0x1234) == std::string("\x12\x34", 2));
  CHECK(frame_length(0xFFFE) == std::string("\xFF\xFE", 2));
  CHECK(frame_length(0xFFFF) == std::string("\xFF\xFF\x00\x00\xFF\xFF", 6));
  CHECK(frame_length(0x123456) == std::string("\xFF\xFF\x00\x12\x34\x56", 6));
}

struct Got {
  int id;
  std::string body;
};

void test_round_trip() {
  // Both ends share the key; a server encoder has no login frame.
  const uint8_t key = 0x2A;
  FrameEncoder server(key, false);
  std::vector<Got> got;
  FrameDecoder client(key, [&](int id, std::string_view b) { got.push_back({id, std::string(b)}); });

  std::string small = gchar(6) + "level.nw\n";                         // raw
  std::string medium = gchar(13) + std::string(100, 'm') + "\n";      // zlib
  std::string big;                                                     // bzip2
  for (int i = 0; i < 300; ++i) big += gchar(13) + "line " + std::to_string(i) + "\n";

  // Encode in order: each call steps the server's cipher.
  std::string wire = server.encode(small);
  wire += server.encode(medium);
  wire += server.encode(big);
  // Feed one byte at a time: frames and messages must survive any split.
  for (char c : wire) client.feed(std::string_view(&c, 1));
  CHECK(!client.failed());
  if (client.failed()) std::fprintf(stderr, "error: %s\n", client.error().c_str());
  CHECK(client.frames() == 3);
  CHECK(got.size() == 302);
  CHECK(got[0].id == 6 && got[0].body == "level.nw");
  CHECK(got[1].id == 13 && got[1].body == std::string(100, 'm'));
  CHECK(got.back().body == "line 299");
  CHECK(static_cast<unsigned char>(wire[2]) == kRaw);
}

void test_long_frame() {
  // Random bytes do not compress, so the bzip2 body passes 0xFFFF bytes and
  // takes the 6.x long length.
  std::mt19937 rng(7);
  std::string payload;
  for (int i = 0; i < 90000; ++i) {
    char c = static_cast<char>(rng() & 0xFF);
    payload.push_back(c == '\n' ? 'n' : c);
  }
  const uint8_t key = 9;
  FrameEncoder server(key, false);
  std::string frame = server.encode(gchar(102) + payload + "\n");
  CHECK(static_cast<unsigned char>(frame[0]) == 0xFF && static_cast<unsigned char>(frame[1]) == 0xFF);
  std::vector<Got> got;
  FrameDecoder client(key, [&](int id, std::string_view b) { got.push_back({id, std::string(b)}); });
  client.feed(frame);
  CHECK(!client.failed());
  CHECK(got.size() == 1 && got[0].id == 102 && got[0].body == payload);
}

void test_raw_data() {
  // 100 announces a raw message that may hold newlines.
  const uint8_t key = 4;
  FrameEncoder server(key, false);
  std::string raw = gchar(102) + "a\nb\nc";
  std::string plain = gchar(100) + gint3(static_cast<uint32_t>(raw.size() + 1)) + "\n" + raw + "\n" + gchar(6) + "x\n";
  std::vector<Got> got;
  FrameDecoder client(key, [&](int id, std::string_view b) { got.push_back({id, std::string(b)}); });
  client.feed(server.encode(plain));
  CHECK(got.size() == 2);
  CHECK(got[0].id == 102 && got[0].body == "a\nb\nc");
  CHECK(got[1].id == 6 && got[1].body == "x");
}

void test_bad_frames() {
  std::vector<Got> got;
  FrameDecoder d(1, [&](int id, std::string_view b) { got.push_back({id, std::string(b)}); });
  d.feed(std::string("\x00\x03\x09zz", 5));  // unknown compression byte
  CHECK(d.failed());
  FrameDecoder big(1, [](int, std::string_view) {});
  big.feed(std::string("\xFF\xFF\x7F\x00\x00\x00", 6));  // past the frame limit
  CHECK(big.failed());
  FrameDecoder z(1, [](int, std::string_view) {});
  z.feed(std::string("\x00\x04\x05" "abc", 6));  // type 5: bzip2, not XORed, garbage
  CHECK(z.failed());
}

void test_login_frame() {
  FrameEncoder client(3);
  std::string f = client.encode("%login line\n");
  size_t len = (static_cast<unsigned char>(f[0]) << 8) | static_cast<unsigned char>(f[1]);
  CHECK(len == f.size() - 2);
  std::string plain;
  CHECK(zlib_decompress(std::string_view(f).substr(2), plain));
  CHECK(plain == "%login line\n");
  CHECK(client.login_sent());
}

void test_profiles() {
  const BuildProfile* r603 = find_profile("6.03r7");
  const BuildProfile* r601 = find_profile("6.01r1 linux");
  CHECK(r603 && r601);
  if (!r603 || !r601) return;
  CHECK(r603->token == "G3D0511C");
  CHECK(r601->token == "G3D0108A");
  CHECK(r603->plo.count() == 92);
  CHECK(r601->plo.count() == 91);
  CHECK(r603->plo.test(111) && !r601->plo.test(111));
  CHECK(r603->pli.test(160) && !r601->pli.test(160));
  CHECK(!r603->pli.test(39));  // no tamper check
  CHECK(!r603->plo.test(41));  // the start message is gone in 6.x
  CHECK(r603->plo.test(178));
  CHECK(!r603->plo.test(100) && !r603->plo.test(108));
  CHECK(handles_pre_switch(100) && handles_pre_switch(108));
  CHECK(find_profile("7.0") == nullptr);
  CHECK(find_profile("6.0") == nullptr);

  // 5.00r7 and 5.12: the same 100-id switch (v5v6-windows-unpacked.md).
  const BuildProfile* r500 = find_profile("5.00r7");
  const BuildProfile* r512 = find_profile("5.12");
  CHECK(r500 && r512);
  if (!r500 || !r512) return;
  CHECK(r500->token == "G3D22067" && r512->token == "G3D14097");
  CHECK(r500->plo.count() == 100 && r512->plo == r500->plo);
  CHECK(r512->plo.test(41) && r512->plo.test(193) && !r512->plo.test(198));
  CHECK(!r512->pli.test(39) && r512->pli.test(5) && r512->pli == r500->pli);
  CHECK(r512->packed_round_down && r512->compress_always && !r500->packed_round_down);
  CHECK(r512->has_os_version && !r500->has_os_version);
  const BuildProfile* r404 = find_profile("4.04r2");
  CHECK(r404 && r404->packed_round_down && !r404->compress_always);
}

// 5.12 steps packed bodies len / 4 rounded down; raw ones still round up
// (protocol/v5v6-lab-play.md, "5.12's cipher step count").
void test_round_down() {
  for (size_t n : {13u, 14u, 15u, 16u, 20u}) {
    Cipher up(9), down(9);
    down.set_packed_round_down(true);
    std::string a(n, '\0'), b(n, '\0');
    up.apply(a, kZlib);
    down.apply(b, kZlib);
    const size_t full = std::min<size_t>(n / 4, 4);
    for (size_t p = 0; p < full * 4; ++p) CHECK(a[p] == b[p]);
    for (size_t p = full * 4; p < n; ++p) CHECK(b[p] == 0);
    // One step short exactly when a short packed body is not a multiple of 4.
    CHECK((up.iterator() == down.iterator()) == (n % 4 == 0 || n >= 16));
  }
  Cipher up(9), down(9);
  down.set_packed_round_down(true);
  std::string a(13, '\0'), b(13, '\0');
  up.apply(a, kRaw);
  down.apply(b, kRaw);
  CHECK(a == b && up.iterator() == down.iterator());

  // A round-down encoder and decoder agree; every short body is zlib.
  FrameEncoder enc(0x21, false);
  enc.set_packed_round_down(true);
  enc.set_compress_always(true);
  std::vector<std::string> got;
  FrameDecoder dec(0x21, [&](int, std::string_view b) { got.emplace_back(b); });
  dec.set_packed_round_down(true);
  for (const char* m : {"!a\n", "!bcdefg\n", "!hi\n"}) {
    const std::string f = enc.encode(m);
    CHECK(static_cast<unsigned char>(f[2]) == kZlib);
    dec.feed(f);
  }
  CHECK(!dec.failed() && got.size() == 3 && got[2] == "hi");
}

}  // namespace

int main() {
  test_gtypes();
  test_cipher();
  test_compression_choice();
  test_frame_length();
  test_round_trip();
  test_long_frame();
  test_raw_data();
  test_bad_frames();
  test_login_frame();
  test_profiles();
  test_round_down();
  TEST_MAIN_END();
}
