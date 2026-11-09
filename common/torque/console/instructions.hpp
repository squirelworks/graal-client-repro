#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace Torque {
struct DsoInstruction {
  std::size_t ip;
  std::uint32_t opcode;
  std::vector<std::uint32_t> operands;
};
enum class InstructionErrorKind { none, code_limit, unknown_opcode, truncated, target };
struct InstructionError {
  InstructionErrorKind kind = InstructionErrorKind::none;
  std::size_t ip = 0;
  std::string message;
};
// Structural decoding only. Word targets may identify an instruction or the
// end-of-stream boundary; this does not establish executable VM semantics.
// On failure, output remains unchanged. Operand words are never reinterpreted
// as opcodes, and identifier relocations are not applied.
bool decode_instructions(const std::vector<std::uint32_t>& code,
                         std::vector<DsoInstruction>& output, InstructionError& error);
} // namespace Torque
