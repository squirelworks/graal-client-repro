#include "seccrypto.hpp"

#include <cstring>
#include <fstream>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
// RtlGenRandom, exported from advapi32 as SystemFunction036.
extern "C" BOOLEAN NTAPI SystemFunction036(PVOID buffer, ULONG length);
#elif defined(__APPLE__)
#include <stdlib.h>
#endif

namespace Quattro::Net::Sec {

namespace {

inline uint32_t rol32(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }
inline uint32_t ror32(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
inline uint64_t ror64(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }

inline uint32_t le32(const unsigned char* p) {
  return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
inline void put_le32(std::string& s, uint32_t v) {
  for (int i = 0; i < 4; ++i) s.push_back(static_cast<char>((v >> (8 * i)) & 0xFF));
}
inline void put_le64(std::string& s, uint64_t v) {
  for (int i = 0; i < 8; ++i) s.push_back(static_cast<char>((v >> (8 * i)) & 0xFF));
}
inline const unsigned char* bytes(std::string_view s) { return reinterpret_cast<const unsigned char*>(s.data()); }

// ---- SHA-256 ----

const uint32_t kK256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

void sha256_block(uint32_t h[8], const unsigned char* p) {
  uint32_t w[64];
  for (int i = 0; i < 16; ++i)
    w[i] = uint32_t(p[4 * i]) << 24 | uint32_t(p[4 * i + 1]) << 16 | uint32_t(p[4 * i + 2]) << 8 | p[4 * i + 3];
  for (int i = 16; i < 64; ++i) {
    uint32_t s0 = ror32(w[i - 15], 7) ^ ror32(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = ror32(w[i - 2], 17) ^ ror32(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
  for (int i = 0; i < 64; ++i) {
    uint32_t t1 = hh + (ror32(e, 6) ^ ror32(e, 11) ^ ror32(e, 25)) + ((e & f) ^ (~e & g)) + kK256[i] + w[i];
    uint32_t t2 = (ror32(a, 2) ^ ror32(a, 13) ^ ror32(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
  }
  h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

// ---- SHA-512 ----

const uint64_t kK512[80] = {
    0x428a2f98d728ae22ULL, 0x7137449123ef65cdULL, 0xb5c0fbcfec4d3b2fULL, 0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL, 0x59f111f1b605d019ULL, 0x923f82a4af194f9bULL, 0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL, 0x12835b0145706fbeULL, 0x243185be4ee4b28cULL, 0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL, 0x80deb1fe3b1696b1ULL, 0x9bdc06a725c71235ULL, 0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL, 0xefbe4786384f25e3ULL, 0x0fc19dc68b8cd5b5ULL, 0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL, 0x4a7484aa6ea6e483ULL, 0x5cb0a9dcbd41fbd4ULL, 0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL, 0xa831c66d2db43210ULL, 0xb00327c898fb213fULL, 0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL, 0xd5a79147930aa725ULL, 0x06ca6351e003826fULL, 0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL, 0x2e1b21385c26c926ULL, 0x4d2c6dfc5ac42aedULL, 0x53380d139d95b3dfULL,
    0x650a73548baf63deULL, 0x766a0abb3c77b2a8ULL, 0x81c2c92e47edaee6ULL, 0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL, 0xa81a664bbc423001ULL, 0xc24b8b70d0f89791ULL, 0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL, 0xd69906245565a910ULL, 0xf40e35855771202aULL, 0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL, 0x1e376c085141ab53ULL, 0x2748774cdf8eeb99ULL, 0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL, 0x4ed8aa4ae3418acbULL, 0x5b9cca4f7763e373ULL, 0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL, 0x78a5636f43172f60ULL, 0x84c87814a1f0ab72ULL, 0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL, 0xa4506cebde82bde9ULL, 0xbef9a3f7b2c67915ULL, 0xc67178f2e372532bULL,
    0xca273eceea26619cULL, 0xd186b8c721c0c207ULL, 0xeada7dd6cde0eb1eULL, 0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL, 0x0a637dc5a2c898a6ULL, 0x113f9804bef90daeULL, 0x1b710b35131c471bULL,
    0x28db77f523047d84ULL, 0x32caab7b40c72493ULL, 0x3c9ebe0a15c9bebcULL, 0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL, 0x597f299cfc657e2aULL, 0x5fcb6fab3ad6faecULL, 0x6c44198c4a475817ULL};

void sha512_block(uint64_t h[8], const unsigned char* p) {
  uint64_t w[80];
  for (int i = 0; i < 16; ++i) {
    uint64_t v = 0;
    for (int j = 0; j < 8; ++j) v = (v << 8) | p[8 * i + j];
    w[i] = v;
  }
  for (int i = 16; i < 80; ++i) {
    uint64_t s0 = ror64(w[i - 15], 1) ^ ror64(w[i - 15], 8) ^ (w[i - 15] >> 7);
    uint64_t s1 = ror64(w[i - 2], 19) ^ ror64(w[i - 2], 61) ^ (w[i - 2] >> 6);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint64_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
  for (int i = 0; i < 80; ++i) {
    uint64_t t1 = hh + (ror64(e, 14) ^ ror64(e, 18) ^ ror64(e, 41)) + ((e & f) ^ (~e & g)) + kK512[i] + w[i];
    uint64_t t2 = (ror64(a, 28) ^ ror64(a, 34) ^ ror64(a, 39)) + ((a & b) ^ (a & c) ^ (b & c));
    hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
  }
  h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

// ---- GF(2^255 - 19), sixteen 16-bit limbs ----

using Gf = int64_t[16];

const Gf kGf0 = {0};
const Gf kGf1 = {1};
const Gf k121665 = {0xDB41, 1};
const Gf kD = {0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
               0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203};
const Gf kD2 = {0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
                0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406};
const Gf kX = {0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
               0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169};
const Gf kY = {0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
               0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666};
const Gf kI = {0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43,
               0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83};
// The group order L, little endian.
const int64_t kL[32] = {0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7,
                        0xa2, 0xde, 0xf9, 0xde, 0x14, 0,    0,    0,    0,    0,    0,
                        0,    0,    0,    0,    0,    0,    0,    0,    0,    0x10};

// Arithmetic shift right, defined for negatives.
inline int64_t sar(int64_t v, int n) { return v < 0 ? ~((~v) >> n) : v >> n; }

void set(Gf o, const Gf a) { std::memcpy(o, a, sizeof(Gf)); }

void car(Gf o) {
  for (int i = 0; i < 16; ++i) {
    int64_t c = sar(o[i], 16);
    if (i < 15)
      o[i + 1] += c;
    else
      o[0] += 38 * c;
    o[i] -= c * 65536;
  }
}

void sel(Gf p, Gf q, int b) {
  int64_t c = ~(int64_t(b) - 1);
  for (int i = 0; i < 16; ++i) {
    int64_t t = c & (p[i] ^ q[i]);
    p[i] ^= t;
    q[i] ^= t;
  }
}

void pack(unsigned char o[32], const Gf n) {
  Gf m, t;
  set(t, n);
  car(t);
  car(t);
  car(t);
  for (int j = 0; j < 2; ++j) {
    m[0] = t[0] - 0xffed;
    for (int i = 1; i < 15; ++i) {
      m[i] = t[i] - 0xffff - (sar(m[i - 1], 16) & 1);
      m[i - 1] &= 0xffff;
    }
    m[15] = t[15] - 0x7fff - (sar(m[14], 16) & 1);
    int b = static_cast<int>(sar(m[15], 16) & 1);
    m[14] &= 0xffff;
    sel(t, m, 1 - b);
  }
  for (int i = 0; i < 16; ++i) {
    o[2 * i] = static_cast<unsigned char>(t[i] & 0xff);
    o[2 * i + 1] = static_cast<unsigned char>((t[i] >> 8) & 0xff);
  }
}

void unpack(Gf o, const unsigned char n[32]) {
  for (int i = 0; i < 16; ++i) o[i] = n[2 * i] + (int64_t(n[2 * i + 1]) << 8);
  o[15] &= 0x7fff;
}

bool neq(const Gf a, const Gf b) {
  unsigned char c[32], d[32];
  pack(c, a);
  pack(d, b);
  unsigned x = 0;
  for (int i = 0; i < 32; ++i) x |= c[i] ^ d[i];
  return x != 0;
}

int par(const Gf a) {
  unsigned char d[32];
  pack(d, a);
  return d[0] & 1;
}

void fadd(Gf o, const Gf a, const Gf b) {
  for (int i = 0; i < 16; ++i) o[i] = a[i] + b[i];
}
void fsub(Gf o, const Gf a, const Gf b) {
  for (int i = 0; i < 16; ++i) o[i] = a[i] - b[i];
}
void fmul(Gf o, const Gf a, const Gf b) {
  int64_t t[31] = {0};
  for (int i = 0; i < 16; ++i)
    for (int j = 0; j < 16; ++j) t[i + j] += a[i] * b[j];
  for (int i = 0; i < 15; ++i) t[i] += 38 * t[i + 16];
  for (int i = 0; i < 16; ++i) o[i] = t[i];
  car(o);
  car(o);
}
void fsqr(Gf o, const Gf a) { fmul(o, a, a); }

void inv(Gf o, const Gf in) {
  Gf c;
  set(c, in);
  for (int a = 253; a >= 0; --a) {
    fsqr(c, c);
    if (a != 2 && a != 4) fmul(c, c, in);
  }
  set(o, c);
}

void pow2523(Gf o, const Gf in) {
  Gf c;
  set(c, in);
  for (int a = 250; a >= 0; --a) {
    fsqr(c, c);
    if (a != 1) fmul(c, c, in);
  }
  set(o, c);
}

void scalarmult(unsigned char q[32], const unsigned char n[32], const unsigned char p[32]) {
  unsigned char z[32];
  std::memcpy(z, n, 32);
  z[31] = (n[31] & 127) | 64;
  z[0] &= 248;
  Gf x, a, b, c, d, e, f;
  unpack(x, p);
  for (int i = 0; i < 16; ++i) {
    b[i] = x[i];
    a[i] = c[i] = d[i] = 0;
  }
  a[0] = d[0] = 1;
  for (int i = 254; i >= 0; --i) {
    int r = (z[i >> 3] >> (i & 7)) & 1;
    sel(a, b, r);
    sel(c, d, r);
    fadd(e, a, c);
    fsub(a, a, c);
    fadd(c, b, d);
    fsub(b, b, d);
    fsqr(d, e);
    fsqr(f, a);
    fmul(a, c, a);
    fmul(c, b, e);
    fadd(e, a, c);
    fsub(a, a, c);
    fsqr(b, a);
    fsub(c, d, f);
    fmul(a, c, k121665);
    fadd(a, a, d);
    fmul(c, c, a);
    fmul(a, d, f);
    fmul(d, b, x);
    fsqr(b, e);
    sel(a, b, r);
    sel(c, d, r);
  }
  inv(c, c);
  fmul(a, a, c);
  pack(q, a);
}

// ---- Ed25519 points (X, Y, Z, T) ----

struct Point {
  Gf v[4];
};

void padd(Point& p, const Point& q) {
  Gf a, b, c, d, t, e, f, g, h;
  fsub(a, p.v[1], p.v[0]);
  fsub(t, q.v[1], q.v[0]);
  fmul(a, a, t);
  fadd(b, p.v[0], p.v[1]);
  fadd(t, q.v[0], q.v[1]);
  fmul(b, b, t);
  fmul(c, p.v[3], q.v[3]);
  fmul(c, c, kD2);
  fmul(d, p.v[2], q.v[2]);
  fadd(d, d, d);
  fsub(e, b, a);
  fsub(f, d, c);
  fadd(g, d, c);
  fadd(h, b, a);
  fmul(p.v[0], e, f);
  fmul(p.v[1], h, g);
  fmul(p.v[2], g, f);
  fmul(p.v[3], e, h);
}

void pswap(Point& p, Point& q, int b) {
  for (int i = 0; i < 4; ++i) sel(p.v[i], q.v[i], b);
}

void ppack(unsigned char r[32], const Point& p) {
  Gf tx, ty, zi;
  inv(zi, p.v[2]);
  fmul(tx, p.v[0], zi);
  fmul(ty, p.v[1], zi);
  pack(r, ty);
  r[31] ^= static_cast<unsigned char>(par(tx) << 7);
}

// p = [s]q; q is used as scratch.
void pscalarmult(Point& p, Point& q, const unsigned char s[32]) {
  set(p.v[0], kGf0);
  set(p.v[1], kGf1);
  set(p.v[2], kGf1);
  set(p.v[3], kGf0);
  for (int i = 255; i >= 0; --i) {
    int b = (s[i >> 3] >> (i & 7)) & 1;
    pswap(p, q, b);
    padd(q, p);
    Point t = p;
    padd(p, t);
    pswap(p, q, b);
  }
}

void pscalarbase(Point& p, const unsigned char s[32]) {
  Point q;
  set(q.v[0], kX);
  set(q.v[1], kY);
  set(q.v[2], kGf1);
  fmul(q.v[3], kX, kY);
  pscalarmult(p, q, s);
}

void mod_l(unsigned char r[32], int64_t x[64]) {
  int64_t carry;
  for (int i = 63; i >= 32; --i) {
    carry = 0;
    int j;
    for (j = i - 32; j < i - 12; ++j) {
      x[j] += carry - 16 * x[i] * kL[j - (i - 32)];
      carry = sar(x[j] + 128, 8);
      x[j] -= carry * 256;
    }
    x[j] += carry;
    x[i] = 0;
  }
  carry = 0;
  for (int j = 0; j < 32; ++j) {
    x[j] += carry - sar(x[31], 4) * kL[j];
    carry = sar(x[j], 8);
    x[j] &= 255;
  }
  for (int j = 0; j < 32; ++j) x[j] -= carry * kL[j];
  for (int i = 0; i < 32; ++i) {
    x[i + 1] += sar(x[i], 8);
    r[i] = static_cast<unsigned char>(x[i] & 255);
  }
}

void reduce64(const std::string& h, unsigned char r[32]) {
  int64_t x[64];
  for (int i = 0; i < 64; ++i) x[i] = static_cast<unsigned char>(h[i]);
  mod_l(r, x);
}

// -P from its encoding; false if it is not a point.
bool unpack_neg(Point& r, const unsigned char p[32]) {
  Gf t, chk, num, den, den2, den4, den6;
  set(r.v[2], kGf1);
  unpack(r.v[1], p);
  fsqr(num, r.v[1]);
  fmul(den, num, kD);
  fsub(num, num, r.v[2]);
  fadd(den, r.v[2], den);
  fsqr(den2, den);
  fsqr(den4, den2);
  fmul(den6, den4, den2);
  fmul(t, den6, num);
  fmul(t, t, den);
  pow2523(t, t);
  fmul(t, t, num);
  fmul(t, t, den);
  fmul(t, t, den);
  fmul(r.v[0], t, den);
  fsqr(chk, r.v[0]);
  fmul(chk, chk, den);
  if (neq(chk, num)) fmul(r.v[0], r.v[0], kI);
  fsqr(chk, r.v[0]);
  fmul(chk, chk, den);
  if (neq(chk, num)) return false;
  if (par(r.v[0]) == (p[31] >> 7)) fsub(r.v[0], kGf0, r.v[0]);
  fmul(r.v[3], r.v[0], r.v[1]);
  return true;
}

// y below p (the sign bit aside).
bool canonical_point(const unsigned char p[32]) {
  Gf y;
  unsigned char b[32];
  unpack(y, p);
  pack(b, y);
  bool ok = true;
  for (int i = 0; i < 31; ++i)
    if (b[i] != p[i]) ok = false;
  if (b[31] != (p[31] & 0x7F)) ok = false;
  return ok;
}

// [8]P is the neutral point.
bool small_order(const Point& p) {
  Point q = p;
  for (int i = 0; i < 3; ++i) {
    Point t = q;
    padd(q, t);
  }
  unsigned char e[32];
  ppack(e, q);
  bool r = e[0] == 1;
  for (int i = 1; i < 32; ++i)
    if (e[i] != 0) r = false;
  return r;
}

bool scalar_below_l(const unsigned char* s) {
  for (int i = 31; i >= 0; --i) {
    if (s[i] < kL[i]) return true;
    if (s[i] > kL[i]) return false;
  }
  return false;  // equal to L
}

std::string to_str(const unsigned char* b, size_t n) { return std::string(reinterpret_cast<const char*>(b), n); }

// ---- ChaCha20 ----

void chacha_block(std::string_view key, std::string_view nonce, uint32_t counter, unsigned char out[64]) {
  uint32_t s[16];
  s[0] = 0x61707865;
  s[1] = 0x3320646e;
  s[2] = 0x79622d32;
  s[3] = 0x6b206574;
  for (int i = 0; i < 8; ++i) s[4 + i] = le32(bytes(key) + 4 * i);
  s[12] = counter;
  for (int i = 0; i < 3; ++i) s[13 + i] = le32(bytes(nonce) + 4 * i);
  uint32_t x[16];
  std::memcpy(x, s, sizeof s);
  auto qr = [&x](int a, int b, int c, int d) {
    x[a] += x[b]; x[d] = rol32(x[d] ^ x[a], 16);
    x[c] += x[d]; x[b] = rol32(x[b] ^ x[c], 12);
    x[a] += x[b]; x[d] = rol32(x[d] ^ x[a], 8);
    x[c] += x[d]; x[b] = rol32(x[b] ^ x[c], 7);
  };
  for (int i = 0; i < 10; ++i) {
    qr(0, 4, 8, 12); qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15);
    qr(0, 5, 10, 15); qr(1, 6, 11, 12); qr(2, 7, 8, 13); qr(3, 4, 9, 14);
  }
  for (int i = 0; i < 16; ++i) {
    uint32_t v = x[i] + s[i];
    for (int j = 0; j < 4; ++j) out[4 * i + j] = static_cast<unsigned char>((v >> (8 * j)) & 0xFF);
  }
}

std::string pad16(size_t n) { return n % 16 == 0 ? std::string() : std::string(16 - n % 16, '\0'); }

std::string aead_tag(std::string_view key, std::string_view nonce, std::string_view aad, std::string_view ct) {
  unsigned char blk[64];
  chacha_block(key, nonce, 0, blk);
  std::string otk = to_str(blk, 32);
  std::string m;
  m.reserve(aad.size() + ct.size() + 48);
  m.append(aad);
  m += pad16(aad.size());
  m.append(ct);
  m += pad16(ct.size());
  put_le64(m, aad.size());
  put_le64(m, ct.size());
  return poly1305_mac(otk, m);
}

const char kB64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

}  // namespace

std::string sha256(std::string_view data) {
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  size_t n = data.size(), i = 0;
  for (; i + 64 <= n; i += 64) sha256_block(h, bytes(data) + i);
  unsigned char last[128] = {0};
  size_t rest = n - i;
  std::memcpy(last, bytes(data) + i, rest);
  last[rest] = 0x80;
  size_t total = rest + 9 <= 64 ? 64 : 128;
  uint64_t bits = uint64_t(n) * 8;
  for (int k = 0; k < 8; ++k) last[total - 1 - k] = static_cast<unsigned char>((bits >> (8 * k)) & 0xFF);
  sha256_block(h, last);
  if (total == 128) sha256_block(h, last + 64);
  std::string out;
  for (int k = 0; k < 8; ++k)
    for (int j = 3; j >= 0; --j) out.push_back(static_cast<char>((h[k] >> (8 * j)) & 0xFF));
  return out;
}

std::string sha512(std::string_view data) {
  uint64_t h[8] = {0x6a09e667f3bcc908ULL, 0xbb67ae8584caa73bULL, 0x3c6ef372fe94f82bULL, 0xa54ff53a5f1d36f1ULL,
                   0x510e527fade682d1ULL, 0x9b05688c2b3e6c1fULL, 0x1f83d9abfb41bd6bULL, 0x5be0cd19137e2179ULL};
  size_t n = data.size(), i = 0;
  for (; i + 128 <= n; i += 128) sha512_block(h, bytes(data) + i);
  unsigned char last[256] = {0};
  size_t rest = n - i;
  std::memcpy(last, bytes(data) + i, rest);
  last[rest] = 0x80;
  size_t total = rest + 17 <= 128 ? 128 : 256;
  uint64_t bits = uint64_t(n) * 8;  // the high 64 bits of the length stay 0
  for (int k = 0; k < 8; ++k) last[total - 1 - k] = static_cast<unsigned char>((bits >> (8 * k)) & 0xFF);
  sha512_block(h, last);
  if (total == 256) sha512_block(h, last + 128);
  std::string out;
  for (int k = 0; k < 8; ++k)
    for (int j = 7; j >= 0; --j) out.push_back(static_cast<char>((h[k] >> (8 * j)) & 0xFF));
  return out;
}

std::string hmac_sha256(std::string_view key, std::string_view data) {
  std::string k = key.size() > 64 ? sha256(key) : std::string(key);
  k.resize(64, '\0');
  std::string ipad(64, '\0'), opad(64, '\0');
  for (int i = 0; i < 64; ++i) {
    ipad[i] = static_cast<char>(k[i] ^ 0x36);
    opad[i] = static_cast<char>(k[i] ^ 0x5c);
  }
  ipad.append(data);
  return sha256(opad + sha256(ipad));
}

std::string hkdf_sha256(std::string_view salt, std::string_view ikm, std::string_view info, size_t len) {
  if (len > 255 * 32) return std::string();
  std::string prk = hmac_sha256(salt.empty() ? std::string(32, '\0') : std::string(salt), ikm);
  std::string out, t;
  unsigned n = 1;
  while (out.size() < len) {
    t = hmac_sha256(prk, t + std::string(info) + static_cast<char>(n));
    out += t;
    ++n;
  }
  out.resize(len);
  return out;
}

std::string x25519(std::string_view scalar, std::string_view u) {
  if (scalar.size() != 32 || u.size() != 32) return std::string();
  unsigned char q[32];
  scalarmult(q, bytes(scalar), bytes(u));
  return to_str(q, 32);
}

std::string x25519_base(std::string_view scalar) {
  unsigned char nine[32] = {9};
  if (scalar.size() != 32) return std::string();
  unsigned char q[32];
  scalarmult(q, bytes(scalar), nine);
  return to_str(q, 32);
}

bool is_zero32(std::string_view s) {
  if (s.size() != 32) return true;
  unsigned x = 0;
  for (char c : s) x |= static_cast<unsigned char>(c);
  return x == 0;
}

bool ed25519_verify(std::string_view sig, std::string_view msg, std::string_view public_key) {
  if (sig.size() != 64 || public_key.size() != 32) return false;
  const unsigned char* pk = bytes(public_key);
  const unsigned char* rb = bytes(sig);
  const unsigned char* sb = bytes(sig) + 32;
  if (!scalar_below_l(sb)) return false;
  if (!canonical_point(pk) || !canonical_point(rb)) return false;
  Point neg_a, neg_r, p, q;
  if (!unpack_neg(neg_a, pk) || !unpack_neg(neg_r, rb)) return false;
  if (small_order(neg_a) || small_order(neg_r)) return false;
  unsigned char hb[32], t[32];
  std::string hin(sig.substr(0, 32));
  hin.append(public_key);
  hin.append(msg);
  reduce64(sha512(hin), hb);
  pscalarmult(p, neg_a, hb);  // -[k]A
  pscalarbase(q, sb);         // [S]B
  padd(p, q);
  ppack(t, p);
  unsigned d = 0;
  for (int i = 0; i < 32; ++i) d |= t[i] ^ rb[i];
  return d == 0;
}

std::string ed25519_public_key(std::string_view seed) {
  if (seed.size() < 32) return std::string();
  std::string h = sha512(seed.substr(0, 32));
  unsigned char a[32];
  std::memcpy(a, h.data(), 32);
  a[0] &= 248;
  a[31] = (a[31] & 127) | 64;
  Point p;
  pscalarbase(p, a);
  unsigned char out[32];
  ppack(out, p);
  return to_str(out, 32);
}

std::string ed25519_sign(std::string_view msg, std::string_view seed) {
  if (seed.size() < 32) return std::string();
  std::string h = sha512(seed.substr(0, 32));
  unsigned char a[32], rb[32], kb[32], re[32];
  std::memcpy(a, h.data(), 32);
  a[0] &= 248;
  a[31] = (a[31] & 127) | 64;
  std::string pk = ed25519_public_key(seed);
  reduce64(sha512(h.substr(32, 32) + std::string(msg)), rb);
  Point p;
  pscalarbase(p, rb);
  ppack(re, p);
  reduce64(sha512(to_str(re, 32) + pk + std::string(msg)), kb);
  int64_t x[64] = {0};
  for (int i = 0; i < 32; ++i) x[i] = rb[i];
  for (int i = 0; i < 32; ++i)
    for (int j = 0; j < 32; ++j) x[i + j] += int64_t(kb[i]) * int64_t(a[j]);
  mod_l(kb, x);
  return to_str(re, 32) + to_str(kb, 32);
}

std::string chacha20_xor(std::string_view key, std::string_view nonce, uint32_t counter, std::string_view data) {
  std::string out(data);
  if (key.size() != 32 || nonce.size() != 12) return std::string();
  unsigned char blk[64];
  for (size_t p = 0; p < out.size(); p += 64) {
    chacha_block(key, nonce, counter++, blk);
    for (size_t i = 0; i < 64 && p + i < out.size(); ++i) out[p + i] = static_cast<char>(out[p + i] ^ blk[i]);
  }
  return out;
}

std::string poly1305_mac(std::string_view key, std::string_view msg) {
  const uint64_t mask26 = 0x3FFFFFF;
  const unsigned char* k = bytes(key);
  uint64_t r0 = le32(k) & 0x3FFFFFF;
  uint64_t r1 = (le32(k + 3) >> 2) & 0x3FFFF03;
  uint64_t r2 = (le32(k + 6) >> 4) & 0x3FFC0FF;
  uint64_t r3 = (le32(k + 9) >> 6) & 0x3F03FFF;
  uint64_t r4 = (le32(k + 12) >> 8) & 0x00FFFFF;
  uint64_t s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5;
  uint64_t h0 = 0, h1 = 0, h2 = 0, h3 = 0, h4 = 0, c;
  for (size_t p = 0; p < msg.size(); p += 16) {
    unsigned char blk[16] = {0};
    size_t n = msg.size() - p;
    uint64_t hibit;
    if (n >= 16) {
      std::memcpy(blk, bytes(msg) + p, 16);
      hibit = uint64_t(1) << 24;
    } else {
      std::memcpy(blk, bytes(msg) + p, n);
      blk[n] = 1;
      hibit = 0;
    }
    h0 += le32(blk) & mask26;
    h1 += (le32(blk + 3) >> 2) & mask26;
    h2 += (le32(blk + 6) >> 4) & mask26;
    h3 += (le32(blk + 9) >> 6) & mask26;
    h4 += (le32(blk + 12) >> 8) | hibit;
    uint64_t d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1;
    uint64_t d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2;
    uint64_t d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3;
    uint64_t d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4;
    uint64_t d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0;
    c = d0 >> 26; h0 = d0 & mask26;
    d1 += c; c = d1 >> 26; h1 = d1 & mask26;
    d2 += c; c = d2 >> 26; h2 = d2 & mask26;
    d3 += c; c = d3 >> 26; h3 = d3 & mask26;
    d4 += c; c = d4 >> 26; h4 = d4 & mask26;
    h0 += c * 5; c = h0 >> 26; h0 &= mask26;
    h1 += c;
  }
  c = h1 >> 26; h1 &= mask26;
  h2 += c; c = h2 >> 26; h2 &= mask26;
  h3 += c; c = h3 >> 26; h3 &= mask26;
  h4 += c; c = h4 >> 26; h4 &= mask26;
  h0 += c * 5; c = h0 >> 26; h0 &= mask26;
  h1 += c;
  uint64_t g0 = h0 + 5; c = g0 >> 26; g0 &= mask26;
  uint64_t g1 = h1 + c; c = g1 >> 26; g1 &= mask26;
  uint64_t g2 = h2 + c; c = g2 >> 26; g2 &= mask26;
  uint64_t g3 = h3 + c; c = g3 >> 26; g3 &= mask26;
  uint64_t g4 = h4 + c - (uint64_t(1) << 26);
  uint64_t m = (g4 >> 63) - 1;  // all ones when h >= p
  g0 &= m; g1 &= m; g2 &= m; g3 &= m; g4 &= m;
  m = ~m;
  h0 = (h0 & m) | g0; h1 = (h1 & m) | g1; h2 = (h2 & m) | g2; h3 = (h3 & m) | g3; h4 = (h4 & m) | g4;
  h0 = (h0 | (h1 << 26)) & 0xFFFFFFFF;
  h1 = ((h1 >> 6) | (h2 << 20)) & 0xFFFFFFFF;
  h2 = ((h2 >> 12) | (h3 << 14)) & 0xFFFFFFFF;
  h3 = ((h3 >> 18) | (h4 << 8)) & 0xFFFFFFFF;
  uint64_t f = h0 + le32(k + 16); h0 = f & 0xFFFFFFFF;
  f = h1 + le32(k + 20) + (f >> 32); h1 = f & 0xFFFFFFFF;
  f = h2 + le32(k + 24) + (f >> 32); h2 = f & 0xFFFFFFFF;
  f = h3 + le32(k + 28) + (f >> 32); h3 = f & 0xFFFFFFFF;
  std::string out;
  put_le32(out, static_cast<uint32_t>(h0));
  put_le32(out, static_cast<uint32_t>(h1));
  put_le32(out, static_cast<uint32_t>(h2));
  put_le32(out, static_cast<uint32_t>(h3));
  return out;
}

std::string aead_seal(std::string_view key, std::string_view nonce, std::string_view aad, std::string_view plain) {
  std::string ct = chacha20_xor(key, nonce, 1, plain);
  return ct + aead_tag(key, nonce, aad, ct);
}

bool aead_open(std::string_view key, std::string_view nonce, std::string_view aad, std::string_view sealed,
               std::string& plain) {
  plain.clear();
  if (sealed.size() < 16 || key.size() != 32 || nonce.size() != 12) return false;
  std::string_view ct = sealed.substr(0, sealed.size() - 16);
  if (!same_bytes(aead_tag(key, nonce, aad, ct), sealed.substr(sealed.size() - 16))) return false;
  plain = chacha20_xor(key, nonce, 1, ct);
  return true;
}

std::string b64_encode(std::string_view data) {
  std::string out;
  size_t n = data.size();
  for (size_t i = 0; i < n; i += 3) {
    uint32_t v = uint32_t(static_cast<unsigned char>(data[i])) << 16;
    if (i + 1 < n) v |= uint32_t(static_cast<unsigned char>(data[i + 1])) << 8;
    if (i + 2 < n) v |= static_cast<unsigned char>(data[i + 2]);
    out.push_back(kB64[v >> 18]);
    out.push_back(kB64[(v >> 12) & 63]);
    if (i + 1 < n) out.push_back(kB64[(v >> 6) & 63]);
    if (i + 2 < n) out.push_back(kB64[v & 63]);
  }
  return out;
}

bool b64_decode(std::string_view text, std::string& out) {
  out.clear();
  // Trailing '=' is tolerated, as the Pascal clients do.
  while (!text.empty() && text.back() == '=') text.remove_suffix(1);
  if (text.size() % 4 == 1) return false;
  uint32_t bits = 0;
  int nbits = 0;
  for (char ch : text) {
    const char* p = ch ? std::strchr(kB64, ch) : nullptr;
    if (!p) {
      out.clear();
      return false;
    }
    bits = ((bits << 6) | uint32_t(p - kB64)) & 0xFFFFFF;
    nbits += 6;
    if (nbits >= 8) {
      nbits -= 8;
      out.push_back(static_cast<char>((bits >> nbits) & 0xFF));
    }
  }
  // the bits left over must be zero (canonical form)
  if ((bits & ((1u << nbits) - 1)) != 0) {
    out.clear();
    return false;
  }
  return true;
}

bool random_bytes(size_t n, std::string& out) {
  out.assign(n, '\0');
  if (n == 0) return true;
#ifdef _WIN32
  if (!SystemFunction036(&out[0], static_cast<ULONG>(n))) {
    out.clear();
    return false;
  }
  return true;
#elif defined(__APPLE__)
  arc4random_buf(&out[0], n);
  return true;
#else
  std::ifstream f("/dev/urandom", std::ios::binary);
  if (!f || !f.read(&out[0], static_cast<std::streamsize>(n))) {
    out.clear();
    return false;
  }
  return true;
#endif
}

bool same_bytes(std::string_view a, std::string_view b) {
  if (a.size() != b.size()) return false;
  unsigned d = 0;
  for (size_t i = 0; i < a.size(); ++i) d |= static_cast<unsigned char>(a[i]) ^ static_cast<unsigned char>(b[i]);
  return d == 0;
}

}  // namespace Quattro::Net::Sec
