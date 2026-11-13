#include "bits.hpp"

#include "huffman.hpp"

#include <cstring>

namespace graal3d {

bool BitReader::flag() {
  if (pos_ >= size_) {
    overrun_ = true;
    ++pos_;
    return false;
  }
  const bool b = (static_cast<uint8_t>(data_[pos_ >> 3]) >> (pos_ & 7)) & 1;
  ++pos_;
  return b;
}

uint32_t BitReader::bits(int n) {
  uint32_t v = 0;
  for (int i = 0; i < n; ++i)
    if (flag()) v |= 1u << i;
  return v;
}

float BitReader::f32() {
  const uint32_t u = u32();
  float f;
  std::memcpy(&f, &u, 4);
  return f;
}

std::string BitReader::string() {
  std::string out;
  if (flag()) {
    const auto& h = torque3d::Huffman::instance();
    const int n = u8();
    for (int i = 0; i < n && !overrun_; ++i) {
      int node = h.root();
      while (!h.isLeaf(node)) node = h.child(node, flag() ? 1 : 0);
      out.push_back(static_cast<char>(h.leafByte(node)));
    }
  } else {
    const int n = u8();
    for (int i = 0; i < n; ++i) out.push_back(static_cast<char>(u8()));
  }
  return out;
}

std::string BitReader::pstring() {
  std::string out;
  if (flag()) {
    const size_t keep = u8();
    out = prev_.substr(0, keep < prev_.size() ? keep : prev_.size());
    out += string();
  } else {
    out = string();
  }
  prev_ = out;
  return out;
}

bool BitWriter::flag(bool b) {
  bits_.push_back(b ? 1 : 0);
  return b;
}

void BitWriter::bits(uint32_t v, int n) {
  for (int i = 0; i < n; ++i) bits_.push_back((v >> i) & 1);
}

void BitWriter::f32(float f) {
  uint32_t u;
  std::memcpy(&u, &f, 4);
  u32(u);
}

void BitWriter::string(const std::string& in) {
  const std::string s = in.size() > 255 ? in.substr(0, 255) : in;
  const auto& h = torque3d::Huffman::instance();
  size_t coded = 0;
  for (unsigned char c : s) coded += h.code(c).size();
  if (coded < s.size() * 8) {
    flag(true);
    u8(static_cast<uint32_t>(s.size()));
    for (unsigned char c : s)
      for (uint8_t b : h.code(c)) bits_.push_back(b);
  } else {
    flag(false);
    u8(static_cast<uint32_t>(s.size()));
    for (unsigned char c : s) u8(c);
  }
}

void BitWriter::pstring(const std::string& s) {
  flag(false);
  string(s);
}

void BitWriter::append(const BitWriter& w) { bits_.insert(bits_.end(), w.bits_.begin(), w.bits_.end()); }

std::string BitWriter::bytes() const {
  std::string out((bits_.size() + 7) / 8, '\0');
  for (size_t i = 0; i < bits_.size(); ++i)
    if (bits_[i]) out[i >> 3] = static_cast<char>(static_cast<uint8_t>(out[i >> 3]) | (1u << (i & 7)));
  return out;
}

std::string toHex(const std::string& bytes) {
  static const char* d = "0123456789abcdef";
  std::string out;
  for (unsigned char c : bytes) {
    out.push_back(d[c >> 4]);
    out.push_back(d[c & 15]);
  }
  return out;
}

std::string fromHex(const std::string& hex) {
  std::string out;
  auto val = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };
  int hi = -1;
  for (char c : hex) {
    const int v = val(c);
    if (v < 0) continue;
    if (hi < 0) {
      hi = v;
    } else {
      out.push_back(static_cast<char>(hi * 16 + v));
      hi = -1;
    }
  }
  return out;
}

}  // namespace graal3d
