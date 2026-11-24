#include "texture.hpp"

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

}  // namespace graal3d::render
