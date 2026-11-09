#include "run_dso.hpp"

#include <cstdlib>
#include <iostream>

using Bytes = std::vector<std::uint8_t>;
void require(bool value, const char* message) {
  if (!value) { std::cerr << message << '\n'; std::exit(1); }
}

// Literal synthetic DSO33, authored from the published field layout. No writer
// under test supplies this fixture. The escaped integer is signed32 minus one.
Bytes fixture() {
  return {
    33,0,0,0,                       // version
    0,0,0,0, 0,0,0,0,              // global strings/floats
    0,0,0,0, 0,0,0,0,              // function strings/floats
    4,0,0,0, 0,0,0,0,              // code count / line count
    65,255,255,255,255,255,63,13,   // load bits, to string, return
    0,0,0,0                        // identifier count
  };
}
int main() {
  using namespace Torque;
  const auto bytes = fixture();
  require(bytes.size() == 40, "fixture size");
  for (const auto order : {FloatOrder::little, FloatOrder::big}) {
    const auto result = execute_dso(bytes, order);
    require(result.returned() && result.execution.value == "-1" &&
            result.execution.steps == 3 && result.execution.ip == 3,
            "serialized execution result");
  }
  // File validation precedes execution even when an early return is present.
  for (std::size_t n = 0; n < bytes.size(); ++n) {
    const auto result = execute_dso(Bytes(bytes.begin(), bytes.begin()+n), FloatOrder::little);
    require(result.status == DsoRunStatus::format_error &&
            result.format.kind == DsoErrorKind::truncated &&
            result.execution.steps == 0 && result.execution.value.empty(),
            "truncation executed code");
  }
  auto bad = bytes;
  bad.push_back(0);
  require(execute_dso(bad, FloatOrder::little).format.kind == DsoErrorKind::trailing,
          "trailing bytes accepted");
  bad = bytes;
  bad[28] = 0; // validly serialized but unsupported instruction
  auto result = execute_dso(bad, FloatOrder::little);
  require(result.status == DsoRunStatus::vm_error &&
          result.execution.error == VmError::unsupported_opcode &&
          result.execution.steps == 0, "unsupported instruction ran");
  result = execute_dso(bytes, FloatOrder::little, {2, 1024});
  require(result.status == DsoRunStatus::vm_error &&
          result.execution.error == VmError::step_limit &&
          result.execution.value.empty(), "budget did not propagate");
  result = execute_dso(bytes, FloatOrder::little, {100, 0});
  require(result.status == DsoRunStatus::vm_error &&
          result.execution.error == VmError::stack_limit, "stack limit lost");

  // Table-end sentinel with one valid use: loader accepts the layout, but
  // the adapter must not interpret this unlinked operand as an integer.
  bad = bytes;
  bad[36] = 1;
  bad.insert(bad.end(), {0,0,0,0, 1,0,0,0, 1,0,0,0});
  DsoBlock block;
  DsoError format;
  require(load_dso(bad, FloatOrder::little, block, format), "relocation fixture malformed");
  result = execute_dso(bad, FloatOrder::little);
  require(result.status == DsoRunStatus::relocation_required &&
          result.execution.steps == 0 && result.execution.value.empty(),
          "unlinked operand executed");
  bad = bytes;
  bad[36] = 1;
  bad.insert(bad.end(), {0,0,0,0, 0,0,0,0});
  require(execute_dso(bad, FloatOrder::little).returned(),
          "unused identifier group blocked execution");
  // No shared VM state survives an earlier failed run.
  require(execute_dso(bytes, FloatOrder::little).execution.value == "-1",
          "later run contaminated");
}
