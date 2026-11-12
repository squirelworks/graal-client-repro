// DES with Graal's key twist and the GRESCR01 reader contract.
#include "../cache/des.hpp"
#include "../cache/grescr.hpp"
#include "check.hpp"

#include <string>

using namespace Quattro::Cache;

namespace {

std::array<uint8_t, 8> key_bytes(uint64_t k) {
  std::array<uint8_t, 8> out{};
  for (int i = 7; i >= 0; --i) {
    out[static_cast<size_t>(i)] = static_cast<uint8_t>(k & 0xFF);
    k >>= 8;
  }
  return out;
}

void test_des_vectors() {
  // FIPS 46-3 worked example, and the same pair with Graal's bit-reversed
  // key bytes (client-internals/saved-passwords.md).
  Des textbook(key_bytes(0x133457799BBCDFF1ULL), false);
  CHECK(textbook.encrypt_block(0x0123456789ABCDEFULL) == 0x85E813540F0AB405ULL);
  CHECK(textbook.decrypt_block(0x85E813540F0AB405ULL) == 0x0123456789ABCDEFULL);
  Des graal(key_bytes(0x133457799BBCDFF1ULL));
  CHECK(graal.encrypt_block(0x0123456789ABCDEFULL) == 0xCEE55ACD2386B23FULL);
  CHECK(graal.decrypt_block(0xCEE55ACD2386B23FULL) == 0x0123456789ABCDEFULL);

  // ECB leaves a short tail in clear.
  std::string data = "0123456789abcdefXYZ";
  std::string enc = graal.encrypt(data);
  CHECK(enc.substr(16) == "XYZ");
  CHECK(enc.substr(0, 16) != data.substr(0, 16));
  CHECK(graal.decrypt(enc) == data);
}

void test_key_words() {
  auto k = key_from_words(0x04030201u, 0x08070605u);
  for (int i = 0; i < 8; ++i) CHECK(k[static_cast<size_t>(i)] == i + 1);
}

void test_crc() {
  CHECK(crc32("") == 0);
  CHECK(crc32("123456789") == 0xCBF43926u);  // the CRC-32 check value
}

// formats/windows-603-cache-conformance.static-derived.json: an eight-byte
// header-only file is never accepted.
void test_conformance_header_only() {
  const std::string file = "GRESCR01";
  ScriptKey key{1, 2};
  GrescrResult zero = read_grescr(file, 1, key, 0);
  CHECK(!zero.success);
  CHECK(!weapon_cache_hit(zero));
  GrescrResult one = read_grescr(file, 1, key, 1);
  CHECK(!one.success && one.body.empty());
  GrescrResult flag2 = read_grescr(file, 2, key, 0);
  CHECK(!flag2.success && flag2.body.empty());
  GrescrResult nokey = read_grescr(file, 1, std::nullopt, 0);
  CHECK(!nokey.success && nokey.body.empty());
}

void test_round_trip() {
  // A synthetic body: segment 1 holding a zero word, as official output has.
  std::string plain("\x00\x00\x00\x01\x00\x00\x00\x04\x00\x00\x00\x00tail5", 17);
  ScriptKey key{0x11223344u, 0x55667788u};
  uint32_t crc = 0;
  std::string file = write_grescr(plain, key, &crc);
  CHECK(file.substr(0, 8) == "GRESCR01");
  CHECK(file.size() == 8 + plain.size());
  CHECK(file.substr(8 + 16) == plain.substr(16));  // clear tail
  CHECK(crc == crc32(std::string_view(file).substr(8)));

  GrescrResult hit = read_grescr(file, 1, key, crc);
  CHECK(hit.success && hit.body == plain);

  // CRC 0: bytes come back, success stays false.
  GrescrResult skip = read_grescr(file, 1, key, 0);
  CHECK(!skip.success && skip.body == plain);

  // The CRC covers the stored body, not the plaintext.
  GrescrResult plain_crc = read_grescr(file, 1, key, crc32(plain));
  CHECK(!plain_crc.success && plain_crc.body.empty());

  GrescrResult wrong_magic = read_grescr("GRESCR02" + file.substr(8), 1, key, crc);
  CHECK(!wrong_magic.success);
  GrescrResult short_file = read_grescr("GRESC", 1, key, crc);
  CHECK(!short_file.success);
}

}  // namespace

int main() {
  test_des_vectors();
  test_key_words();
  test_crc();
  test_conformance_header_only();
  test_round_trip();
  TEST_MAIN_END();
}
