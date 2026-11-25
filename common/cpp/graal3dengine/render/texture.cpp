#include "texture.hpp"

#include <algorithm>
#include <cmath>

namespace graal3d::render {

uint32_t Texture::sample(float u, float v) const {
  if (empty()) return packRgba(255, 255, 255);
  float fu = u - std::floor(u), fv = v - std::floor(v);
  int x = int(fu * width), y = int(fv * height);
  if (x >= width) x = width - 1;
  if (y >= height) y = height - 1;
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  return pixels[size_t(y) * width + x];
}

uint32_t Texture::sampleBilinear(float u, float v, bool clamp) const {
  if (empty()) return packRgba(255, 255, 255);
  if (!std::isfinite(u) || !std::isfinite(v)) return sample(0, 0);
  if (clamp) {
    u = std::min(std::max(u, 0.0f), 1.0f);
    v = std::min(std::max(v, 0.0f), 1.0f);
  } else {
    u -= std::floor(u);
    v -= std::floor(v);
  }
  // Texel centres sit at half steps.
  const float x = u * float(width) - 0.5f, y = v * float(height) - 0.5f;
  const float fx0 = std::floor(x), fy0 = std::floor(y);
  const float ax = x - fx0, ay = y - fy0;
  auto cell = [&](int i, int n) {
    if (clamp) return i < 0 ? 0 : i >= n ? n - 1 : i;
    i %= n;
    return i < 0 ? i + n : i;
  };
  const int x0 = cell(int(fx0), width), x1 = cell(int(fx0) + 1, width);
  const int y0 = cell(int(fy0), height), y1 = cell(int(fy0) + 1, height);
  const uint32_t c00 = pixels[size_t(y0) * width + x0], c10 = pixels[size_t(y0) * width + x1];
  const uint32_t c01 = pixels[size_t(y1) * width + x0], c11 = pixels[size_t(y1) * width + x1];
  uint32_t out = 0;
  for (int shift = 0; shift < 32; shift += 8) {
    const float top = float((c00 >> shift) & 0xFF) * (1 - ax) + float((c10 >> shift) & 0xFF) * ax;
    const float bottom = float((c01 >> shift) & 0xFF) * (1 - ax) + float((c11 >> shift) & 0xFF) * ax;
    const float c = top * (1 - ay) + bottom * ay;
    out |= uint32_t(std::min(255.0f, c + 0.5f)) << shift;
  }
  return out;
}

}  // namespace graal3d::render
