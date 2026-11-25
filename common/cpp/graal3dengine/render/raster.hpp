// The software rasteriser: perspective-correct textured triangles with a
// depth buffer, Gouraud lighting and per-vertex linear fog. The pixels
// are the rebuild's own; the original draws through OpenGL (or Torque's
// Direct3D wrapper) and no pixel match is claimed.
#pragma once

#include "math.hpp"
#include "texture.hpp"

#include <vector>

namespace graal3d::render {

// The camera: where it is, how it is turned (its own +y is forward, +x
// right, +z up) and its horizontal field of view.
struct View {
  M4 cameraToWorld;
  float fovDegrees = 90.0f;
  float nearPlane = 0.1f;
  float farPlane = 1000.0f;  // nothing past it is drawn
};

struct RasterVertex {
  V3 position;           // world space
  float u = 0, v = 0;    // texture coordinates
  float light[3] = {1, 1, 1};
  float fog = 0;         // 0 = none, 1 = all fog colour
};

struct RasterState {
  const Texture* texture = nullptr;  // null: untextured
  float color[3] = {1, 1, 1};         // multiplies the texel
  uint32_t fogColor = 0;
  bool depthTest = true;
  bool depthWrite = true;
};

class Rasterizer {
 public:
  explicit Rasterizer(Frame frame);

  void setView(const View& view);
  const View& view() const { return view_; }
  const M4& worldToCamera() const { return worldToCamera_; }

  void clear(uint32_t color);
  void clearDepth();
  void drawTriangle(const RasterVertex& a, const RasterVertex& b, const RasterVertex& c, const RasterState& s);

  // For tests: how many pixels the last frame wrote.
  long pixelsWritten() const { return written_; }

 private:
  // A triangle clipped by six planes has at most nine corners.
  static constexpr int kMaxClipVertices = 9;
  struct ClipVertex {
    float x, y, d;  // camera space: right, up, forward (depth)
    float u, v, l[3], fog;
  };
  void drawClipped(const ClipVertex* poly, int count, const RasterState& s);

  Frame frame_;
  std::vector<float> depth_;  // 1 / depth; 0 = empty
  View view_;
  M4 worldToCamera_;
  float focal_ = 1;  // pixels per unit at depth 1
  long written_ = 0;
};

}  // namespace graal3d::render
