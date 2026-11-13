// The Torque bit stream as Graal's 3D link uses it (Graal_analysis
// torque/udp-session.md §2): bits packed least significant first, N-bit
// unsigned fields low bit first, f32 as its raw 32 bits, and two string
// forms: `string` (flag Huffman, u8 length, codes or bytes) and `pstring`
// (a leading flag: 1 = keep a prefix of the previous string of this packet).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace graal3d {

class BitReader {
 public:
  BitReader() = default;
  explicit BitReader(const std::string& bytes) : data_(bytes), size_(bytes.size() * 8) {}

  bool flag();
  uint32_t bits(int n);  // n <= 32
  uint8_t u8() { return static_cast<uint8_t>(bits(8)); }
  uint32_t u32() { return bits(32); }
  float f32();
  std::string string();
  std::string pstring();

  size_t pos() const { return pos_; }
  void seek(size_t p) { pos_ = p; }
  size_t size() const { return size_; }
  size_t left() const { return pos_ >= size_ ? 0 : size_ - pos_; }
  // True once a read ran past the end (the reads then give zeros).
  bool overrun() const { return overrun_; }
  // The previous-string buffer of `pstring`; cleared at each packet start.
  void resetStrings() { prev_.clear(); }

 private:
  std::string data_;
  size_t size_ = 0;
  size_t pos_ = 0;
  bool overrun_ = false;
  std::string prev_;
};

class BitWriter {
 public:
  bool flag(bool b);
  void bits(uint32_t v, int n);
  void u8(uint32_t v) { bits(v, 8); }
  void u32(uint32_t v) { bits(v, 32); }
  void f32(float f);
  // Huffman when that is shorter than the raw bytes (as the Seihai
  // gserver and the real clients write; udp-session.md §3).
  void string(const std::string& s);
  // Always the plain form (prefix flag 0); a writer may (§2).
  void pstring(const std::string& s);
  // Appends another writer's bits.
  void append(const BitWriter& w);

  size_t pos() const { return bits_.size(); }
  std::string bytes() const;
  const std::vector<uint8_t>& raw() const { return bits_; }

 private:
  std::vector<uint8_t> bits_;
};

std::string toHex(const std::string& bytes);
std::string fromHex(const std::string& hex);

}  // namespace graal3d
