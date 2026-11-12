// GRESCR01: the 6.x cache of a weapon or class script
// (weblevels/<host>/weapons/<name>.code and .../classes/<name>.code).
//
// Behaviour, from Graal_analysis formats/gwebl001-cache.md ("GRESCR01"),
// formats/windows-603-weapon-cache.md and
// protocol/gs2-official-bytecode-6113.md:
//
// - The file is the 8 bytes "GRESCR01", then the stored body: DES-ECB over
//   whole 8-byte blocks (Graal's bit-reversed key), the last len % 8 bytes
//   in clear. The plaintext is compiled GS2 (the four-segment container).
// - The key is the two GINT5 words of 140 / 197, as little-endian 32-bit
//   words. It is never stored on disk.
// - The reader clears success first. A cache flag other than 1, or no key,
//   returns empty at once. Fewer than 8 bytes or another magic: empty.
// - The CRC32 covers the stored body, before decryption. With an expected
//   CRC that is not 0, a mismatch returns empty; a match sets success and
//   returns the decrypted body. With an expected CRC of 0 the comparison is
//   skipped: the body is still decrypted and returned, but success stays
//   false.
// - The weapon caller asks the server again (PLI 158) whenever success is
//   false; returned bytes alone never mean the cache was accepted.
#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace Quattro::Cache {

constexpr std::string_view kGrescrMagic = "GRESCR01";

uint32_t crc32(std::string_view data, uint32_t crc = 0);

struct ScriptKey {
  uint32_t lo = 0;
  uint32_t hi = 0;
};

struct GrescrResult {
  bool success = false;  // the cache was accepted
  std::string body;      // returned bytes (may be non-empty with success false)
};

GrescrResult read_grescr(std::string_view file, int cache_flag, std::optional<ScriptKey> key,
                         uint32_t expected_crc);

// What the server's 140 sends is cached: the magic and the stored body
// (encrypted whole blocks, clear tail). Returns the file bytes and the CRC
// a later 197 would carry.
std::string write_grescr(std::string_view plain, ScriptKey key, uint32_t* crc_out = nullptr);

// The weapon caller's branch: true means "hand the bytes to the script
// machine", false means "send PLI 158 for the script".
inline bool weapon_cache_hit(const GrescrResult& r) { return r.success; }
constexpr int kPliUpdateScript = 158;

}  // namespace Quattro::Cache
