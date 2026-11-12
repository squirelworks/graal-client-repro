#pragma once

// TorqueScript source compiler for the Graal 3.x console: compiles a plain
// .cs script (the root main.cs, the exported prefs.cs / config.cs, console
// input) into a DSO v33 code block with Graal's opcode numbering, so the same
// loader and VM handle compiled and source scripts.

#include "../dso.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace Torque {

struct CompileError {
  int line = 0;  // 1-based source line
  std::string message;
};

// On failure, `output` is unchanged and `error` names the line.
bool compile_script(const std::string& source, DsoBlock& output, CompileError& error);

// Serializes a block in the DSO v33 file layout. Code words below 0xFF take
// one byte; others take 0xFF and a little-endian U32. Integer fields are
// little-endian; float tables use the given order.
std::vector<std::uint8_t> write_dso(const DsoBlock& block, FloatOrder order);

} // namespace Torque
