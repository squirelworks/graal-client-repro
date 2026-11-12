#include "jpeg.hpp"

#define STB_IMAGE_STATIC
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

namespace Torque::Gui {

bool decode_jpeg(const std::uint8_t* data, std::size_t size, Image& out, std::string& error) {
  if (!data || size < 4 || size > std::size_t(64) * 1024 * 1024) { error = "not a JPEG"; return false; }
  int w = 0, h = 0, n = 0;
  if (!stbi_info_from_memory(data, static_cast<int>(size), &w, &h, &n)) {
    error = stbi_failure_reason() ? stbi_failure_reason() : "not a JPEG";
    return false;
  }
  if (w <= 0 || h <= 0 || w > kMaxImageSide || h > kMaxImageSide ||
      std::size_t(w) * std::size_t(h) > kMaxImagePixels) {
    error = "JPEG too large";
    return false;
  }
  unsigned char* rgb = stbi_load_from_memory(data, static_cast<int>(size), &w, &h, &n, 3);
  if (!rgb) {
    error = stbi_failure_reason() ? stbi_failure_reason() : "bad JPEG";
    return false;
  }
  Image image(w, h);
  for (std::size_t i = 0; i < image.pixels.size(); ++i)
    image.pixels[i] = Color{rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2], 255};
  stbi_image_free(rgb);
  out = std::move(image);
  return true;
}

}  // namespace Torque::Gui
