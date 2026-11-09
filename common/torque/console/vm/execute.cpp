#include "execute.hpp"

namespace Torque {
namespace {
constexpr std::uint32_t jump_if_not = 7, jump_if = 9, jump = 12, ret = 13;
constexpr std::uint32_t uint_to_string = 63, discard_uint = 64, load_uint = 65;
constexpr std::size_t max_words = 1024 * 1024;

bool has_operand(std::uint32_t op) {
  return op == jump_if_not || op == jump_if || op == jump || op == load_uint;
}
bool is_branch(std::uint32_t op) {
  return op == jump_if_not || op == jump_if || op == jump;
}
bool supported(std::uint32_t op) {
  return has_operand(op) || op == ret || op == uint_to_string || op == discard_uint;
}
} // namespace

VmResult execute_words(const std::vector<std::uint32_t>& code, VmLimits limits) {
  VmResult result;
  auto fail = [&](VmError error, std::size_t ip) {
    result.error = error;
    result.ip = ip;
    // Partial output must not be mistaken for a completed script result.
    result.value.clear();
    return result;
  };
  if (code.size() > max_words) return fail(VmError::code_limit, 0);
  std::vector<bool> starts(code.size(), false);
  // Validate the entire selected subset before executing it. An operand that
  // happens to equal an opcode is never an instruction boundary.
  for (std::size_t ip = 0; ip < code.size();) {
    starts[ip] = true;
    const auto op = code[ip];
    if (!supported(op)) return fail(VmError::unsupported_opcode, ip);
    if (has_operand(op) && code.size() - ip < 2)
      return fail(VmError::missing_operand, ip);
    ip += has_operand(op) ? 2 : 1;
  }
  for (std::size_t ip = 0; ip < code.size();) {
    const auto op = code[ip];
    if (is_branch(op) && (code[ip+1] >= starts.size() || !starts[code[ip+1]]))
      return fail(VmError::invalid_target, ip);
    ip += has_operand(op) ? 2 : 1;
  }

  std::vector<std::uint32_t> integers;
  std::size_t ip = 0;
  while (ip < code.size()) {
    if (result.steps == limits.steps) return fail(VmError::step_limit, ip);
    ++result.steps;
    const auto at = ip;
    const auto op = code[ip++];
    if (op == ret) {
      result.ip = at;
      return result;
    }
    if (op == load_uint) {
      if (integers.size() == limits.stack) return fail(VmError::stack_limit, at);
      integers.push_back(code[ip++]);
    } else if (op == jump) {
      ip = code[ip];
    } else {
      if (integers.empty()) return fail(VmError::stack_underflow, at);
      const auto value = integers.back();
      integers.pop_back();
      if (op == uint_to_string) {
        result.value = std::to_string(value);
      } else if (op != discard_uint) {
        const auto target = code[ip++];
        if ((op == jump_if && value != 0) || (op == jump_if_not && value == 0))
          ip = target;
      }
    }
  }
  return fail(VmError::missing_return, ip);
}
} // namespace Torque
