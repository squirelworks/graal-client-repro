#include "capture.hpp"

#include <cmath>
#include <cstring>

namespace graal3d::capture {
namespace {

struct In {
  const uint8_t* p;
  size_t n;
  bool swap = false;
  uint16_t u16(size_t at) const {
    const uint16_t v = uint16_t(p[at] | p[at + 1] << 8);
    return swap ? uint16_t(v >> 8 | v << 8) : v;
  }
  uint32_t u32(size_t at) const {
    const uint32_t v = uint32_t(p[at]) | uint32_t(p[at + 1]) << 8 | uint32_t(p[at + 2]) << 16 | uint32_t(p[at + 3]) << 24;
    return swap ? __builtin_bswap32(v) : v;
  }
};

uint16_t be16(const uint8_t* p) { return uint16_t(p[0] << 8 | p[1]); }
uint32_t be32(const uint8_t* p) { return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3]; }

enum : uint32_t {
  kEthernet = 1,
  kNull = 0,
  kRaw = 101,
  kRawAlt = 12,
  kRawAlt2 = 14,
  kLinuxSll = 113,
  kLinuxSll2 = 276,
  kLoop = 108,
};

// One captured frame: finds the IPv4 packet in it and keeps its UDP or
// TCP payload.
void takeFrame(uint32_t linkType, const uint8_t* f, size_t n, double time, std::vector<Datagram>& out,
               CaptureStats& st) {
  ++st.frames;
  size_t ip = 0;
  uint16_t etherType = 0x0800;
  switch (linkType) {
    case kEthernet: {
      if (n < 14) return void(++st.skipped);
      etherType = be16(f + 12);
      ip = 14;
      while ((etherType == 0x8100 || etherType == 0x88A8) && n >= ip + 4) {
        etherType = be16(f + ip + 2);
        ip += 4;
      }
      break;
    }
    case kLinuxSll:
      if (n < 16) return void(++st.skipped);
      etherType = be16(f + 14);
      ip = 16;
      break;
    case kLinuxSll2:
      if (n < 20) return void(++st.skipped);
      etherType = be16(f);
      ip = 20;
      break;
    case kNull:
    case kLoop: {
      if (n < 4) return void(++st.skipped);
      uint32_t family;
      std::memcpy(&family, f, 4);
      if (family != 2 && __builtin_bswap32(family) != 2) return void(++st.skipped);
      ip = 4;
      break;
    }
    case kRaw:
    case kRawAlt:
    case kRawAlt2:
      break;
    default:
      return void(++st.skipped);
  }
  if (etherType != 0x0800 || n < ip + 20 || (f[ip] >> 4) != 4) return void(++st.skipped);
  const size_t ihl = size_t(f[ip] & 15) * 4;
  const size_t total = be16(f + ip + 2);
  if (ihl < 20 || total < ihl || n < ip + total) return void(++st.skipped);
  const uint16_t frag = be16(f + ip + 6);
  if (frag & 0x3FFF) return void(++st.fragments);  // more fragments or an offset
  const uint8_t proto = f[ip + 9];
  Datagram d;
  d.time = time;
  d.srcIp = be32(f + ip + 12);
  d.dstIp = be32(f + ip + 16);
  const uint8_t* l4 = f + ip + ihl;
  const size_t l4n = total - ihl;
  if (proto == 17) {
    if (l4n < 8) return void(++st.skipped);
    const size_t len = be16(l4 + 4);
    if (len < 8 || len > l4n) return void(++st.skipped);
    d.srcPort = be16(l4);
    d.dstPort = be16(l4 + 2);
    d.payload.assign(reinterpret_cast<const char*>(l4 + 8), len - 8);
    ++st.udp;
  } else if (proto == 6) {
    if (l4n < 20) return void(++st.skipped);
    const size_t off = size_t(l4[12] >> 4) * 4;
    if (off < 20 || off > l4n) return void(++st.skipped);
    d.udp = false;
    d.srcPort = be16(l4);
    d.dstPort = be16(l4 + 2);
    d.payload.assign(reinterpret_cast<const char*>(l4 + off), l4n - off);
    ++st.tcp;
  } else {
    return void(++st.skipped);
  }
  out.push_back(std::move(d));
}

bool readPcap(const In& in, std::vector<Datagram>& out, CaptureStats& st, std::string& error, bool nano) {
  if (in.n < 24) return error = "capture: short pcap header", false;
  const uint32_t linkType = in.u32(20) & 0x0FFFFFFF;
  size_t at = 24;
  bool first = true;
  double t0 = 0;
  while (in.n - at >= 16) {
    const double t = in.u32(at) + in.u32(at + 4) * (nano ? 1e-9 : 1e-6);
    const size_t caplen = in.u32(at + 8);
    at += 16;
    if (caplen > in.n - at) return error = "capture: a packet runs past the end of the file", false;
    if (first) t0 = t, first = false;
    takeFrame(linkType, in.p + at, caplen, t - t0, out, st);
    at += caplen;
  }
  return true;
}

bool readPcapng(const uint8_t* p, size_t n, std::vector<Datagram>& out, CaptureStats& st, std::string& error) {
  In in{p, n};
  std::vector<std::pair<uint32_t, double>> interfaces;  // link type, seconds per tick
  size_t at = 0;
  bool first = true;
  double t0 = 0;
  while (n - at >= 12) {
    if (in.u32(at) == 0x0A0D0D0A) {  // section header: the byte order may change
      if (n - at < 12) break;
      const uint32_t magic = In{p, n}.u32(at + 8);
      in.swap = magic == 0x4D3C2B1A;
      if (!in.swap && magic != 0x1A2B3C4D) return error = "capture: bad pcapng section", false;
      interfaces.clear();
    }
    const uint32_t type = in.u32(at);
    const size_t len = in.u32(at + 4);
    if (len < 12 || len % 4 || len > n - at) return error = "capture: a pcapng block runs past the end", false;
    const uint8_t* b = p + at + 8;
    const size_t bn = len - 12;
    if (type == 1 && bn >= 8) {  // interface description
      double tick = 1e-6;
      size_t o = 8;
      while (bn - o >= 4) {
        const uint16_t code = in.u16(size_t(b - p) + o);
        const uint16_t olen = in.u16(size_t(b - p) + o + 2);
        if (code == 0 || size_t(olen) > bn - o - 4) break;
        if (code == 9 && olen >= 1) {  // if_tsresol
          const uint8_t r = b[o + 4];
          tick = (r & 0x80) ? std::ldexp(1.0, -int(r & 0x7F)) : std::pow(10.0, -int(r));
        }
        o += 4 + ((olen + 3u) & ~3u);
      }
      interfaces.push_back({in.u16(size_t(b - p)), tick});
    } else if (type == 6 && bn >= 20) {  // enhanced packet
      const uint32_t id = in.u32(size_t(b - p));
      const uint64_t ticks = uint64_t(in.u32(size_t(b - p) + 4)) << 32 | in.u32(size_t(b - p) + 8);
      const size_t caplen = in.u32(size_t(b - p) + 12);
      if (id < interfaces.size() && caplen <= bn - 20) {
        const double t = double(ticks) * interfaces[id].second;
        if (first) t0 = t, first = false;
        takeFrame(interfaces[id].first, b + 20, caplen, t - t0, out, st);
      } else {
        ++st.skipped;
      }
    } else if (type == 3 && bn >= 4 && !interfaces.empty()) {  // simple packet
      const size_t orig = in.u32(size_t(b - p));
      takeFrame(interfaces[0].first, b + 4, std::min(orig, bn - 4), 0, out, st);
    }
    at += len;
  }
  return true;
}

}  // namespace

bool readCapture(const std::string& bytes, std::vector<Datagram>& out, CaptureStats& stats, std::string& error) {
  const auto* p = reinterpret_cast<const uint8_t*>(bytes.data());
  const size_t n = bytes.size();
  if (n < 4) return error = "capture: empty file", false;
  const uint32_t magic = In{p, n}.u32(0);
  switch (magic) {
    case 0xA1B2C3D4: return readPcap(In{p, n, false}, out, stats, error, false);
    case 0xD4C3B2A1: return readPcap(In{p, n, true}, out, stats, error, false);
    case 0xA1B23C4D: return readPcap(In{p, n, false}, out, stats, error, true);
    case 0x4D3CB2A1: return readPcap(In{p, n, true}, out, stats, error, true);
    case 0x0A0D0D0A: return readPcapng(p, n, out, stats, error);
    default: return error = "capture: not a pcap or pcapng file", false;
  }
}

std::string ipText(uint32_t ip) {
  return std::to_string(ip >> 24) + "." + std::to_string(ip >> 16 & 255) + "." + std::to_string(ip >> 8 & 255) + "." +
         std::to_string(ip & 255);
}

ReplayResult replay(const std::vector<Datagram>& datagrams, const ReplayOptions& options,
                    std::unique_ptr<Link>& link) {
  ReplayResult res;
  long start = -1;
  for (size_t i = 0; i < datagrams.size() && start < 0; ++i) {
    const Datagram& d = datagrams[i];
    if (d.udp && d.payload.size() == 5 && uint8_t(d.payload[0]) == 0x1A &&
        (options.serverPort == 0 || d.dstPort == options.serverPort))
      start = long(i);
  }
  if (start < 0) return res;
  const Datagram& ch = datagrams[size_t(start)];
  BitReader r(ch.payload);
  r.u8();
  res.found = true;
  res.sequence = r.u32();
  res.clientIp = ch.srcIp;
  res.clientPort = ch.srcPort;
  res.serverIp = ch.dstIp;
  res.serverPort = ch.dstPort;
  const double t0 = ch.time;
  double now = 0;
  auto note = [&](const std::string& s) { res.events.push_back({now, s}); };

  LinkLogin login;
  login.protocol = options.protocol;
  login.connectSequence = res.sequence;
  login.replay = true;
  Link::Callbacks cb;
  cb.log = [&](const std::string& s) { note(s); };
  cb.loginStep = [&](int s) { note("step " + std::to_string(s)); };
  cb.error = [&](const std::string& s) { note("error " + s); };
  cb.text = [&](const BigText& t) {
    res.texts.push_back(t);
    note("text " + t.s1 + " / " + t.s2 + " / " + t.s3 + " (" + std::to_string(t.data.size()) + " bytes)");
  };
  link = std::make_unique<Link>(login, cb);
  link->start(0);
  for (size_t i = size_t(start); i < datagrams.size(); ++i) {
    const Datagram& d = datagrams[i];
    if (!d.udp) continue;
    if (d.srcIp == res.clientIp && d.srcPort == res.clientPort && d.dstIp == res.serverIp &&
        d.dstPort == res.serverPort) {
      ++res.clientPackets;
      continue;
    }
    if (!(d.srcIp == res.serverIp && d.srcPort == res.serverPort && d.dstIp == res.clientIp &&
          d.dstPort == res.clientPort))
      continue;
    const double t = d.time - t0;
    if (options.stopAt >= 0 && t > options.stopAt) break;
    now = t;
    res.lastTime = t;
    ++res.serverPackets;
    link->receive(d.payload, uint32_t(t * 1000.0));
    link->takeOutgoing();
    if (link->state() == Link::State::Closed) break;
  }
  return res;
}

}  // namespace graal3d::capture
