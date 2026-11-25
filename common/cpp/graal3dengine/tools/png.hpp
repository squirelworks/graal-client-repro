// A small PNG writer for the tools (RGB, one IDAT, zlib from the system).
#pragma once

#include <cstdint>
#include <string>

namespace graal3d::tools {

// Pixels as the renderer packs them (R in the low byte); alpha is dropped.
// False when the file cannot be written.
bool writePng(const std::string& path, const uint32_t* pixels, int width, int height, int stride);

}  // namespace graal3d::tools
