// Small vector and matrix types for the world renderer.
//
// Torque's world is z-up; an object or camera with no rotation looks
// along +y with +x to its right. Matrices here are column-vector style:
// p' = M * p, with the translation in the last column.
#pragma once

#include <cmath>

namespace graal3d::render {

struct V3 {
  float x = 0, y = 0, z = 0;
  V3() = default;
  V3(float x_, float y_, float z_) : x(x_), y(y_), z(z_) {}
  V3 operator+(const V3& o) const { return {x + o.x, y + o.y, z + o.z}; }
  V3 operator-(const V3& o) const { return {x - o.x, y - o.y, z - o.z}; }
  V3 operator*(float s) const { return {x * s, y * s, z * s}; }
  V3 operator-() const { return {-x, -y, -z}; }
};

inline float dot(const V3& a, const V3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(const V3& a, const V3& b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline float length(const V3& a) { return std::sqrt(dot(a, a)); }
inline V3 normalize(const V3& a) {
  const float l = length(a);
  return l > 1e-12f ? a * (1.0f / l) : V3{0, 0, 0};
}

struct V4 {
  float x = 0, y = 0, z = 0, w = 0;
};

struct M4 {
  float m[4][4] = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}};

  static M4 identity() { return M4{}; }
  static M4 translation(const V3& t) {
    M4 r;
    r.m[0][3] = t.x;
    r.m[1][3] = t.y;
    r.m[2][3] = t.z;
    return r;
  }
  static M4 scale(const V3& s) {
    M4 r;
    r.m[0][0] = s.x;
    r.m[1][1] = s.y;
    r.m[2][2] = s.z;
    return r;
  }
  // A right-handed rotation of `angle` radians about `axis`.
  static M4 rotation(const V3& axis, float angle) {
    M4 r;
    const V3 a = normalize(axis);
    if (a.x == 0 && a.y == 0 && a.z == 0) return r;
    const float c = std::cos(angle), s = std::sin(angle), t = 1 - c;
    r.m[0][0] = t * a.x * a.x + c;
    r.m[0][1] = t * a.x * a.y - s * a.z;
    r.m[0][2] = t * a.x * a.z + s * a.y;
    r.m[1][0] = t * a.x * a.y + s * a.z;
    r.m[1][1] = t * a.y * a.y + c;
    r.m[1][2] = t * a.y * a.z - s * a.x;
    r.m[2][0] = t * a.x * a.z - s * a.y;
    r.m[2][1] = t * a.y * a.z + s * a.x;
    r.m[2][2] = t * a.z * a.z + c;
    return r;
  }

  M4 operator*(const M4& o) const {
    M4 r;
    for (int i = 0; i < 4; ++i)
      for (int j = 0; j < 4; ++j) {
        float v = 0;
        for (int k = 0; k < 4; ++k) v += m[i][k] * o.m[k][j];
        r.m[i][j] = v;
      }
    return r;
  }
  V3 point(const V3& p) const {
    return {m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z + m[0][3],
            m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z + m[1][3],
            m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z + m[2][3]};
  }
  V3 vector(const V3& v) const {
    return {m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z, m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
            m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z};
  }
  V4 project(const V3& p) const {
    return {m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z + m[0][3],
            m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z + m[1][3],
            m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z + m[2][3],
            m[3][0] * p.x + m[3][1] * p.y + m[3][2] * p.z + m[3][3]};
  }
  // The inverse of a rotation-and-translation matrix (no scale).
  M4 rigidInverse() const {
    M4 r;
    for (int i = 0; i < 3; ++i)
      for (int j = 0; j < 3; ++j) r.m[i][j] = m[j][i];
    for (int i = 0; i < 3; ++i) r.m[i][3] = -(r.m[i][0] * m[0][3] + r.m[i][1] * m[1][3] + r.m[i][2] * m[2][3]);
    return r;
  }
};

// The rotation a Graal 3D client gives an axis and angle from the wire.
// The clients turn the opposite way from the right-hand rule: a positive
// angle about +x tilts the view down, one about +z turns it right (the
// Seihai gserver's lab notes, bin/docs/graal3d.md, 2026-11-20).
inline M4 graalRotation(const V3& axis, float angle) { return M4::rotation(axis, -angle); }

// A camera's transform from the wire: position, then axis and angle.
inline M4 graalTransform(const V3& position, const V3& axis, float angle) {
  return M4::translation(position) * graalRotation(axis, angle);
}

// A shape's transform from the wire: the same rule as the camera's (lab
// follow-up 10: a positive angle about +z turns a cube clockwise seen
// from above, its +x face to -y at 90 degrees).
inline M4 graalShapeTransform(const V3& position, const V3& axis, float angle) {
  return graalTransform(position, axis, angle);
}

}  // namespace graal3d::render
