#pragma once

// Game304 backed by the Pascal 3.04 game library, loaded at run time.

#include <memory>
#include <string>

#include "game304.hpp"

namespace Torque {

// Loads the library at lib_path and opens a session on the install at
// install_dir. Null, with the reason in error, when either fails.
std::unique_ptr<Game304> load_pascal_game304(const std::string& lib_path, const std::string& install_dir,
                                             std::string& error);

} // namespace Torque
