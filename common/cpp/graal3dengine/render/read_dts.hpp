// The Torque `.dts` shape reader (versions 19 to 24).
//
// Layout from the Torque engine's TSShape::read / assembleShape,
// TSMesh::assemble and, for versions 19 to 21, Sequence::read and the
// separate skin list (Torque3D, MIT; render/README.md lists the sources),
// cross-checked with the Marble Blast web port's DTS parser (MIT).
// Graal's bounds are the client's own (Graal_analysis
// torque/stock-tge-reference-mbg-2026-11-25.md, [bin 5.12]): 5.12 accepts
// versions 17 to 24, 4.04r2 up to 24. Versions 17 and 18 use the older
// shape stream (no three-stream block) and are refused with a clear error,
// as is anything above 24.
//
// The file is a version word, then one block that holds three streams
// (32-bit, 16-bit and 8-bit values) read side by side with a guard value
// checked across all three after each section; then the sequences and the
// material list. Drawn: the shape in its default pose at its highest
// detail level. Each standard mesh is placed by its object's node (the
// chain of default rotations and translations); a skin mesh's initial
// vertices are already in shape space. Triangle lists, strips and fans
// become triangles. A primitive flagged as having no material is not drawn.
// Sorted meshes are drawn as standard ones (their translucency order is
// not kept); decal meshes, a class the 5.12 lacks, are refused.
#pragma once

#include "mesh.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace graal3d::render {

constexpr int kDtsMinVersion = 19;  // read by this reader
constexpr int kDtsMaxVersion = 24;  // the clients' own upper bound
// Limits (rebuild policy).
constexpr size_t kDtsMaxCount = 1u << 20;  // any one table's entries

bool readDts(const uint8_t* data, size_t size, Shape& out, std::string& error);
bool readDts(const std::vector<uint8_t>& bytes, Shape& out, std::string& error);

}  // namespace graal3d::render
