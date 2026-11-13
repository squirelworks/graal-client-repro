// The gen-5 game connection codec the 6.01 and 6.03 programs use.
//
// From Graal_analysis protocol/v6x-clients.md ("Cipher and framing") and
// protocol/codec-and-framing.md:
//
// - The first frame the client sends is the login frame: a u16be length
//   and a zlib stream, with no compression byte and no XOR.
// - Every later frame, both ways: the length, a compression byte, the
//   body. 2 is raw, 4 zlib, 6 bzip2; odd codes are the same with no XOR.
// - An even code XORs the start of the body: one LCG step per 4-byte group
//   present, at most 12 groups for 2 and 4 groups for 4 and 6. A short
//   last group still steps. The LCG is it = it * 0x08088405 + key, seeded
//   0x04A80B38, one iterator per direction, key = random & 0x7F.
// - New in 6.x: a frame of 0xFFFF bytes or more is sent as the length
//   0xFFFF and then the real length as a u32be.
// - Messages inside a frame are id + 32, the body, '\n'. Id 100 announces
//   a raw message of a GINT3 length that may hold newlines.
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>

namespace Quattro::Net {

constexpr uint32_t kCipherSeed = 0x04A80B38u;
constexpr uint32_t kCipherMul = 0x08088405u;
constexpr int kXorGroupsRaw = 12;
constexpr int kXorGroupsPacked = 4;

enum Compression : uint8_t {
  kRaw = 2,
  kZlib = 4,
  kBzip2 = 6,
};

// Receive limits. These are the rebuild's own, so a hostile server cannot
// grow the client without bound; the original's limits were not read.
constexpr size_t kMaxFrame = 16u * 1024 * 1024;
constexpr size_t kMaxPending = 4u * 1024 * 1024;

class Cipher {
 public:
  explicit Cipher(uint8_t key = 0) { reset(key); }
  void reset(uint8_t key) {
    key_ = key & 0x7F;
    it_ = kCipherSeed;
  }
  // XORs `body` in place for compression byte `type`. Odd types are left.
  void apply(std::string& body, uint8_t type);
  // 5.12 (and the Windows 4.04r2 engine) steps len / 4 rounded down for
  // zlib and bzip2 bodies (still at most 4 groups) and rounds up only for
  // raw ones (Graal_analysis protocol/v5v6-lab-play.md, "5.12's cipher step
  // count"). Every other build rounds up in both cases.
  void set_packed_round_down(bool on) { round_down_ = on; }
  uint8_t key() const { return key_; }
  uint32_t iterator() const { return it_; }

 private:
  uint8_t key_ = 0;
  uint32_t it_ = kCipherSeed;
  bool round_down_ = false;
};

// zlib and bzip2 on strings. Decompression stops with false past `limit`.
std::string zlib_compress(std::string_view in);
bool zlib_decompress(std::string_view in, std::string& out, size_t limit = kMaxFrame);
std::string bzip2_compress(std::string_view in);
bool bzip2_decompress(std::string_view in, std::string& out, size_t limit = kMaxFrame);

// The client's choice for an outgoing buffer: bzip2 from 0x1000 bytes,
// zlib from 0x30, raw below that unless zlib comes out shorter
// (protocol/client-versions.md, "Gen-5 send on the client"; the 6.x note
// keeps those thresholds).
uint8_t choose_compression(size_t plain_size, size_t zlib_size);

// The frame length as it goes on the wire.
std::string frame_length(size_t len);

// Builds outgoing frames. The first call to `encode` is the login frame.
class FrameEncoder {
 public:
  // `login_first` false is the server's side, which has no login frame.
  explicit FrameEncoder(uint8_t key, bool login_first = true) : cipher_(key), login_(login_first) {}
  // Returns the whole frame: length bytes, then the body.
  std::string encode(std::string_view plain);
  bool login_sent() const { return !login_; }
  // 5.12: the packed step rule above, and every body below the bzip2 size
  // compressed with zlib, short ones too (protocol/v5v6-windows-unpacked.md,
  // "5.12 sends even short bodies zlib-compressed").
  void set_packed_round_down(bool on) { cipher_.set_packed_round_down(on); }
  void set_compress_always(bool on) { compress_always_ = on; }

 private:
  Cipher cipher_;
  bool login_;
  bool compress_always_ = false;
};

// Splits an incoming byte stream into frames and the frames into messages.
// `on_message` gets the logical id (wire byte - 32) and the body without
// the trailing newline. A protocol error stops the decoder; `error()` says
// why and later input is ignored.
class FrameDecoder {
 public:
  using MessageFn = std::function<void(int id, std::string_view body)>;

  FrameDecoder(uint8_t key, MessageFn on_message)
      : cipher_(key), on_message_(std::move(on_message)) {}

  // Some servers' first frame is plain; the client never sees that on a
  // game connection, so frames are always gen-5 here.
  void feed(std::string_view bytes);
  bool failed() const { return !error_.empty(); }
  const std::string& error() const { return error_; }
  size_t frames() const { return frames_; }

  // Decodes one frame body (compression byte first) to plain bytes.
  bool decode_body(std::string_view body, std::string& plain);
  // 5.12's decoder steps packed bodies rounded down (Cipher above).
  void set_packed_round_down(bool on) { cipher_.set_packed_round_down(on); }

 private:
  void split();
  void fail(const char* why);

  Cipher cipher_;
  MessageFn on_message_;
  std::string raw_;
  std::string plain_;
  size_t raw_pending_ = 0;
  bool in_raw_ = false;
  size_t frames_ = 0;
  std::string error_;
};

}  // namespace Quattro::Net
