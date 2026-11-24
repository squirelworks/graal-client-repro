#include "mesh.hpp"

#include <limits>

namespace graal3d::render {

void Shape::computeBounds() {
  const float inf = std::numeric_limits<float>::infinity();
  boundsMin = {inf, inf, inf};
  boundsMax = {-inf, -inf, -inf};
  bool any = false;
  for (const Mesh& m : meshes)
    for (const Vertex& v : m.vertices) {
      any = true;
      if (v.position.x < boundsMin.x) boundsMin.x = v.position.x;
      if (v.position.y < boundsMin.y) boundsMin.y = v.position.y;
      if (v.position.z < boundsMin.z) boundsMin.z = v.position.z;
      if (v.position.x > boundsMax.x) boundsMax.x = v.position.x;
      if (v.position.y > boundsMax.y) boundsMax.y = v.position.y;
      if (v.position.z > boundsMax.z) boundsMax.z = v.position.z;
    }
  if (!any) boundsMin = boundsMax = {0, 0, 0};
}

void computeNormals(Mesh& mesh) {
  for (Vertex& v : mesh.vertices) v.normal = {0, 0, 0};
  const size_t n = mesh.vertices.size();
  for (const Triangle& t : mesh.triangles) {
    if (t.v[0] >= n || t.v[1] >= n || t.v[2] >= n) continue;
    const V3& a = mesh.vertices[t.v[0]].position;
    const V3& b = mesh.vertices[t.v[1]].position;
    const V3& c = mesh.vertices[t.v[2]].position;
    const V3 face = cross(b - a, c - a);  // length is twice the area
    for (uint32_t i : t.v) mesh.vertices[i].normal = mesh.vertices[i].normal + face;
  }
  for (Vertex& v : mesh.vertices) v.normal = normalize(v.normal);
}

}  // namespace graal3d::render
