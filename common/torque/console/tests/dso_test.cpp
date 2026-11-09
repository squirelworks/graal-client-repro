#include "../dso.hpp"

#include <cstdlib>
#include <iostream>
#include <vector>

using Bytes = std::vector<std::uint8_t>;
void require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}

// Independently hand-written from the documented field layout, not produced
// by the reader or an encoder under test. See README.md for provenance.
Bytes fixture() {
  return {
    33,0,0,0,                         // version
    4,0,0,0, 'A',0,'B',0,             // global strings
    1,0,0,0, 0,0,0,0,0,0,0xf0,0x3f, // global float: 1.0
    2,0,0,0, 'F',0,                   // function strings
    1,0,0,0, 0,0,0,0,0,0,4,0xc0,    // function float: -2.5
    4,0,0,0, 1,0,0,0,                // code words, line pairs
    65,255,0x78,0x56,0x34,0x12,13,0,  // compact and escaped words
    10,0,0,0, 0,0,0,0,               // source line 10 at ip 0
    2,0,0,0,                          // two identifier groups
    0,0,0,0, 1,0,0,0, 3,0,0,0,       // A used at code word 3
    4,0,0,0, 0,0,0,0                 // unnamed argument at table end
  };
}
void put32(Bytes& bytes, std::size_t at, std::uint32_t value) {
  for (unsigned i = 0; i < 4; ++i) bytes.at(at + i) = (value >> (i * 8)) & 255;
}
void reject(const Bytes& bytes, Torque::DsoErrorKind kind) {
  Torque::DsoBlock output;
  output.code = {999};
  output.global_strings = "unchanged";
  Torque::DsoError error;
  require(!Torque::load_dso(bytes, Torque::FloatOrder::little, output, error),
          "malformed DSO accepted");
  require(error.kind == kind, "incorrect error classification");
  require(error.offset <= bytes.size(), "error outside input");
  require(output.code == std::vector<std::uint32_t>{999} &&
          output.global_strings == "unchanged", "failure changed caller state");
}
int main() {
  const auto original = fixture();
  require(original.size() == 90, "fixture layout changed");
  Torque::DsoBlock block;
  Torque::DsoError error;
  require(Torque::load_dso(original, Torque::FloatOrder::little, block, error),
          "little-endian fixture rejected");
  require(error.kind == Torque::DsoErrorKind::none, "success left an error");
  require(block.global_strings == std::string("A\0B\0", 4) &&
          block.function_strings == std::string("F\0", 2), "string tables differ");
  require(block.global_floats == std::vector<double>{1.0} &&
          block.function_floats == std::vector<double>{-2.5}, "float tables differ");
  require(block.code == std::vector<std::uint32_t>{65,0x12345678,13,0},
          "compact/escaped words differ or relocation patched code");
  require(block.lines.size() == 1 && block.lines[0].line == 10 && block.lines[0].ip == 0,
          "line table differs");
  require(block.identifiers.size() == 2 && block.identifiers[0].name == "A" &&
          !block.identifiers[0].unnamed && block.identifiers[0].string_offset == 0 &&
          block.identifiers[0].uses == std::vector<std::uint32_t>{3} &&
          block.identifiers[1].unnamed && block.identifiers[1].name.empty() &&
          block.identifiers[1].uses.empty(), "identifier groups differ");

  auto big = original;
  const Bytes one_be = {0x3f,0xf0,0,0,0,0,0,0};
  const Bytes negative_be = {0xc0,4,0,0,0,0,0,0};
  for (unsigned i = 0; i < 8; ++i) { big[16+i] = one_be[i]; big[34+i] = negative_be[i]; }
  require(Torque::load_dso(big, Torque::FloatOrder::big, block, error) &&
          block.global_floats[0] == 1.0 && block.function_floats[0] == -2.5,
          "explicit PPC float order failed");

  for (std::size_t end = 0; end < original.size(); ++end)
    reject(Bytes(original.begin(), original.begin()+end), Torque::DsoErrorKind::truncated);
  auto bad = original;
  bad[0] = 34; reject(bad, Torque::DsoErrorKind::version);
  bad = original; bad.push_back(0); reject(bad, Torque::DsoErrorKind::trailing);
  for (const std::size_t at : {12,30,42,46,66,74}) {
    bad = original; put32(bad, at, 0xffffffff);
    reject(bad, Torque::DsoErrorKind::limit);
  }
  for (const std::size_t at : {4,24}) {
    bad = original; put32(bad, at, 0xffffffff);
    reject(bad, Torque::DsoErrorKind::truncated);
  }
  bad = original; put32(bad, 70, 5); reject(bad, Torque::DsoErrorKind::identifier);
  bad = original; put32(bad, 70, 2); bad[11] = 'X';
  reject(bad, Torque::DsoErrorKind::identifier);
  bad = original; put32(bad, 78, 4); reject(bad, Torque::DsoErrorKind::relocation);
  bad = original; put32(bad, 74, 100); reject(bad, Torque::DsoErrorKind::truncated);
  bad = original; put32(bad, 46, 100); reject(bad, Torque::DsoErrorKind::truncated);
  reject(Bytes(Torque::dso_max_bytes+1, 0), Torque::DsoErrorKind::limit);

  // Empty tables and no code are structurally legal; no execution is implied.
  Bytes empty(32, 0); empty[0] = 33;
  error = {Torque::DsoErrorKind::version, 8, "stale error"};
  require(Torque::load_dso(empty, Torque::FloatOrder::little, block, error) &&
          block.code.empty() && block.identifiers.empty() &&
          error.kind == Torque::DsoErrorKind::none && error.message.empty(),
          "empty tables or error reset failed");
  std::cout << "DSO33 tables, explicit float orders, relocations and malformed inputs passed\n";
}
