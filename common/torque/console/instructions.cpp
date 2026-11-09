#include "instructions.hpp"

#include <utility>

namespace Torque {
namespace {
std::size_t fixed_operands(std::uint32_t op) {
  switch (op) {
    case 1: case 70: case 71: return 3;
    case 4: case 5: case 6: case 7: case 8: case 9: case 10: case 11: case 12:
    case 36: case 37: case 48: case 65: case 66: case 67: case 68: case 69:
    case 74: return 1;
    default: return 0;
  }
}
} // namespace

bool decode_instructions(const std::vector<std::uint32_t>& code,
                         std::vector<DsoInstruction>& output, InstructionError& error) {
  auto fail = [&](InstructionErrorKind kind, std::size_t ip, const char* message) {
    error = {kind, ip, message};
    return false;
  };
  if (code.size() > 1024 * 1024)
    return fail(InstructionErrorKind::code_limit, 0, "instruction word limit exceeded");
  std::vector<DsoInstruction> decoded;
  std::vector<bool> boundaries(code.size() + 1, false);
  boundaries[code.size()] = true;
  for (std::size_t ip = 0; ip < code.size();) {
    const auto op = code[ip];
    if (op > 82 || op == 2 || op == 3 || op == 72)
      return fail(InstructionErrorKind::unknown_opcode, ip, "undocumented opcode");
    std::size_t count = fixed_operands(op);
    if (op == 0) {
      // FUNC_DECL: name, namespace, package, hasBody, end, argc, arg names.
      if (code.size() - ip - 1 < 6)
        return fail(InstructionErrorKind::truncated, ip, "truncated function header");
      const auto argc = code[ip + 6];
      if (argc > code.size() - ip - 7)
        return fail(InstructionErrorKind::truncated, ip, "truncated function arguments");
      count = 6 + static_cast<std::size_t>(argc);
    }
    if (count > code.size() - ip - 1)
      return fail(InstructionErrorKind::truncated, ip, "truncated instruction operands");
    boundaries[ip] = true;
    decoded.push_back({ip, op, {code.begin()+ip+1, code.begin()+ip+1+count}});
    ip += count + 1;
  }
  for (const auto& instruction : decoded) {
    const auto op = instruction.opcode;
    std::uint32_t target;
    bool has_target = true;
    if (op >= 6 && op <= 12) target = instruction.operands[0];
    else if (op == 1) target = instruction.operands[2];
    else if (op == 0 && instruction.operands[3] != 0) {
      target = instruction.operands[4];
      if (target < instruction.ip + instruction.operands.size() + 1)
        return fail(InstructionErrorKind::target, instruction.ip, "function end precedes body");
    } else {
      target = 0;
      has_target = false;
    }
    if (has_target && (target > code.size() || !boundaries[target]))
      return fail(InstructionErrorKind::target, instruction.ip, "target is not a code boundary");
  }
  output = std::move(decoded);
  error = {};
  return true;
}
} // namespace Torque
