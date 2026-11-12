// RGBA image and a bounded PNG reader/writer for the Torque GUI layer.
//
// The 3.04 GUI reads two kinds of PNG: the theme bitmap arrays under
// common/ui/themes/* (palette, RGB and RGBA images) and the 8-bit gray
// glyph sheets embedded in each .gft font cache (Graal_analysis
// torque/study-torque-clients.md section 4). This reader covers the PNG
// colour types and bit depths of the PNG specification, without
// interlacing, and always returns straight (non-premultiplied) RGBA8.
// Decompression uses the system zlib. Size limits are rebuild policy.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace Torque::Gui {

struct Color {
  std::uint8_t r = 0, g = 0, b = 0, a = 255;
  bool operator==(const Color& o) const {
    return r == o.r && g == o.g && b == o.b && a == o.a;
  }
  bool operator!=(const Color& o) const { return !(*this == o); }
};

struct Image {
  int width = 0;
  int height = 0;
  std::vector<Color> pixels;  // row-major, width * height

  Image() = default;
  Image(int w, int h, Color fill = {0, 0, 0, 0});
  bool empty() const { return width <= 0 || height <= 0; }
  Color& at(int x, int y) { return pixels[std::size_t(y) * width + x]; }
  const Color& at(int x, int y) const { return pixels[std::size_t(y) * width + x]; }
};

// Largest accepted width or height, and largest pixel count.
constexpr int kMaxImageSide = 16384;
constexpr std::size_t kMaxImagePixels = std::size_t(16) * 1024 * 1024;

// Decodes one PNG stream that starts at data[0]. Reading stops after the
// IEND chunk; `consumed` (when given) receives the number of bytes up to
// and including IEND, so a caller can read PNGs packed back to back. On
// failure `out` is left unchanged and `error` names the problem.
bool decode_png(const std::uint8_t* data, std::size_t size, Image& out,
                std::string& error, std::size_t* consumed = nullptr);
bool decode_png(const std::vector<std::uint8_t>& bytes, Image& out, std::string& error);

// Writes an 8-bit RGBA PNG. Used for lab captures of the software canvas.
std::vector<std::uint8_t> encode_png(const Image& image);

bool read_file(const std::string& path, std::vector<std::uint8_t>& out, std::string& error);
bool write_file(const std::string& path, const std::vector<std::uint8_t>& bytes, std::string& error);

}  // namespace Torque::Gui
