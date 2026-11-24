// stb_image's implementation for the world renderer, in its own file: it
// is third-party code (common/cpp/third_party/stb) and is built without
// -Werror. Static, so it never clashes with the engine library's copy.
#define STB_IMAGE_STATIC
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#define STBI_ONLY_TGA
#define STBI_NO_STDIO
// No thread-local flip flags (see common/cpp/graalengine/src/stb_impl.cpp).
#define STBI_NO_THREAD_LOCALS
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include "texture.hpp"

namespace graal3d::render {

bool decodeImage(const uint8_t* data, size_t size, Texture& out, std::string& error) {
  if (size > 0x7FFFFFFF) {
    error = "image too large";
    return false;
  }
  int w = 0, h = 0, comp = 0;
  stbi_uc* px = stbi_load_from_memory(data, int(size), &w, &h, &comp, 4);
  if (!px) {
    const char* why = stbi_failure_reason();
    error = why ? why : "unreadable image";
    return false;
  }
  if (w <= 0 || h <= 0 || w > kMaxTextureSide || h > kMaxTextureSide) {
    stbi_image_free(px);
    error = "image size out of range";
    return false;
  }
  out.width = w;
  out.height = h;
  out.pixels.assign(size_t(w) * h, 0);
  for (size_t i = 0; i < out.pixels.size(); ++i)
    out.pixels[i] = packRgba(px[i * 4], px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3]);
  stbi_image_free(px);
  return true;
}

}  // namespace graal3d::render
