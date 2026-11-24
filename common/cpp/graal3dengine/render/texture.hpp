// Textures and the frame the renderer draws into.
//
// Pixels are 32-bit RGBA with red in the lowest byte (the byte order
// R, G, B, A in memory on a little-endian machine), the layout of
// Torque::Gui::Color and of the canvases the repro clients present.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace graal3d::render {

constexpr int kMaxTextureSide = 4096;  // rebuild policy

inline uint32_t packRgba(uint32_t r, uint32_t g, uint32_t b, uint32_t a = 255) {
  return r | g << 8 | b << 16 | a << 24;
}
inline uint8_t red(uint32_t c) { return uint8_t(c); }
inline uint8_t green(uint32_t c) { return uint8_t(c >> 8); }
inline uint8_t blue(uint32_t c) { return uint8_t(c >> 16); }
inline uint8_t alpha(uint32_t c) { return uint8_t(c >> 24); }

struct Texture {
  int width = 0, height = 0;
  std::vector<uint32_t> pixels;  // row-major, top row first
  bool empty() const { return width <= 0 || height <= 0; }
  // Nearest texel, wrapping in both directions.
  uint32_t sample(float u, float v) const;
};

// PNG, JPEG, GIF (first frame), BMP and TGA, through stb_image.
bool decodeImage(const uint8_t* data, size_t size, Texture& out, std::string& error);

// A view onto pixels someone else owns: a canvas, a window's buffer or a
// test's vector. `stride` counts pixels.
struct Frame {
  uint32_t* pixels = nullptr;
  int width = 0, height = 0, stride = 0;
  uint32_t& at(int x, int y) { return pixels[size_t(y) * stride + x]; }
  uint32_t at(int x, int y) const { return pixels[size_t(y) * stride + x]; }
};

}  // namespace graal3d::render
