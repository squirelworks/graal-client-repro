#pragma once

#include "ast.hpp"

#include <string>

namespace Torque {
namespace Script {

struct ParseError {
  int line = 0;
  std::string message;
};

// Parses a whole script. On failure returns false, leaves `out` empty and
// fills `error` with the 1-based line and a message.
bool parse_script(const std::string& source, StmtList& out, ParseError& error);

// Deep copy, used where one source expression is compiled more than once
// (each switch case compares against the switch value again).
ExprPtr clone_expr(const Expr& e);

} // namespace Script
} // namespace Torque
