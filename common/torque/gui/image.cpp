#include "image.hpp"

#include <zlib.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>

namespace Torque::Gui {

Image::Image(int w, int h, Color fill)
    : width(w), height(h), pixels(std::size_t(w > 0 ? w : 0) * (h > 0 ? h : 0), fill) {}

namespace {

const std::uint8_t kSignature[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};

std::uint32_t be32(const std::uint8_t* p) {
  return (std::uint32_t(p[0]) << 24) | (std::uint32_t(p[1]) << 16) |
         (std::uint32_t(p[2]) << 8) | std::uint32_t(p[3]);
}

int paeth(int a, int b, int c) {
  int p = a + b - c;
  int pa = std::abs(p - a), pb = std::abs(p - b), pc = std::abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

int channels_for(int color_type) {
  switch (color_type) {
    case 0: return 1;  // gray
    case 2: return 3;  // RGB
    case 3: return 1;  // palette index
    case 4: return 2;  // gray + alpha
    case 6: return 4;  // RGBA
    default: return 0;
  }
}

bool depth_allowed(int color_type, int depth) {
  switch (color_type) {
    case 0: return depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16;
    case 3: return depth == 1 || depth == 2 || depth == 4 || depth == 8;
    case 2: case 4: case 6: return depth == 8 || depth == 16;
    default: return false;
  }
}

// Inflates exactly `expected` bytes. Extra output or a short stream fails.
bool inflate_exact(const std::vector<std::uint8_t>& in, std::vector<std::uint8_t>& out,
                   std::size_t expected) {
  out.assign(expected, 0);
  z_stream zs{};
  if (inflateInit(&zs) != Z_OK) return false;
  zs.next_in = const_cast<Bytef*>(in.data());
  zs.avail_in = uInt(in.size());
  zs.next_out = out.data();
  zs.avail_out = uInt(expected);
  int rc = inflate(&zs, Z_FINISH);
  bool ok = rc == Z_STREAM_END && zs.avail_out == 0;
  if (rc == Z_BUF_ERROR && zs.avail_out == 0) ok = false;  // more data than expected
  inflateEnd(&zs);
  return ok;
}

}  // namespace

bool decode_png(const std::uint8_t* data, std::size_t size, Image& out, std::string& error,
                std::size_t* consumed) {
  auto fail = [&](const char* message) { error = message; return false; };
  if (size < 8 || std::equal(kSignature, kSignature + 8, data) == false)
    return fail("not a PNG signature");

  std::size_t pos = 8;
  bool have_header = false, have_palette = false, seen_data = false, data_closed = false;
  bool ended = false;
  std::uint32_t width = 0, height = 0;
  int depth = 0, color_type = 0;
  std::vector<Color> palette;
  bool have_key = false;
  std::array<std::uint16_t, 3> key{};  // tRNS colour key for gray / RGB
  std::vector<std::uint8_t> compressed;

  while (!ended) {
    if (size - pos < 12) return fail("truncated chunk");
    std::uint32_t length = be32(data + pos);
    if (length > 0x7fffffffu || length > size - pos - 12) return fail("chunk length past end");
    const std::uint8_t* type = data + pos + 4;
    const std::uint8_t* body = data + pos + 8;
    std::uint32_t stored_crc = be32(body + length);
    if (crc32(crc32(0, nullptr, 0), type, length + 4) != stored_crc) return fail("chunk CRC mismatch");
    std::string name(reinterpret_cast<const char*>(type), 4);

    if (!have_header && name != "IHDR") return fail("IHDR is not first");
    if (name == "IHDR") {
      if (have_header) return fail("second IHDR");
      if (length != 13) return fail("bad IHDR length");
      width = be32(body);
      height = be32(body + 4);
      depth = body[8];
      color_type = body[9];
      if (width == 0 || height == 0 || width > kMaxImageSide || height > kMaxImageSide ||
          std::size_t(width) * height > kMaxImagePixels)
        return fail("image size out of range");
      if (!depth_allowed(color_type, depth)) return fail("unsupported colour type or depth");
      if (body[10] != 0 || body[11] != 0) return fail("unknown compression or filter method");
      if (body[12] != 0) return fail("interlaced PNG not supported");
      have_header = true;
    } else if (name == "PLTE") {
      if (seen_data || have_palette || length % 3 != 0 || length == 0 || length > 768)
        return fail("bad PLTE");
      for (std::uint32_t i = 0; i < length; i += 3)
        palette.push_back({body[i], body[i + 1], body[i + 2], 255});
      have_palette = true;
    } else if (name == "tRNS") {
      if (seen_data) return fail("tRNS after IDAT");
      if (color_type == 3) {
        if (!have_palette || length > palette.size()) return fail("bad tRNS");
        for (std::uint32_t i = 0; i < length; ++i) palette[i].a = body[i];
      } else if (color_type == 0 && length == 2) {
        key[0] = std::uint16_t((body[0] << 8) | body[1]);
        have_key = true;
      } else if (color_type == 2 && length == 6) {
        for (int i = 0; i < 3; ++i) key[i] = std::uint16_t((body[2 * i] << 8) | body[2 * i + 1]);
        have_key = true;
      } else {
        return fail("bad tRNS");
      }
    } else if (name == "IDAT") {
      if (color_type == 3 && !have_palette) return fail("palette image without PLTE");
      if (data_closed) return fail("IDAT chunks not consecutive");
      compressed.insert(compressed.end(), body, body + length);
      seen_data = true;
    } else if (name == "IEND") {
      ended = true;
    } else if ((type[0] & 0x20) == 0) {
      return fail("unknown critical chunk");
    }
    if (seen_data && name != "IDAT") data_closed = true;
    pos += std::size_t(length) + 12;
  }
  if (compressed.empty()) return fail("no image data");

  const int channels = channels_for(color_type);
  const std::size_t bits_per_pixel = std::size_t(channels) * depth;
  const std::size_t row_bytes = (std::size_t(width) * bits_per_pixel + 7) / 8;
  const std::size_t bpp = bits_per_pixel < 8 ? 1 : bits_per_pixel / 8;
  std::vector<std::uint8_t> raw;
  if (!inflate_exact(compressed, raw, (row_bytes + 1) * height))
    return fail("image data does not inflate to the declared size");

  // Undo the per-row filters in place.
  std::vector<std::uint8_t> zero(row_bytes, 0);
  for (std::uint32_t y = 0; y < height; ++y) {
    std::uint8_t* row = raw.data() + y * (row_bytes + 1);
    std::uint8_t filter = row[0];
    std::uint8_t* cur = row + 1;
    const std::uint8_t* prev = y ? raw.data() + (y - 1) * (row_bytes + 1) + 1 : zero.data();
    for (std::size_t i = 0; i < row_bytes; ++i) {
      int a = i >= bpp ? cur[i - bpp] : 0;
      int b = prev[i];
      int c = i >= bpp ? prev[i - bpp] : 0;
      int add;
      switch (filter) {
        case 0: add = 0; break;
        case 1: add = a; break;
        case 2: add = b; break;
        case 3: add = (a + b) / 2; break;
        case 4: add = paeth(a, b, c); break;
        default: return fail("unknown row filter");
      }
      cur[i] = std::uint8_t(cur[i] + add);
    }
  }

  Image image(static_cast<int>(width), static_cast<int>(height));
  for (std::uint32_t y = 0; y < height; ++y) {
    const std::uint8_t* row = raw.data() + y * (row_bytes + 1) + 1;
    for (std::uint32_t x = 0; x < width; ++x) {
      auto sample = [&](int channel) -> std::uint16_t {
        std::size_t index = std::size_t(x) * channels + channel;
        if (depth == 16) return std::uint16_t((row[2 * index] << 8) | row[2 * index + 1]);
        if (depth == 8) return row[index];
        std::size_t bit = index * depth;
        int shift = 8 - depth - int(bit % 8);
        return std::uint16_t((row[bit / 8] >> shift) & ((1 << depth) - 1));
      };
      auto to8 = [&](std::uint16_t v) -> std::uint8_t {
        if (depth == 16) return std::uint8_t(v >> 8);
        if (depth == 8) return std::uint8_t(v);
        return std::uint8_t(v * 255 / ((1 << depth) - 1));
      };
      Color px;
      switch (color_type) {
        case 0: {
          std::uint16_t v = sample(0);
          std::uint8_t g = to8(v);
          px = {g, g, g, std::uint8_t(have_key && v == key[0] ? 0 : 255)};
          break;
        }
        case 2: {
          std::uint16_t r = sample(0), g = sample(1), b = sample(2);
          bool keyed = have_key && r == key[0] && g == key[1] && b == key[2];
          px = {to8(r), to8(g), to8(b), std::uint8_t(keyed ? 0 : 255)};
          break;
        }
        case 3: {
          std::uint16_t index = sample(0);
          if (index >= palette.size()) return fail("palette index out of range");
          px = palette[index];
          break;
        }
        case 4: {
          std::uint8_t g = to8(sample(0));
          px = {g, g, g, to8(sample(1))};
          break;
        }
        default:
          px = {to8(sample(0)), to8(sample(1)), to8(sample(2)), to8(sample(3))};
      }
      image.at(int(x), int(y)) = px;
    }
  }
  out = std::move(image);
  if (consumed) *consumed = pos;
  return true;
}

bool decode_png(const std::vector<std::uint8_t>& bytes, Image& out, std::string& error) {
  std::size_t used = 0;
  Image image;
  if (!decode_png(bytes.data(), bytes.size(), image, error, &used)) return false;
  if (used != bytes.size()) { error = "bytes after IEND"; return false; }
  out = std::move(image);
  return true;
}

namespace {
void put_be32(std::vector<std::uint8_t>& out, std::uint32_t v) {
  for (int s = 24; s >= 0; s -= 8) out.push_back(std::uint8_t(v >> s));
}
void put_chunk(std::vector<std::uint8_t>& out, const char* type, const std::vector<std::uint8_t>& body) {
  put_be32(out, std::uint32_t(body.size()));
  std::size_t start = out.size();
  out.insert(out.end(), type, type + 4);
  out.insert(out.end(), body.begin(), body.end());
  put_be32(out, crc32(crc32(0, nullptr, 0), out.data() + start, uInt(body.size() + 4)));
}
}  // namespace

std::vector<std::uint8_t> encode_png(const Image& image) {
  std::vector<std::uint8_t> out(kSignature, kSignature + 8);
  std::vector<std::uint8_t> header;
  put_be32(header, std::uint32_t(image.width));
  put_be32(header, std::uint32_t(image.height));
  header.insert(header.end(), {8, 6, 0, 0, 0});
  put_chunk(out, "IHDR", header);

  std::vector<std::uint8_t> raw;
  raw.reserve(std::size_t(image.height) * (std::size_t(image.width) * 4 + 1));
  for (int y = 0; y < image.height; ++y) {
    raw.push_back(0);
    for (int x = 0; x < image.width; ++x) {
      const Color& c = image.at(x, y);
      raw.insert(raw.end(), {c.r, c.g, c.b, c.a});
    }
  }
  uLongf packed_size = compressBound(uLong(raw.size()));
  std::vector<std::uint8_t> packed(packed_size);
  compress2(packed.data(), &packed_size, raw.data(), uLong(raw.size()), 9);
  packed.resize(packed_size);
  put_chunk(out, "IDAT", packed);
  put_chunk(out, "IEND", {});
  return out;
}

bool read_file(const std::string& path, std::vector<std::uint8_t>& out, std::string& error) {
  std::ifstream in(path, std::ios::binary);
  if (!in) { error = "cannot open " + path; return false; }
  out.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
  return true;
}

bool write_file(const std::string& path, const std::vector<std::uint8_t>& bytes, std::string& error) {
  std::ofstream out(path, std::ios::binary);
  if (!out.write(reinterpret_cast<const char*>(bytes.data()), std::streamsize(bytes.size()))) {
    error = "cannot write " + path;
    return false;
  }
  return true;
}

}  // namespace Torque::Gui
