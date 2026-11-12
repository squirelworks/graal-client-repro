// DES in ECB mode, as the 6.x program uses it for cached scripts and
// package keys.
//
// The cipher is the published standard (FIPS 46-3). Graal's one twist,
// from Graal_analysis client-internals/saved-passwords.md: every key byte
// is bit-reversed (bit 0 becomes bit 7) before the key schedule. The note's
// check value: key 133457799BBCDFF1, block 0123456789ABCDEF gives
// CEE55ACD2386B23F with the twist (85E813540F0AB405 as textbook DES).
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

namespace Quattro::Cache {

class Des {
 public:
  // `graal_key` true applies the bit-reversal before the schedule.
  explicit Des(const std::array<uint8_t, 8>& key, bool graal_key = true);

  uint64_t encrypt_block(uint64_t block) const { return crypt(block, false); }
  uint64_t decrypt_block(uint64_t block) const { return crypt(block, true); }

  // ECB over whole 8-byte blocks; a short tail is left as it is (the 6.113
  // caches store the last len % 8 bytes in clear, gs2-official-bytecode-6113.md).
  std::string encrypt(std::string_view data) const;
  std::string decrypt(std::string_view data) const;

 private:
  uint64_t crypt(uint64_t block, bool decrypt) const;
  std::array<uint64_t, 16> subkeys_{};
};

// Two little-endian 32-bit words (the two GINT5 values of 140 and 197) as
// the 8 key bytes (formats/gwebl001-cache.md, "GRESCR01").
std::array<uint8_t, 8> key_from_words(uint32_t lo, uint32_t hi);

}  // namespace Quattro::Cache
