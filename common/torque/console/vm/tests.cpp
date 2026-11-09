#include "execute.hpp"

#include <cstdlib>
#include <iostream>

void require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}
void error(const std::vector<std::uint32_t>& words, Torque::VmError expected,
           std::size_t ip, std::size_t steps, Torque::VmLimits limits = {}) {
  const auto result = Torque::execute_words(words, limits);
  require(!result.returned() && result.error == expected && result.ip == ip &&
          result.steps == steps && result.value.empty(), "wrong failure outcome");
}
int main() {
  using Torque::VmError;
  // Independently authored static-derived vectors published by analysis348.
  // These are not original-client runtime recordings. Result/count assertions
  // are explicit; implementation instruction counts remain our own policy.
  struct ContractCase {
    std::vector<std::uint32_t> words;
    const char* text;
    std::size_t steps, return_ip;
  };
  const std::vector<ContractCase> contract = {
    {{65,2147483647u,63,13}, "2147483647", 3,3},
    {{65,2147483648u,63,13}, "-2147483648", 3,3},
    {{65,4294967295u,63,13}, "-1", 3,3},
    {{65,17,65,99,64,63,13}, "17", 5,6},
    {{65,17,65,0,7,8,65,99,63,13}, "17", 5,9},
    {{65,17,65,4294967295u,9,8,65,99,63,13}, "17", 5,9},
    {{65,17,12,6,65,99,63,13}, "17", 4,7}
  };
  for (const auto& test : contract) {
    const auto actual = Torque::execute_words(test.words);
    require(actual.returned() && actual.value == test.text &&
            actual.steps == test.steps && actual.ip == test.return_ip,
            "published Linux3.04 static-derived contract differs");
  }
  // Hand-authored oracle: condition 0 branches to word 8, yielding "42".
  // No loader/compiler/encoder under test produces this fixture or its oracle.
  const std::vector<std::uint32_t> branch = {65,0,7,8,65,99,63,13,65,42,63,13};
  auto result = Torque::execute_words(branch);
  require(result.returned() && result.value == "42" && result.steps == 5 &&
          result.ip == 11, "taken zero branch did not return 42 in five steps");
  auto nonzero = branch; nonzero[1] = 1;
  result = Torque::execute_words(nonzero);
  require(result.returned() && result.value == "99" && result.steps == 5 &&
          result.ip == 7, "untaken zero branch differs");
  auto positive = branch; positive[2] = 9;
  result = Torque::execute_words(positive);
  require(result.returned() && result.value == "99", "untaken nonzero branch differs");
  positive[1] = 1;
  result = Torque::execute_words(positive);
  require(result.returned() && result.value == "42", "taken nonzero branch differs");
  result = Torque::execute_words({12,4,65,99,65,7,63,13});
  require(result.returned() && result.value == "7" && result.steps == 4,
          "unconditional branch differs");
  result = Torque::execute_words({65,8,64,65,2,63,13});
  require(result.returned() && result.value == "2", "discard did not pop");
  result = Torque::execute_words({65,9,63,65,4,63,13});
  require(result.returned() && result.value == "4", "string result did not replace");
  result = Torque::execute_words({13}, {1,0});
  require(result.returned() && result.value.empty() && result.steps == 1,
          "empty return or exact instruction budget differs");
  require(Torque::execute_words({13}).value.empty(), "state leaked between calls");

  error({}, VmError::missing_return, 0, 0);
  error({65}, VmError::missing_operand, 0, 0);
  error({7}, VmError::missing_operand, 0, 0);
  error({9}, VmError::missing_operand, 0, 0);
  error({12}, VmError::missing_operand, 0, 0);
  error({82}, VmError::unsupported_opcode, 0, 0);
  error({13,82}, VmError::unsupported_opcode, 1, 0); // even unreachable code
  error({12,1,13}, VmError::invalid_target, 0, 0);  // into its own operand
  error({12,3,13}, VmError::invalid_target, 0, 0);  // exactly code end
  error({12,0xffffffff,13}, VmError::invalid_target, 0, 0);
  error({65,0,7,1,13}, VmError::invalid_target, 2, 0);
  error({63,13}, VmError::stack_underflow, 0, 1);
  error({64,13}, VmError::stack_underflow, 0, 1);
  error({7,0,13}, VmError::stack_underflow, 0, 1);
  error({9,0,13}, VmError::stack_underflow, 0, 1);
  error({65,1,7,0,63,13}, VmError::stack_underflow, 4, 3); // branch consumes condition
  error({65,1,63}, VmError::missing_return, 3, 2); // discard partial string result
  error({12,0}, VmError::step_limit, 0, 7, {7,1});
  error({65,1,12,0}, VmError::stack_limit, 0, 5, {100,2});
  error({65,1,13}, VmError::stack_limit, 0, 1, {100,0});
  error({13}, VmError::step_limit, 0, 0, {0,1});
  error(std::vector<std::uint32_t>(1024*1024+1,13), VmError::code_limit, 0, 0);
  std::cout << "Bounded integer/branch/return execution and rejection tests passed\n";
}
