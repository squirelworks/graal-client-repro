// The capture reader and session replay (tools/capture.*) against the
// recorded server session of the link test, wrapped in made-up captures;
// and the tools' PNG writer.
#include "../render/texture.hpp"
#include "../tools/capture.hpp"
#include "../tools/png.hpp"
#include "bits.hpp"
#include "vectors.hpp"

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>

using namespace graal3d;
using namespace graal3d::capture;

static int failures = 0;
#define CHECK(cond)                                                      \
  do {                                                                   \
    if (!(cond)) {                                                       \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                        \
    }                                                                    \
  } while (0)

namespace {

std::string fromHex(const char* h) {
  std::string out;
  for (size_t i = 0; h[i] && h[i + 1]; i += 2) out += char(std::stoi(std::string(h + i, 2), nullptr, 16));
  return out;
}

const uint32_t kClientIp = 0x0A000002, kServerIp = 0x0A000001;
const uint16_t kClientPort = 50000, kServerPort = 14918;

std::string challengeRequest() {
  BitWriter w;
  w.u8(0x1A);
  w.u32(0x400);
  return w.bytes();
}

std::string challengeResponse() {
  BitWriter w;
  w.u8(0x1E);
  w.u32(0x400);
  for (uint32_t d : {0x03020100u, 0x07060504u, 0x0b0a0908u, 0x0f0e0d0cu}) w.u32(d);
  return w.bytes();
}

struct Packet {
  double time;
  uint32_t src, dst;
  uint16_t sport, dport;
  int proto;  // 17 UDP, 6 TCP
  std::string payload;
  uint16_t frag = 0;
};

void be16(std::string& s, uint16_t v) {
  s += char(v >> 8);
  s += char(v);
}
void be32(std::string& s, uint32_t v) {
  be16(s, uint16_t(v >> 16));
  be16(s, uint16_t(v));
}
void le32(std::string& s, uint32_t v) {
  for (int i = 0; i < 4; ++i) s += char(v >> (8 * i));
}
void le16(std::string& s, uint16_t v) {
  s += char(v);
  s += char(v >> 8);
}

// An Ethernet frame (with a VLAN tag when asked) around an IPv4 packet.
std::string frame(const Packet& p, bool vlan) {
  std::string l4;
  if (p.proto == 17) {
    be16(l4, p.sport);
    be16(l4, p.dport);
    be16(l4, uint16_t(8 + p.payload.size()));
    be16(l4, 0);
  } else {
    be16(l4, p.sport);
    be16(l4, p.dport);
    be32(l4, 1);
    be32(l4, 0);
    l4 += char(5 << 4);
    l4 += char(0x18);
    be16(l4, 0xFFFF);
    be32(l4, 0);
  }
  l4 += p.payload;
  std::string ip;
  ip += char(0x45);
  ip += char(0);
  be16(ip, uint16_t(20 + l4.size()));
  be32(ip, 0);
  ip[6] = char(p.frag >> 8);
  ip[7] = char(p.frag);
  ip += char(64);
  ip += char(p.proto);
  be16(ip, 0);
  be32(ip, p.src);
  be32(ip, p.dst);
  std::string f(12, '\x02');
  if (vlan) {
    be16(f, 0x8100);
    be16(f, 7);
  }
  be16(f, 0x0800);
  return f + ip + l4;
}

std::vector<Packet> session() {
  std::vector<Packet> v;
  double t = 100.0;
  auto up = [&](const std::string& s) { v.push_back({t += 0.01, kClientIp, kServerIp, kClientPort, kServerPort, 17, s}); };
  auto down = [&](const std::string& s) { v.push_back({t += 0.01, kServerIp, kClientIp, kServerPort, kClientPort, 17, s}); };
  // Noise before the session: other traffic, TCP, a fragment.
  v.push_back({t, kClientIp, 0x08080808, 5353, 53, 17, "dns?"});
  v.push_back({t += 0.01, kClientIp, kServerIp, 50001, 14917, 6, "GNP1905C"});
  v.push_back({t += 0.01, kServerIp, kClientIp, kServerPort, kClientPort, 17, "frag", 0x2000});
  up(challengeRequest());
  down(challengeResponse());
  up(fromHex(kConnectRequest));
  down(fromHex(kAcceptFull));
  up(fromHex(kClientData1));
  for (const char* s : kServer) {
    down(fromHex(s));
    up(fromHex(kClientData2));
  }
  // A packet from another server port: not this session's.
  v.push_back({t += 0.01, kServerIp, kClientIp, 9999, kClientPort, 17, fromHex(kServer[0])});
  return v;
}

std::string pcap(const std::vector<Packet>& packets, bool bigEndian, bool vlan) {
  auto u32 = [&](std::string& s, uint32_t x) { bigEndian ? be32(s, x) : le32(s, x); };
  auto u16 = [&](std::string& s, uint16_t x) { bigEndian ? be16(s, x) : le16(s, x); };
  std::string out;
  u32(out, 0xA1B2C3D4);
  u16(out, 2);
  u16(out, 4);
  u32(out, 0);
  u32(out, 0);
  u32(out, 65535);
  u32(out, 1);
  for (const Packet& p : packets) {
    const std::string f = frame(p, vlan);
    u32(out, uint32_t(p.time));
    u32(out, uint32_t((p.time - uint32_t(p.time)) * 1e6 + 0.5));
    u32(out, uint32_t(f.size()));
    u32(out, uint32_t(f.size()));
    out += f;
  }
  return out;
}

void block(std::string& out, uint32_t type, const std::string& body) {
  std::string b = body;
  while (b.size() % 4) b += char(0);
  le32(out, type);
  le32(out, uint32_t(b.size() + 12));
  out += b;
  le32(out, uint32_t(b.size() + 12));
}

std::string pcapng(const std::vector<Packet>& packets) {
  std::string out, shb, idb;
  le32(shb, 0x1A2B3C4D);
  le16(shb, 1);
  le16(shb, 0);
  le32(shb, 0xFFFFFFFF);
  le32(shb, 0xFFFFFFFF);
  block(out, 0x0A0D0D0A, shb);
  le16(idb, 1);  // Ethernet
  le16(idb, 0);
  le32(idb, 65535);
  le16(idb, 9);  // if_tsresol: 10^-9
  le16(idb, 1);
  idb += std::string("\x09\0\0\0", 4);
  le32(idb, 0);  // end of options
  block(out, 1, idb);
  for (const Packet& p : packets) {
    const std::string f = frame(p, false);
    const uint64_t ns = uint64_t(p.time * 1e9 + 0.5);
    std::string epb;
    le32(epb, 0);
    le32(epb, uint32_t(ns >> 32));
    le32(epb, uint32_t(ns));
    le32(epb, uint32_t(f.size()));
    le32(epb, uint32_t(f.size()));
    epb += f;
    block(out, 6, epb);
  }
  return out;
}

void checkSession(const std::string& bytes, const char* what) {
  std::vector<Datagram> d;
  CaptureStats st;
  std::string error;
  const bool ok = readCapture(bytes, d, st, error);
  if (!ok) std::fprintf(stderr, "%s: %s\n", what, error.c_str());
  CHECK(ok);
  CHECK(st.frames == 19);
  CHECK(st.tcp == 1);
  CHECK(st.fragments == 1);
  CHECK(st.udp == 17);
  CHECK(d.size() == 18);
  CHECK(d[0].time == 0);
  CHECK(!d[1].udp && d[1].payload == "GNP1905C" && d[1].dstPort == 14917);

  std::unique_ptr<Link> link;
  const ReplayResult r = replay(d, {}, link);
  CHECK(r.found);
  CHECK(r.sequence == 0x400);
  CHECK(r.serverPort == kServerPort && r.clientPort == kClientPort);
  CHECK(r.serverIp == kServerIp && r.clientIp == kClientIp);
  CHECK(ipText(r.serverIp) == "10.0.0.1");
  CHECK(r.serverPackets == 7);
  CHECK(r.clientPackets == 8);
  CHECK(link && link->state() == Link::State::Connected);
  CHECK(link->loginStep() == 6);
  CHECK(link->controlGhost() == 1);
  CHECK(link->ghosts().size() == 2);
  CHECK(link->ghosts().count(0) && link->ghosts().at(0).className == "Sun");
  CHECK(link->ghosts().count(1) && link->ghosts().at(1).object.shape == "labcube.3ds");
  CHECK((link->commandsReceived() == std::vector<std::string>{"MissionStartPhase1", "MissionStartPhase2"}));
  bool step6 = false;
  for (const auto& e : r.events) step6 |= e.what == "step 6";
  CHECK(step6);
  CHECK(r.lastTime > 0.1 && r.lastTime < 0.2);
}

void testCaptures() {
  checkSession(pcap(session(), false, false), "pcap");
  checkSession(pcap(session(), true, true), "pcap, big-endian, VLAN");
  checkSession(pcapng(session()), "pcapng");
}

void testStopAt() {
  std::vector<Datagram> d;
  CaptureStats st;
  std::string error;
  CHECK(readCapture(pcap(session(), false, false), d, st, error));
  // The challenge is at 0.03 s; the accept 0.04 s after it, the first
  // mission packet 0.06 s after it.
  ReplayOptions o;
  o.stopAt = 0.045;
  std::unique_ptr<Link> link;
  ReplayResult r = replay(d, o, link);
  CHECK(r.serverPackets == 2);
  CHECK(link->state() == Link::State::Connected);
  CHECK(link->ghosts().empty());
  // A port with no challenge to it finds no session.
  o = {};
  o.serverPort = 1234;
  r = replay(d, o, link);
  CHECK(!r.found);
}

void testBadCaptures() {
  std::vector<Datagram> d;
  CaptureStats st;
  std::string error;
  CHECK(!readCapture("", d, st, error));
  CHECK(!readCapture("not a capture", d, st, error));
  std::string cut = pcap(session(), false, false);
  cut.resize(cut.size() - 3);
  CHECK(!readCapture(cut, d, st, error));
  CHECK(error.find("past the end") != std::string::npos);
  // A capture with no session in it.
  d.clear();
  CHECK(readCapture(pcap({{1.0, kClientIp, kServerIp, 1, 2, 17, "x"}}, false, false), d, st, error));
  std::unique_ptr<Link> link;
  CHECK(!replay(d, {}, link).found);
  // Every truncation of a pcapng file is refused or read without harm.
  const std::string ng = pcapng(session());
  for (size_t n = 0; n < ng.size(); n += 7) {
    d.clear();
    readCapture(ng.substr(0, n), d, st, error);
  }
}

void testPng() {
  const uint32_t px[6] = {render::packRgba(255, 0, 0), render::packRgba(0, 255, 0), 0xDEADBEEF,
                          render::packRgba(0, 0, 255), render::packRgba(10, 20, 30), 0xDEADBEEF};
  const std::string path = (std::filesystem::temp_directory_path() / "g3d-replay-test.png").string();
  CHECK(tools::writePng(path, px, 2, 2, 3));
  std::string b;
  {
    std::ifstream f(path, std::ios::binary);  // closed before the remove (Windows)
    std::stringstream ss;
    ss << f.rdbuf();
    b = ss.str();
  }
  render::Texture t;
  std::string error;
  CHECK(render::decodeImage(reinterpret_cast<const uint8_t*>(b.data()), b.size(), t, error));
  CHECK(t.width == 2 && t.height == 2);
  if (t.pixels.size() == 4) {
    CHECK(t.pixels[0] == render::packRgba(255, 0, 0));
    CHECK(t.pixels[1] == render::packRgba(0, 255, 0));
    CHECK(t.pixels[2] == render::packRgba(0, 0, 255));
    CHECK(t.pixels[3] == render::packRgba(10, 20, 30));
  }
  std::error_code ec;
  std::filesystem::remove(path, ec);
  CHECK(!tools::writePng(path, px, 0, 2, 3));
  CHECK(!tools::writePng("/nonexistent-dir/x.png", px, 2, 2, 3));
}

}  // namespace

int main() {
  testCaptures();
  testStopAt();
  testBadCaptures();
  testPng();
  if (failures) {
    std::fprintf(stderr, "replay-test: %d check(s) failed\n", failures);
    return 1;
  }
  std::printf("replay-test: all checks passed\n");
  return 0;
}
