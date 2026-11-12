#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace Torque {

enum class FloatOrder { little, big };
enum class DsoErrorKind { none, truncated, version, limit, identifier, relocation, trailing };
struct DsoError {
  DsoErrorKind kind = DsoErrorKind::none;
  std::size_t offset = 0;
  std::string message;
};
struct DsoLine { std::uint32_t line, ip; };
struct DsoIdentifier {
  std::uint32_t string_offset;
  // Unused arguments point at or past the global string table end.
  bool unnamed;
  std::string name;
  std::vector<std::uint32_t> uses;
};
struct DsoBlock {
  std::string global_strings, function_strings;
  std::vector<double> global_floats, function_floats;
  std::vector<std::uint32_t> code;
  std::vector<DsoLine> lines;
  std::vector<DsoIdentifier> identifiers;
};

constexpr std::size_t dso_max_bytes = 16 * 1024 * 1024;
constexpr std::size_t dso_max_items = 1024 * 1024;

// Format-only reader: no execution, interning or code patching. Float byte
// order is an explicit profile input; all integer fields are little-endian.
// On failure, output is unchanged. Error offsets are zero-based file bytes.
bool load_dso(const std::vector<std::uint8_t>& bytes, FloatOrder order,
              DsoBlock& output, DsoError& error);

} // namespace Torque
