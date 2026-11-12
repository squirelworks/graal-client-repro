// Graal's 7-bit wire integers, as the 6.x program reads and writes them.
//
// Each value is one or more bytes of 7 bits, most significant group first,
// each group stored as group + 32 (Graal_analysis protocol/codec-and-framing.md;
// protocol/v6x-clients.md uses the same names: `c`, `s`, `i3`, `i5`).
#pragma once

#include <cstdint>
#include <string>
#include <string_view>

namespace Quattro::Net {

// GCHAR: one byte, value + 32. Values above 223 wrap as the original's byte
// arithmetic does; callers keep values in range.
std::string gchar(unsigned v);
// GSHORT: two 7-bit groups (0 .. 0x3FFF).
std::string gshort(unsigned v);
// GINT3: three 7-bit groups (0 .. 0x1FFFFF).
std::string gint3(uint32_t v);
// GINT5: five 7-bit groups (0 .. 2^35 - 1).
std::string gint5(uint64_t v);
// GCHAR length + bytes. Strings of 0xE0 bytes or more are cut to 0xDF and
// the length byte is 0xFF, as the 6.x login line does for the password.
std::string gstring(std::string_view s);

// Reads the same encodings from a message body. Reading past the end gives
// 0 (or an empty string) and sets `ok` to false; it never throws.
class Reader {
 public:
  explicit Reader(std::string_view data) : data_(data) {}

  unsigned gchar();
  unsigned gshort();
  uint32_t gint3();
  uint64_t gint5();
  std::string gstring();  // GCHAR length, then that many bytes
  std::string rest();     // everything not read yet

  bool ok() const { return ok_; }
  bool at_end() const { return pos_ >= data_.size(); }
  size_t pos() const { return pos_; }

 private:
  unsigned byte();
  std::string_view data_;
  size_t pos_ = 0;
  bool ok_ = true;
};

}  // namespace Quattro::Net
