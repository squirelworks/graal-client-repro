#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace Torque {
enum class VmError {
  none, code_limit, unsupported_opcode, missing_operand, invalid_target,
  stack_underflow, stack_limit, step_limit, missing_return
};
struct VmLimits {
  std::size_t steps = 10000;
  std::size_t stack = 1024;
};
struct VmResult {
  VmError error = VmError::none;
  std::size_t ip = 0;
  std::size_t steps = 0;
  std::string value;
  bool returned() const { return error == VmError::none; }
};

// Executes only the documented subset; there are no native calls or external
// side effects. Each call owns fresh stacks/string state. ip is a word index.
VmResult execute_words(const std::vector<std::uint32_t>& code, VmLimits limits = {});
} // namespace Torque
