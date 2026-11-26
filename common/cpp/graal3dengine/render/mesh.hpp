// The one in-memory shape every file reader produces.
#pragma once

#include "math.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace graal3d::render {

struct Material {
  std::string name;
  std::string texture;  // file name as the shape gives it; empty for none
  float color[3] = {1, 1, 1};  // diffuse, 0..1
  bool alphaTest = true;       // see RasterState::alphaTest
};

struct Vertex {
  V3 position;
  V3 normal;
  float u = 0, v = 0;
};

struct Triangle {
  uint32_t v[3] = {0, 0, 0};
  int material = -1;  // index into Shape::materials; -1 = none (not drawn)
};

struct Mesh {
  std::string name;
  std::vector<Vertex> vertices;
  std::vector<Triangle> triangles;
  // When not empty: the mesh is an additive layer over the shape's earlier
  // meshes, weighted by this weightSize-square map read at texture
  // coordinates times weightScale (RasterState::additive). The terrain's
  // material layers.
  std::vector<float> weightMap;
  int weightSize = 0;
  float weightScale = 1;
};

struct Shape {
  // What the shape was read from; the 5.12 lights each kind its own way.
  enum Kind { k3ds, kDts, kDif, kFt, kTerrain };
  Kind kind = k3ds;
  std::vector<Material> materials;
  std::vector<Mesh> meshes;     // drawn
  std::vector<Mesh> collision;  // the collision hulls (a .3ds Col- mesh is also in meshes: drawn)
  V3 boundsMin, boundsMax;

  void computeBounds();
};

// Fills each vertex normal with the area-weighted average of the normals
// of the triangles that use it.
void computeNormals(Mesh& mesh);

}  // namespace graal3d::render
