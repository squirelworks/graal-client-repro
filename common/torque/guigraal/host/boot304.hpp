#pragma once

// The engine set-up tq-play and graal304-torque share: the 3.04 classes,
// input, prefs, text lists, the TorqueScript compiler, and host stubs for
// the video functions the boot calls.

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "../../console/engine/engine.hpp"

namespace Torque {

// Registers everything on `engine` and points it at the install and prefs
// folders. `print` gets each console line (it is also kept for the F2
// console). Does not run main.cs.
void setup_engine_304(Engine& engine, const std::string& root, const std::string& prefs,
                      std::function<void(const std::string&)> print);

// True for a 3.153 install (scripts2D/main2D.cs). setup_engine_304 then
// reads its .dso files with big-endian floats and execs scripts by name.
bool is_install_3153(const Engine& engine);

// Runs the install's own root main.cs, as the original does.
void boot_304(Engine& engine);

// A steps file: one TorqueScript statement per line at a time in ms
// (tq-play's --steps). Lines starting with # are comments.
struct Step {
  unsigned at = 0;
  std::string code;
};
bool read_steps(const std::string& path, std::vector<Step>& out);

// A 24-bit BMP of 0xAARRGGBB pixels, rows top down.
bool write_bmp(const std::string& path, const std::uint32_t* pixels, int width, int height);

} // namespace Torque
