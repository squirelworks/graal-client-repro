#pragma once

#include "../dso.hpp"
#include "execute.hpp"

namespace Torque {
enum class DsoRunStatus { returned, format_error, relocation_required, vm_error };
struct DsoRunResult {
  DsoRunStatus status = DsoRunStatus::format_error;
  DsoError format;
  VmResult execution;
  bool returned() const { return status == DsoRunStatus::returned; }
};

// Reproduction composition policy: validate the whole serialized file before
// executing the seven-operation subset. Identifier uses need a future linker;
// never execute unpatched relocation operands as integer payloads.
DsoRunResult execute_dso(const std::vector<std::uint8_t>& bytes, FloatOrder order,
                         VmLimits limits = {});
} // namespace Torque
