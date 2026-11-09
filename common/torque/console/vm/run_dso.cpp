#include "run_dso.hpp"

namespace Torque {
DsoRunResult execute_dso(const std::vector<std::uint8_t>& bytes, FloatOrder order,
                         VmLimits limits) {
  DsoRunResult result;
  DsoBlock block;
  if (!load_dso(bytes, order, block, result.format)) return result;
  for (const auto& identifier : block.identifiers) {
    if (!identifier.uses.empty()) {
      result.status = DsoRunStatus::relocation_required;
      return result;
    }
  }
  result.execution = execute_words(block.code, limits);
  result.status = result.execution.returned() ? DsoRunStatus::returned
                                             : DsoRunStatus::vm_error;
  return result;
}
} // namespace Torque
