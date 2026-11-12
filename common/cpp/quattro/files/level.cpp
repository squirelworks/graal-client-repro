#include "level.hpp"

#include <sstream>

namespace Quattro::Files {

namespace {

// Bits least significant first, as the GR-V board is packed.
class BitReader {
 public:
  BitReader(std::string_view d, size_t pos) : d_(d), pos_(pos) {}
  bool read(int width, unsigned& out) {
    while (nbits_ < width) {
      if (pos_ >= d_.size()) return false;
      buf_ |= static_cast<uint32_t>(static_cast<unsigned char>(d_[pos_++])) << nbits_;
      nbits_ += 8;
    }
    out = buf_ & ((1u << width) - 1);
    buf_ >>= width;
    nbits_ -= width;
    return true;
  }
  // The next section starts at the byte after the last one read; leftover
  // bits of that byte are padding.
  size_t byte_pos() const { return pos_; }

 private:
  std::string_view d_;
  size_t pos_;
  uint32_t buf_ = 0;
  int nbits_ = 0;
};

bool read_board(std::string_view data, size_t& pos, int width, Board& board) {
  BitReader br(data, pos);
  const unsigned flag = 1u << (width - 1);
  size_t n = 0;
  unsigned count = 1;
  bool dbl = false;
  while (n < board.size()) {
    unsigned code;
    if (!br.read(width, code)) return false;
    if (code & flag) {
      count = code & 0xFF;
      dbl = (code & 0x100) != 0;
      continue;
    }
    if (dbl) {
      unsigned b;
      if (!br.read(width, b)) return false;
      for (unsigned i = 0; i < count && n < board.size(); ++i) {
        board[n++] = static_cast<uint16_t>(code);
        if (n < board.size()) board[n++] = static_cast<uint16_t>(b);
      }
    } else {
      for (unsigned i = 0; i < count && n < board.size(); ++i) board[n++] = static_cast<uint16_t>(code);
    }
    count = 1;
    dbl = false;
  }
  pos = br.byte_pos();
  return true;
}

// One line, without its '\n'. False at end of data.
bool line(std::string_view d, size_t& pos, std::string_view& out) {
  if (pos >= d.size()) return false;
  size_t e = d.find('\n', pos);
  if (e == std::string_view::npos) e = d.size();
  out = d.substr(pos, e - pos);
  pos = e < d.size() ? e + 1 : e;
  if (!out.empty() && out.back() == '\r') out.remove_suffix(1);
  return true;
}

int gc(char c) { return static_cast<unsigned char>(c) - 32; }

void parse_link(std::string_view l, Level& lv) {
  std::vector<std::string> tok;
  std::istringstream in{std::string(l)};
  for (std::string t; in >> t;) tok.push_back(t);
  if (tok.size() < 7) return;
  Link k;
  size_t n = tok.size();
  for (size_t i = 0; i + 6 < n; ++i) k.dest += (i ? " " : "") + tok[i];
  try {
    k.x = std::stoi(tok[n - 6]);
    k.y = std::stoi(tok[n - 5]);
    k.w = std::stoi(tok[n - 4]);
    k.h = std::stoi(tok[n - 3]);
  } catch (...) {
    return;
  }
  k.newx = tok[n - 2];
  k.newy = tok[n - 1];
  lv.links.push_back(k);
}

}  // namespace

bool read_level(std::string_view data, Level& out, std::string& error) {
  out = Level{};
  if (data.size() < 8) {
    error = "level is shorter than its magic";
    return false;
  }
  out.magic = std::string(data.substr(0, 8));
  int width = 0;
  bool layered = false;
  if (out.magic == "GR-V1.00" || out.magic == "GR-V1.01") width = 12;
  else if (out.magic == "GR-V1.02" || out.magic == "GR-V1.03" || out.magic == "GR-V1.04") width = 13;
  else if (out.magic == "GR-V1.05") width = 13, layered = true;
  else {
    error = "unknown level magic";
    return false;
  }
  size_t pos = 8;
  size_t layers = 1;
  if (layered) {
    if (pos >= data.size()) {
      error = "no layer count";
      return false;
    }
    layers = static_cast<size_t>(gc(data[pos++]));
    if (layers == 0 || layers > 64) {
      error = "bad layer count";
      return false;
    }
  }
  for (size_t i = 0; i < layers; ++i) {
    Board b{};
    if (!read_board(data, pos, width, b)) {
      error = "board ends early";
      return false;
    }
    out.layers.push_back(b);
  }

  std::string_view l;
  // Links, to '#'.
  while (line(data, pos, l) && l != "#" && !l.empty()) parse_link(l, out);
  // Baddies: records of at least 3 bytes up to a '\n', until one whose
  // first byte is 0x80 or more (the FF FF FF terminator).
  while (pos < data.size()) {
    bool end = static_cast<unsigned char>(data[pos]) >= 0x80;
    size_t from = pos + 3 <= data.size() ? pos + 3 : data.size();
    size_t e = data.find('\n', from);
    pos = e == std::string_view::npos ? data.size() : e + 1;
    if (end) break;
  }
  // NPCs, to '#' (GR-V1.00 on). Not kept: the server sends the NPCs.
  while (line(data, pos, l) && l != "#") {
  }
  // Chests, to '#' (GR-V1.01 on).
  if (out.magic != "GR-V1.00") {
    while (line(data, pos, l) && l != "#") {
      if (l.size() >= 4) out.chests.push_back({gc(l[0]), gc(l[1]), gc(l[2]), gc(l[3])});
    }
  }
  // Signs, to an empty line (a HEIGHTS block may follow; it is skipped).
  while (line(data, pos, l) && !l.empty()) {
    if (l.size() >= 2) out.signs.push_back({gc(l[0]), gc(l[1]), std::string(l.substr(2))});
  }
  return true;
}

bool apply_board_packet(std::string_view body, Level& level, std::string& error) {
  if (body.size() != kBoardTiles * 2) {
    error = "board packet is not 8192 bytes";
    return false;
  }
  if (level.layers.empty()) level.layers.emplace_back();
  Board& b = level.layers[0];
  for (size_t i = 0; i < b.size(); ++i)
    b[i] = static_cast<uint16_t>(static_cast<unsigned char>(body[2 * i]) |
                                 (static_cast<unsigned char>(body[2 * i + 1]) << 8));
  return true;
}

std::string write_board_stream(const Board& board) {
  std::string out;
  uint32_t buf = 0;
  int nbits = 0;
  auto put = [&](unsigned code) {
    buf |= (code & 0x1FFF) << nbits;
    nbits += 13;
    while (nbits >= 8) {
      out.push_back(static_cast<char>(buf & 0xFF));
      buf >>= 8;
      nbits -= 8;
    }
  };
  size_t i = 0;
  while (i < board.size()) {
    size_t n = 1;
    while (i + n < board.size() && board[i + n] == board[i] && n < 64) ++n;
    if (n > 1) put(0x1000 | static_cast<unsigned>(n));
    put(board[i] & 0xFFF);
    i += n;
  }
  if (nbits > 0) out.push_back(static_cast<char>(buf & 0xFF));
  return out;
}

}  // namespace Quattro::Files
