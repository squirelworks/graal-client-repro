#include "gen5.hpp"

#include "gtypes.hpp"

#include <bzlib.h>
#include <zlib.h>

#include <algorithm>
#include <vector>

namespace Quattro::Net {

void Cipher::apply(std::string& body, uint8_t type) {
  if (type & 1) return;
  size_t groups = type == kRaw ? kXorGroupsRaw : kXorGroupsPacked;
  groups = std::min(groups, (body.size() + 3) / 4);
  for (size_t g = 0; g < groups; ++g) {
    it_ = it_ * kCipherMul + key_;
    for (size_t j = 0; j < 4; ++j) {
      size_t p = g * 4 + j;
      if (p >= body.size()) break;
      body[p] = static_cast<char>(static_cast<unsigned char>(body[p]) ^ ((it_ >> (8 * j)) & 0xFF));
    }
  }
}

std::string zlib_compress(std::string_view in) {
  uLongf cap = compressBound(static_cast<uLong>(in.size()));
  std::string out(cap, '\0');
  if (compress2(reinterpret_cast<Bytef*>(out.data()), &cap, reinterpret_cast<const Bytef*>(in.data()),
                static_cast<uLong>(in.size()), Z_DEFAULT_COMPRESSION) != Z_OK)
    return {};
  out.resize(cap);
  return out;
}

bool zlib_decompress(std::string_view in, std::string& out, size_t limit) {
  out.clear();
  z_stream zs{};
  if (inflateInit(&zs) != Z_OK) return false;
  zs.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(in.data()));
  zs.avail_in = static_cast<uInt>(in.size());
  char buf[16384];
  int rc = Z_OK;
  while (rc == Z_OK) {
    zs.next_out = reinterpret_cast<Bytef*>(buf);
    zs.avail_out = sizeof buf;
    rc = inflate(&zs, Z_NO_FLUSH);
    if (rc != Z_OK && rc != Z_STREAM_END) break;
    out.append(buf, sizeof buf - zs.avail_out);
    if (out.size() > limit) {
      rc = Z_MEM_ERROR;
      break;
    }
    if (rc == Z_OK && zs.avail_in == 0 && zs.avail_out != 0) {
      rc = Z_DATA_ERROR;  // truncated stream
      break;
    }
  }
  inflateEnd(&zs);
  return rc == Z_STREAM_END;
}

std::string bzip2_compress(std::string_view in) {
  unsigned int cap = static_cast<unsigned int>(in.size() + in.size() / 100 + 600);
  std::string out(cap, '\0');
  // Block size 5, as the 6.x type-6 compressor's call shape (v6x-clients.md).
  if (BZ2_bzBuffToBuffCompress(out.data(), &cap, const_cast<char*>(in.data()),
                               static_cast<unsigned int>(in.size()), 5, 0, 0) != BZ_OK)
    return {};
  out.resize(cap);
  return out;
}

bool bzip2_decompress(std::string_view in, std::string& out, size_t limit) {
  out.clear();
  bz_stream bs{};
  if (BZ2_bzDecompressInit(&bs, 0, 0) != BZ_OK) return false;
  bs.next_in = const_cast<char*>(in.data());
  bs.avail_in = static_cast<unsigned int>(in.size());
  char buf[16384];
  int rc = BZ_OK;
  while (rc == BZ_OK) {
    bs.next_out = buf;
    bs.avail_out = sizeof buf;
    rc = BZ2_bzDecompress(&bs);
    if (rc != BZ_OK && rc != BZ_STREAM_END) break;
    out.append(buf, sizeof buf - bs.avail_out);
    if (out.size() > limit) {
      rc = BZ_MEM_ERROR;
      break;
    }
    if (rc == BZ_OK && bs.avail_in == 0 && bs.avail_out != 0) {
      rc = BZ_DATA_ERROR;
      break;
    }
  }
  BZ2_bzDecompressEnd(&bs);
  return rc == BZ_STREAM_END;
}

uint8_t choose_compression(size_t plain_size, size_t zlib_size) {
  if (plain_size >= 0x1000) return kBzip2;
  if (plain_size >= 0x30) return kZlib;
  return zlib_size < plain_size ? kZlib : kRaw;
}

std::string frame_length(size_t len) {
  std::string out;
  if (len >= 0xFFFF) {
    out = "\xFF\xFF";
    for (int s = 24; s >= 0; s -= 8) out.push_back(static_cast<char>((len >> s) & 0xFF));
  } else {
    out.push_back(static_cast<char>((len >> 8) & 0xFF));
    out.push_back(static_cast<char>(len & 0xFF));
  }
  return out;
}

std::string FrameEncoder::encode(std::string_view plain) {
  std::string body;
  if (login_) {
    login_ = false;
    body = zlib_compress(plain);
  } else {
    std::string z = plain.size() < 0x1000 ? zlib_compress(plain) : std::string();
    uint8_t type = choose_compression(plain.size(), z.size());
    if (type == kBzip2)
      body = bzip2_compress(plain);
    else if (type == kZlib)
      body = std::move(z);
    else
      body = std::string(plain);
    cipher_.apply(body, type);
    body.insert(body.begin(), static_cast<char>(type));
  }
  return frame_length(body.size()) + body;
}

void FrameDecoder::fail(const char* why) {
  error_ = why;
  raw_.clear();
  plain_.clear();
}

bool FrameDecoder::decode_body(std::string_view body, std::string& plain) {
  plain.clear();
  if (body.empty()) return false;
  uint8_t type = static_cast<uint8_t>(body[0]);
  std::string b(body.substr(1));
  cipher_.apply(b, type);
  switch (type) {
    case 1:
    case 2:
      plain = std::move(b);
      return true;
    case 3:
    case 4:
      return zlib_decompress(b, plain);
    case 5:
    case 6:
      return bzip2_decompress(b, plain);
    default:
      return false;
  }
}

void FrameDecoder::feed(std::string_view bytes) {
  if (failed()) return;
  raw_.append(bytes);
  size_t p = 0;
  while (raw_.size() - p >= 2) {
    const auto* u = reinterpret_cast<const unsigned char*>(raw_.data() + p);
    size_t len = (static_cast<size_t>(u[0]) << 8) | u[1];
    size_t head = 2;
    if (len == 0xFFFF) {
      if (raw_.size() - p < 6) break;
      len = (static_cast<size_t>(u[2]) << 24) | (static_cast<size_t>(u[3]) << 16) |
            (static_cast<size_t>(u[4]) << 8) | u[5];
      head = 6;
      if (len > kMaxFrame) return fail("frame from the server is past the limit");
    }
    if (raw_.size() - p < head + len) break;
    std::string plain;
    if (!decode_body(std::string_view(raw_).substr(p + head, len), plain))
      return fail("bad frame from the server");
    p += head + len;
    ++frames_;
    plain_ += plain;
    split();
    if (failed()) return;
  }
  raw_.erase(0, p);
}

void FrameDecoder::split() {
  size_t p = 0;
  const size_t n = plain_.size();
  while (p < n) {
    if (in_raw_) {
      if (n - p < raw_pending_) break;
      std::string_view msg = std::string_view(plain_).substr(p, raw_pending_);
      p += raw_pending_;
      in_raw_ = false;
      raw_pending_ = 0;
      if (!msg.empty() && msg.back() == '\n') msg.remove_suffix(1);
      if (!msg.empty()) on_message_((static_cast<unsigned char>(msg[0]) - 32) & 0xFF, msg.substr(1));
      continue;
    }
    size_t e = plain_.find('\n', p);
    if (e == std::string::npos) break;
    std::string_view msg = std::string_view(plain_).substr(p, e - p);
    p = e + 1;
    if (msg.empty()) continue;
    int id = (static_cast<unsigned char>(msg[0]) - 32) & 0xFF;
    if (id == 100) {
      Reader r(msg.substr(1));
      raw_pending_ = r.gint3();
      in_raw_ = true;
      continue;
    }
    on_message_(id, msg.substr(1));
  }
  plain_.erase(0, p);
  if (plain_.size() > kMaxPending) fail("unfinished message from the server is past the limit");
}

}  // namespace Quattro::Net
