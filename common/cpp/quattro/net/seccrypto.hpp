// The primitives of the Seihai secure login (SEI00001) for the Quattro
// program. Not part of any Graal client: no Graal build had any of this.
//
// SHA-256 and SHA-512 (FIPS 180-4), HMAC-SHA256 (RFC 2104), HKDF-SHA256
// (RFC 5869), X25519 (RFC 7748), strict Ed25519 verification and signing
// (RFC 8032), ChaCha20-Poly1305 (RFC 8439), base64 without padding, and a
// random source from the operating system.
//
// The field and group code follows the public-domain TweetNaCl layout
// (sixteen 16-bit limbs in int64, constant-time selects), the same layout as
// the Pascal clients' common/GSecCrypto.pas, so both sides of the repo give
// the same bytes. Byte strings are std::string, like the rest of net/.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace Quattro::Net::Sec {

std::string sha256(std::string_view data);
std::string sha512(std::string_view data);
std::string hmac_sha256(std::string_view key, std::string_view data);
// Extract and expand; `len` at most 255 * 32.
std::string hkdf_sha256(std::string_view salt, std::string_view ikm, std::string_view info, size_t len);

// X25519(scalar, u): both 32 bytes. Returns 32 bytes.
std::string x25519(std::string_view scalar, std::string_view u);
std::string x25519_base(std::string_view scalar);
bool is_zero32(std::string_view s);

// Strict: S below L, canonical encodings, no small-order A or R.
bool ed25519_verify(std::string_view sig, std::string_view msg, std::string_view public_key);
// From a 32-byte seed. Used by the tests' stand-in server.
std::string ed25519_public_key(std::string_view seed);
std::string ed25519_sign(std::string_view msg, std::string_view seed);

std::string chacha20_xor(std::string_view key, std::string_view nonce, uint32_t counter, std::string_view data);
std::string poly1305_mac(std::string_view key, std::string_view msg);
// AEAD_CHACHA20_POLY1305: the ciphertext then the 16-byte tag.
std::string aead_seal(std::string_view key, std::string_view nonce, std::string_view aad, std::string_view plain);
bool aead_open(std::string_view key, std::string_view nonce, std::string_view aad, std::string_view sealed,
               std::string& plain);

// Standard alphabet, no padding. Decode is strict: no padding, no stray
// characters, no non-zero trailing bits.
std::string b64_encode(std::string_view data);
bool b64_decode(std::string_view text, std::string& out);

// False when the system gave no random bytes.
bool random_bytes(size_t n, std::string& out);

// Constant time over equal lengths.
bool same_bytes(std::string_view a, std::string_view b);

}  // namespace Quattro::Net::Sec
