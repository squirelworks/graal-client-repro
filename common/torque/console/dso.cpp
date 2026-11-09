#include "dso.hpp"

#include <cstring>
#include <limits>
#include <utility>

namespace Torque {
namespace {
class Reader {
 public:
  explicit Reader(const std::vector<std::uint8_t>& input) : bytes(input) {}
  std::size_t pos = 0;
  std::size_t remaining() const { return bytes.size() - pos; }
  [[noreturn]] void fail(DsoErrorKind kind, const std::string& message) const {
    throw DsoError{kind, pos, message};
  }
  void need(std::size_t count) const {
    if (count > remaining()) fail(DsoErrorKind::truncated, "truncated DSO field");
  }
  std::uint8_t byte() { need(1); return bytes[pos++]; }
  std::uint32_t u32() {
    need(4);
    std::uint32_t value = 0;
    for (unsigned i = 0; i < 4; ++i) value |= std::uint32_t(bytes[pos++]) << (i * 8);
    return value;
  }
  std::uint32_t count(std::size_t minimum_bytes) {
    const auto value = u32();
    if (value > dso_max_items) fail(DsoErrorKind::limit, "DSO item limit exceeded");
    // Division prevents count multiplication overflowing on a 32-bit host.
    if (value > remaining() / minimum_bytes)
      fail(DsoErrorKind::truncated, "DSO count exceeds remaining bytes");
    return value;
  }
  std::string strings() {
    const auto size = u32();
    need(size);
    std::string result(bytes.begin() + pos, bytes.begin() + pos + size);
    pos += size;
    return result;
  }
  std::vector<double> floats(FloatOrder order) {
    const auto size = count(8);
    std::vector<double> result;
    result.reserve(size);
    for (std::uint32_t i = 0; i < size; ++i) {
      std::uint64_t bits = 0;
      for (unsigned j = 0; j < 8; ++j) {
        const unsigned shift = order == FloatOrder::big ? (7 - j) * 8 : j * 8;
        bits |= std::uint64_t(byte()) << shift;
      }
      double value;
      std::memcpy(&value, &bits, sizeof(value));
      result.push_back(value);
    }
    return result;
  }
 private:
  const std::vector<std::uint8_t>& bytes;
};
static_assert(sizeof(double) == 8 && std::numeric_limits<double>::is_iec559,
              "DSO float tables require IEEE-754 binary64");
} // namespace

bool load_dso(const std::vector<std::uint8_t>& bytes, FloatOrder order,
              DsoBlock& output, DsoError& error) {
  Reader in(bytes);
  try {
    if (bytes.size() > dso_max_bytes)
      in.fail(DsoErrorKind::limit, "DSO file limit exceeded");
    if (in.u32() != 33) in.fail(DsoErrorKind::version, "expected DSO version 33");
    DsoBlock block;
    block.global_strings = in.strings();
    block.global_floats = in.floats(order);
    block.function_strings = in.strings();
    block.function_floats = in.floats(order);
    const auto code_size = in.count(1);
    const auto line_size = in.u32();
    if (line_size > dso_max_items) in.fail(DsoErrorKind::limit, "DSO line limit exceeded");
    // Recheck after the line count, before allocating the code vector.
    in.need(code_size);
    block.code.reserve(code_size);
    for (std::uint32_t i = 0; i < code_size; ++i) {
      const auto first = in.byte();
      block.code.push_back(first == 255 ? in.u32() : first);
    }
    if (line_size > in.remaining() / 8)
      in.fail(DsoErrorKind::truncated, "truncated DSO line table");
    block.lines.reserve(line_size);
    for (std::uint32_t i = 0; i < line_size; ++i) {
      const auto line = in.u32();
      const auto ip = in.u32();
      block.lines.push_back({line, ip});
    }
    const auto ident_size = in.count(8);
    block.identifiers.reserve(ident_size);
    std::size_t name_bytes = 0;
    for (std::uint32_t i = 0; i < ident_size; ++i) {
      DsoIdentifier ident;
      ident.string_offset = in.u32();
      if (ident.string_offset > block.global_strings.size())
        in.fail(DsoErrorKind::identifier, "identifier offset outside global strings");
      ident.unnamed = ident.string_offset == block.global_strings.size();
      if (!ident.unnamed) {
        const auto end = block.global_strings.find('\0', ident.string_offset);
        if (end == std::string::npos)
          in.fail(DsoErrorKind::identifier, "unterminated identifier");
        const auto size = end - ident.string_offset;
        if (size > dso_max_bytes - name_bytes)
          in.fail(DsoErrorKind::limit, "DSO identifier name budget exceeded");
        name_bytes += size;
        ident.name = block.global_strings.substr(ident.string_offset, size);
      }
      const auto use_size = in.count(4);
      ident.uses.reserve(use_size);
      for (std::uint32_t j = 0; j < use_size; ++j) {
        const auto ip = in.u32();
        if (ip >= block.code.size())
          in.fail(DsoErrorKind::relocation, "identifier use outside code");
        ident.uses.push_back(ip);
      }
      block.identifiers.push_back(std::move(ident));
    }
    if (in.remaining()) in.fail(DsoErrorKind::trailing, "unexpected bytes after DSO");
    output = std::move(block);
    error = {};
    return true;
  } catch (const DsoError& failure) {
    error = failure;
    return false;
  }
}
} // namespace Torque
