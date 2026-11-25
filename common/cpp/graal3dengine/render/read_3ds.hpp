// The 3D Studio `.3ds` reader (GameShape3DS in 5.12, Shape3ds in 4.04r2).
//
// Written from the public 3DS chunk format: each chunk is a 16-bit id and
// a 32-bit length that counts its own six header bytes, little-endian.
// Read: the editor block's objects (name, vertices, texture coordinates,
// faces, the face groups that name a material, the local matrix) and its
// materials (name, diffuse colour, texture file name).
//
// Graal's rules (Graal_analysis torque/engine-and-formats.md, the Seihai
// gserver's lab notes): a mesh whose name starts with `Col-` is a
// collision hull, yet the real 5.12 draws it like any other (lab T3D-032:
// a 2.8-unit hull showed instead of the cube), so it is kept in both
// lists; a face with no material is not drawn
// ("a .3ds shape with only vertices and faces loads without an error but
// is not drawn", 5.12 and 4.20r6, lab 2026-11-20).
//
// Vertices in a .3ds are stored in world space already (the local matrix
// only says where the object's pivot is), so they are used as stored.
#pragma once

#include "mesh.hpp"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace graal3d::render {

// Limits (rebuild policy): a file over these is refused.
constexpr size_t k3dsMaxVertices = 65535;  // the format's own 16-bit counts
constexpr size_t k3dsMaxObjects = 4096;

bool read3ds(const uint8_t* data, size_t size, Shape& out, std::string& error);
bool read3ds(const std::vector<uint8_t>& bytes, Shape& out, std::string& error);

}  // namespace graal3d::render
