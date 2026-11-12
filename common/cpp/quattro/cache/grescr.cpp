#include "grescr.hpp"

#include "des.hpp"

#include <array>

namespace Quattro::Cache {

namespace {
std::array<uint32_t, 256> make_table() {
  std::array<uint32_t, 256> t{};
  for (uint32_t i = 0; i < 256; ++i) {
    uint32_t c = i;
    for (int k = 0; k < 8; ++k) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
    t[i] = c;
  }
  return t;
}
}  // namespace

// The zlib CRC-32: an empty input returns `crc` unchanged.
uint32_t crc32(std::string_view data, uint32_t crc) {
  static const std::array<uint32_t, 256> table = make_table();
  if (data.empty()) return crc;
  crc = ~crc;
  for (unsigned char b : data) crc = table[(crc ^ b) & 0xFF] ^ (crc >> 8);
  return ~crc;
}

GrescrResult read_grescr(std::string_view file, int cache_flag, std::optional<ScriptKey> key,
                         uint32_t expected_crc) {
  GrescrResult r;
  if (cache_flag != 1 || !key) return r;
  if (file.size() < kGrescrMagic.size() || file.substr(0, kGrescrMagic.size()) != kGrescrMagic) return r;
  std::string_view stored = file.substr(kGrescrMagic.size());
  if (expected_crc != 0) {
    if (crc32(stored) != expected_crc) return r;
    r.success = true;
  }
  Des des(key_from_words(key->lo, key->hi));
  r.body = des.decrypt(stored);
  return r;
}

std::string write_grescr(std::string_view plain, ScriptKey key, uint32_t* crc_out) {
  Des des(key_from_words(key.lo, key.hi));
  std::string stored = des.encrypt(plain);
  if (crc_out) *crc_out = crc32(stored);
  return std::string(kGrescrMagic) + stored;
}

}  // namespace Quattro::Cache
