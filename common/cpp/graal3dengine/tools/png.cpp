#include "png.hpp"

#include <zlib.h>

#include <cstdio>
#include <vector>

namespace graal3d::tools {
namespace {

void be32(std::string& s, uint32_t v) {
  s += char(v >> 24);
  s += char(v >> 16);
  s += char(v >> 8);
  s += char(v);
}

void chunk(std::string& out, const char* type, const std::string& data) {
  be32(out, uint32_t(data.size()));
  std::string body(type, 4);
  body += data;
  out += body;
  be32(out, uint32_t(crc32(0, reinterpret_cast<const Bytef*>(body.data()), uInt(body.size()))));
}

}  // namespace

bool writePng(const std::string& path, const uint32_t* pixels, int width, int height, int stride) {
  if (!pixels || width <= 0 || height <= 0 || stride < width) return false;
  std::string raw;
  raw.reserve(size_t(height) * (size_t(width) * 3 + 1));
  for (int y = 0; y < height; ++y) {
    raw += char(0);  // no filter
    for (int x = 0; x < width; ++x) {
      const uint32_t p = pixels[size_t(y) * stride + x];
      raw += char(p & 255);
      raw += char(p >> 8 & 255);
      raw += char(p >> 16 & 255);
    }
  }
  uLongf zn = compressBound(uLong(raw.size()));
  std::vector<Bytef> z(zn);
  if (compress2(z.data(), &zn, reinterpret_cast<const Bytef*>(raw.data()), uLong(raw.size()), 6) != Z_OK) return false;
  std::string out("\x89PNG\r\n\x1a\n", 8);
  std::string ihdr;
  be32(ihdr, uint32_t(width));
  be32(ihdr, uint32_t(height));
  ihdr += std::string("\x08\x02\x00\x00\x00", 5);  // 8-bit RGB
  chunk(out, "IHDR", ihdr);
  chunk(out, "IDAT", std::string(reinterpret_cast<const char*>(z.data()), zn));
  chunk(out, "IEND", "");
  FILE* f = std::fopen(path.c_str(), "wb");
  if (!f) return false;
  const bool ok = std::fwrite(out.data(), 1, out.size(), f) == out.size();
  return std::fclose(f) == 0 && ok;
}

}  // namespace graal3d::tools
