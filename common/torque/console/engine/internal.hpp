#pragma once

#include "engine.hpp"

namespace Torque {

struct Engine::Frame {
  std::shared_ptr<CodeBlock> block;
  const Function* fn = nullptr;
  std::map<std::string, std::pair<std::string, Value>> locals;  // lower -> (name, value)
};

struct ScriptError {
  std::string message;
};

} // namespace Torque
