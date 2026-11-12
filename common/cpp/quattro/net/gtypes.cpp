#include "gtypes.hpp"

namespace Quattro::Net {

namespace {
std::string groups(uint64_t v, int count) {
  std::string out(static_cast<size_t>(count), '\0');
  for (int i = count - 1; i >= 0; --i) {
    out[static_cast<size_t>(i)] = static_cast<char>((v & 0x7F) + 32);
    v >>= 7;
  }
  return out;
}
}  // namespace

std::string gchar(unsigned v) { return std::string(1, static_cast<char>((v + 32) & 0xFF)); }
std::string gshort(unsigned v) { return groups(v & 0x3FFF, 2); }
std::string gint3(uint32_t v) { return groups(v & 0x1FFFFF, 3); }
std::string gint5(uint64_t v) { return groups(v & 0x7FFFFFFFFULL, 5); }

std::string gstring(std::string_view s) {
  if (s.size() >= 0xE0) return std::string(1, '\xFF') + std::string(s.substr(0, 0xDF));
  return gchar(static_cast<unsigned>(s.size())) + std::string(s);
}

unsigned Reader::byte() {
  if (pos_ >= data_.size()) {
    ok_ = false;
    return 0;
  }
  return static_cast<unsigned char>(data_[pos_++]);
}

unsigned Reader::gchar() {
  unsigned b = byte();
  return ok_ ? ((b - 32) & 0xFF) : 0;
}

unsigned Reader::gshort() {
  unsigned hi = gchar();
  unsigned lo = gchar();
  return ((hi & 0x7F) << 7) | (lo & 0x7F);
}

uint32_t Reader::gint3() {
  uint32_t v = 0;
  for (int i = 0; i < 3; ++i) v = (v << 7) | (gchar() & 0x7F);
  return v;
}

uint64_t Reader::gint5() {
  uint64_t v = 0;
  for (int i = 0; i < 5; ++i) v = (v << 7) | (gchar() & 0x7F);
  return v;
}

std::string Reader::gstring() {
  unsigned len = gchar();
  if (!ok_) return {};
  if (len > data_.size() - pos_) {
    ok_ = false;
    pos_ = data_.size();
    return {};
  }
  std::string s(data_.substr(pos_, len));
  pos_ += len;
  return s;
}

std::string Reader::rest() {
  std::string s(data_.substr(pos_ < data_.size() ? pos_ : data_.size()));
  pos_ = data_.size();
  return s;
}

}  // namespace Quattro::Net
