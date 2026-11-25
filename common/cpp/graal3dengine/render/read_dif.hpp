// The Torque interior (`.dif`) reader: InteriorResource version 44 with
// Interior version 0, the only versions the Graal clients load (Graal_analysis
// torque/stock-baseline-mbg-2026-11-25.md: InteriorResource / Interior /
// ForceField = 44 / 0 / 0 in 4.04r2, 5.12 and stock TGE).
//
// Layout from the Marble Blast web port's DIF reader (hx_dif, MIT), which
// reads the TGE-era files of the same versions. Drawn: the first detail
// level's surfaces. Each surface is a run of the winding list (point
// indices) drawn as a triangle strip, textured by its material and its
// texture-generation planes (u = planeX . p + dX, v = planeY . p + dY).
// Null surfaces, the other detail levels, sub-objects, triggers, path
// followers, force fields and lightmaps are not read or drawn.
#pragma once

#include "mesh.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace graal3d::render {

constexpr uint32_t kDifResourceVersion = 44;
constexpr int32_t kDifInteriorVersion = 0;
constexpr size_t kDifMaxCount = 1u << 22;  // any one list's entries (rebuild policy)

bool readDif(const uint8_t* data, size_t size, Shape& out, std::string& error);
bool readDif(const std::vector<uint8_t>& bytes, Shape& out, std::string& error);

}  // namespace graal3d::render
