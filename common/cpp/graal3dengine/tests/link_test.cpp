// The 3D link against the decoded real-client vectors in Graal_analysis
// torque/udp-session.md (§3 handshake, §4 first client packets, §8 ghost
// payloads and the server session). The bytes are copied from that note;
// "[run]" vectors are a real 5.12 client's, "[srv]" ones the Seihai test
// gserver's.
#include "bits.hpp"
#include "link.hpp"
#include "world.hpp"
#include "vectors.hpp"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

using namespace graal3d;

static int failures = 0;
#define CHECK(cond)                                                      \
  do {                                                                   \
    if (!(cond)) {                                                       \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                        \
    }                                                                    \
  } while (0)

namespace {

const uint32_t kDigest[4] = {0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c};

std::string challengeResponse() {
  BitWriter w;
  w.u8(0x1E);
  w.u32(0x400);
  for (auto d : kDigest) w.u32(d);
  return w.bytes();
}

bool near(float a, float b) { return std::fabs(a - b) < 1e-4f; }

// What a server reads from one client data packet: the header, the game
// section and the guaranteed events (class id, payload start, length).
struct ClientPacket {
  int seq = -1, ack = -1, type = -1;
  bool firstPerson = false, hasControl = false, ownState = false;
  int controlGhost = -1;
  GameObjectState own;
  std::vector<std::pair<int, std::string>> commands;  // class id, command name
};

ClientPacket readClientPacket(const std::string& bytes, const std::map<int, std::string>& events) {
  ClientPacket p;
  BitReader r(bytes);
  if (!r.flag()) return p;
  r.bits(1);
  p.seq = static_cast<int>(r.bits(9));
  p.ack = static_cast<int>(r.bits(9));
  p.type = static_cast<int>(r.bits(2));
  const int n = static_cast<int>(r.bits(3));
  r.bits(8 * n);
  if (p.type != 0) return p;
  if (r.flag()) r.bits(20);
  if (r.flag()) r.bits(20);
  p.firstPerson = r.flag();
  r.f32();
  r.f32();
  r.f32();
  if ((p.hasControl = r.flag())) p.controlGhost = static_cast<int>(r.bits(12));
  if ((p.ownState = r.flag())) readGameObjectUpdate(r, p.own);
  if (r.flag()) r.bits(8);
  while (r.flag()) {
    r.bits(12);
    r.seek(r.pos() + r.bits(14));
  }
  while (r.flag()) {
    if (!r.flag()) r.bits(7);
    const int cls = static_cast<int>(r.bits(12));
    const uint32_t len = r.bits(14);
    const size_t start = r.pos();
    std::string name;
    auto it = events.find(cls);
    if (it != events.end() && it->second == "RemoteCommandEvent") {
      const int argc = static_cast<int>(r.bits(5));
      if (argc > 0 && r.bits(2) == 1) name = r.pstring();
    }
    p.commands.emplace_back(cls, name);
    r.seek(start + len);
  }
  return p;
}

void testHuffmanAndRequest() {
  // The writer reproduces the real 5.12 client's connect request.
  LinkLogin login;
  login.account = "guest";
  login.password = "7Y3bdzjf";
  login.protocol = 24;
  Link link(login, {});
  link.start(0);
  auto out = link.takeOutgoing();
  CHECK(out.size() == 1);
  CHECK(toHex(out[0]) == "1a00040000");
  link.receive(challengeResponse(), 10);
  out = link.takeOutgoing();
  CHECK(out.size() == 1);
  CHECK(toHex(out[0]) == kConnectRequest);
  CHECK(out[0].size() == 71);
  CHECK(link.state() == Link::State::Connecting);

  // The request decodes with no bits left over.
  BitReader r(fromHex(kConnectRequest));
  r.u8();
  r.u32();
  for (int i = 0; i < 4; ++i) r.u32();
  CHECK(r.string() == "GameConnection");
  CHECK(r.u32() == 0);
  CHECK(r.u32() == 0xFFFFFFFFu);
  CHECK(r.string() == "Graal3D");
  CHECK(r.u32() == 24);
  CHECK(r.u32() == 24);
  CHECK(r.string() == "7Y3bdzjf");
  CHECK(r.u32() == 2);
  CHECK(r.string() == "guest");
  CHECK(r.string().empty());
  CHECK(r.left() == 0);
}

void testAcceptsAndFirstPackets() {
  std::vector<std::string> logs;
  LinkLogin login;
  login.account = "guest";
  login.password = "7Y3bdzjf";
  Link link(login, {[&](const std::string& s) { logs.push_back(s); }, nullptr, nullptr, nullptr});
  link.start(0);
  link.receive(challengeResponse(), 1);
  link.takeOutgoing();
  link.receive(fromHex(kAcceptEmpty), 2);
  CHECK(link.state() == Link::State::Connected);
  CHECK(!logs.empty() && logs.back() == "Connection established");
  auto out = link.takeOutgoing();
  CHECK(out.size() == 1);
  CHECK(toHex(out[0]) == kClientData1);
  link.tick(2 + Link::kKeepAliveMs);
  out = link.takeOutgoing();
  CHECK(out.size() == 1);
  CHECK(toHex(out[0]) == kClientData2);

  // The full protocol-24 table: ten object classes, nine event classes.
  Link full(login, {});
  full.start(0);
  full.receive(challengeResponse(), 1);
  full.receive(fromHex(kAcceptFull), 2);
  CHECK(full.state() == Link::State::Connected);
  CHECK(full.objectClasses().size() == 10);
  CHECK(full.eventClasses().size() == 9);
  CHECK(full.objectClasses().at(0) == "Camera");
  CHECK(full.objectClasses().at(4) == "GameObject");
  CHECK(full.objectClasses().at(9) == "fxSunLight");
  CHECK(full.eventClasses().at(5) == "RemoteCommandEvent");
  CHECK(full.eventClasses().at(8) == "TerrainRequestUpdatesEvent");

  // Another protocol is refused.
  LinkLogin old = login;
  old.protocol = 21;
  std::string error;
  Link refused(old, {nullptr, nullptr, [&](const std::string& e) { error = e; }, nullptr});
  refused.start(0);
  refused.receive(challengeResponse(), 1);
  refused.receive(fromHex(kAcceptEmpty), 2);
  CHECK(refused.state() == Link::State::Closed);
  CHECK(error.find("protocol 24") != std::string::npos);
}

void testPayloads() {
  {
    BitReader r(fromHex(kGameObject));
    GameObjectState o;
    CHECK(readGameObjectUpdate(r, o));
    CHECK(r.pos() == 471);
    CHECK(o.name == "G3DPlayer_lab");
    CHECK(o.shape == "labcube.3ds");
    CHECK(near(o.position.z, 1) && near(o.position.x, 0));
    CHECK(near(o.axis.z, 1));
    CHECK(o.nickname == "lab");
    CHECK(o.nickColor[0] == 255 && o.nickColor[3] == 255);
    CHECK(o.flags == 0x48);
    // Written back with the same sections, the bits are the same.
    BitWriter w;
    writeGameObjectUpdate(w, o, (1u << 0) | (1u << 2) | (1u << 4) | (1u << 11) | (1u << 12));
    CHECK(w.pos() == 471);
    CHECK(toHex(w.bytes()) == kGameObject);
  }
  {
    BitReader r(fromHex("0000"));
    GameObjectState o;
    CHECK(readGameObjectUpdate(r, o));
    CHECK(r.pos() == 13);
  }
  {
    BitReader r(fromHex(kSun));
    SunState s;
    CHECK(readSunUpdate(r, s));
    CHECK(r.pos() == 379);
    CHECK(s.name == "Sun");
    CHECK(near(s.direction.x, 0.57735f) && near(s.direction.z, -0.57735f));
    CHECK(near(s.color[0], 0.8f) && near(s.ambient[2], 0.35f));
  }
  {
    BitReader r(fromHex(kSky));
    SkyState s;
    CHECK(readSkyUpdate(r, s));
    CHECK(s.name == "Sky");
    CHECK(near(s.visibleDistance, 500));
    CHECK(s.textures == "sky_fr,sky_rt,sky_bk,sky_lf,sky_up,sky_dn");
    CHECK(near(s.fogColor.x, 0.5f) && near(s.fogColor.y, 0.6f) && near(s.fogColor.z, 0.8f));
  }
}

void testServerSession() {
  // The whole server session of §8 against this client.
  std::vector<int> steps;
  std::vector<std::string> logs;
  LinkLogin login;
  login.account = "guest";
  login.password = "7Y3bdzjf";
  Link link(login, {[&](const std::string& s) { logs.push_back(s); }, [&](int s) { steps.push_back(s); }, nullptr,
                    nullptr});
  uint32_t t = 0;
  link.start(t);
  link.receive(challengeResponse(), ++t);
  link.takeOutgoing();
  link.receive(fromHex(kAcceptFull), ++t);
  auto out = link.takeOutgoing();
  CHECK(out.size() == 1);
  CHECK(toHex(out[0]) == kClientData1);
  const auto& ev = link.eventClasses();

  // seq 1: MissionStartPhase1, the Sun and the player's GameObject.
  link.receive(fromHex(kServer[0]), ++t);
  CHECK((steps == std::vector<int>{2}));
  CHECK(link.ghosts().size() == 2);
  CHECK(link.ghosts().at(0).className == "Sun");
  CHECK(link.ghosts().at(0).sun.name == "Sun");
  CHECK(link.ghosts().at(1).className == "GameObject");
  CHECK(link.ghosts().at(1).object.name == "G3DPlayer_lab");
  CHECK(link.ghosts().at(1).object.shape == "labcube.3ds");
  out = link.takeOutgoing();
  CHECK(out.size() == 1);
  auto p = readClientPacket(out[0], ev);
  CHECK(p.seq == 2 && p.ack == 1 && p.type == 0);
  CHECK(p.commands.size() == 1 && p.commands[0].second == "MissionStartPhase1Ack");

  // seq 2: MissionStartPhase2.
  link.receive(fromHex(kServer[1]), ++t);
  CHECK((steps == std::vector<int>{2, 3, 4}));
  out = link.takeOutgoing();
  CHECK(out.size() == 1);
  p = readClientPacket(out[0], ev);
  CHECK(p.seq == 3 && p.ack == 2);
  CHECK(p.commands.size() == 1 && p.commands[0].second == "MissionStartPhase2Ack");

  // seq 3: the control object, ghost 1: steps 5 and 6, and the client
  // sends the object's shape, transform and flags back.
  link.receive(fromHex(kServer[2]), ++t);
  CHECK((steps == std::vector<int>{2, 3, 4, 5, 6}));
  CHECK(link.controlGhost() == 1);
  CHECK(link.loginStep() == 6);
  out = link.takeOutgoing();
  CHECK(out.size() == 1);
  p = readClientPacket(out[0], ev);
  CHECK(p.seq == 4 && p.ack == 3);
  CHECK(p.hasControl && p.controlGhost == 1 && p.ownState);
  CHECK(p.own.shape == "labcube.3ds");
  CHECK(p.own.hasTransform && near(p.own.axis.x, 1) && near(p.own.angle, 0));
  CHECK(p.own.flags == 0x48);
  CHECK(p.commands.empty());

  // seq 4: keep-alive; answered with an ack packet (5 bytes).
  link.receive(fromHex(kServer[3]), ++t);
  out = link.takeOutgoing();
  CHECK(out.size() == 1 && out[0].size() == 5);
  p = readClientPacket(out[0], ev);
  CHECK(p.type == 2 && p.seq == 4 && p.ack == 4);

  // A second later the client sends its own keep-alive: position, ghost
  // and an empty update (21 bytes with one ack byte).
  t += Link::kKeepAliveMs;
  link.tick(t);
  out = link.takeOutgoing();
  CHECK(out.size() == 1);
  CHECK(out[0].size() == 21);
  p = readClientPacket(out[0], ev);
  CHECK(p.seq == 5 && p.hasControl && p.ownState);
  CHECK(!p.own.hasTransform && p.own.shape.empty());

  // seq 5 acks our 5 and is taken.
  link.receive(fromHex(kServer[4]), ++t);
  CHECK(link.state() == Link::State::Connected);
  CHECK((link.commandsReceived() == std::vector<std::string>{"MissionStartPhase1", "MissionStartPhase2"}));
  bool phase1 = false;
  for (const auto& l : logs) phase1 |= l == "Phase 1: Download Ghost Objects";
  CHECK(phase1);
}

void testLostEventIsResent() {
  // The server's first packet does not ack our ack-carrying packet: the
  // event goes out again in the next data packet.
  LinkLogin login;
  Link link(login, {});
  link.start(0);
  link.receive(challengeResponse(), 1);
  link.receive(fromHex(kAcceptFull), 2);
  link.takeOutgoing();
  link.receive(fromHex(kServer[0]), 3);  // Phase1 -> our seq 2 carries the ack
  link.takeOutgoing();
  // A server keep-alive (seq 2) that acks our seq 2 as lost: highest ack
  // 2, one mask byte with only bit 1 (our seq 1) set.
  BitWriter w;
  w.flag(true);
  w.bits(0, 1);
  w.bits(2, 9);
  w.bits(2, 9);
  w.bits(0, 2);
  w.bits(1, 3);
  w.bits(0x02, 8);
  w.flag(false);
  w.flag(false);
  w.flag(false);  // control
  w.flag(false);  // camera
  w.flag(false);  // fov
  w.flag(false);  // unguaranteed
  w.flag(false);  // guaranteed
  w.flag(false);  // ghosts
  link.receive(w.bytes(), 4);
  auto out = link.takeOutgoing();
  CHECK(out.size() == 1);
  auto p = readClientPacket(out[0], link.eventClasses());
  CHECK(p.seq == 3);
  CHECK(p.commands.size() == 1 && p.commands[0].second == "MissionStartPhase1Ack");
}

void testTimeouts() {
  std::string error;
  LinkLogin login;
  Link link(login, {nullptr, nullptr, [&](const std::string& e) { error = e; }, nullptr});
  link.start(0);
  link.tick(Link::kResendMs);
  auto out = link.takeOutgoing();
  CHECK(out.size() == 2 && out[1] == out[0]);  // the challenge again
  link.tick(Link::kConnectTimeoutMs + 1);
  CHECK(link.state() == Link::State::Closed);
  CHECK(error == "The connection to the Graal3D server couldn't be established.");

  error.clear();
  Link quiet(login, {nullptr, nullptr, [&](const std::string& e) { error = e; }, nullptr});
  quiet.start(0);
  quiet.receive(challengeResponse(), 1);
  quiet.receive(fromHex(kAcceptEmpty), 2);
  quiet.tick(2 + Link::kSilenceTimeoutMs + 1);
  CHECK(error == "The 3D server connection has timed out");
}

void testProtocols() {
  CHECK(protocolForBuild("4.04r2") == 19);
  CHECK(protocolForBuild("4.20r6") == 21);
  CHECK(protocolForBuild("4.20r8") == 21);
  CHECK(protocolForBuild("5.00r7") == 24);
  CHECK(protocolForBuild("5.12") == 24);
}

void testServerText() {
  // A BigData `events` message from the server, uncompressed and zlib.
  LinkLogin login;
  std::vector<BigText> got;
  Link link(login, {nullptr, nullptr, nullptr, [&](const BigText& t) { got.push_back(t); }});
  link.start(0);
  link.receive(challengeResponse(), 1);
  link.receive(fromHex(kAcceptFull), 2);
  link.takeOutgoing();
  const auto& ev = link.eventClasses();
  auto idOf = [&](const std::string& n) {
    for (const auto& [id, name] : ev)
      if (name == n) return id;
    return -1;
  };
  BitWriter w;
  w.flag(true);
  w.bits(0, 1);
  w.bits(1, 9);
  w.bits(1, 9);
  w.bits(0, 2);
  w.bits(1, 3);
  w.bits(1, 8);
  w.flag(false);
  w.flag(false);
  w.flag(false);
  w.flag(false);
  w.flag(false);
  w.flag(false);  // unguaranteed
  const std::string text = "s lab.flag\n";
  BitWriter start;
  start.bits(7, 16);
  start.pstring("");
  start.pstring("events");
  start.pstring("");
  start.bits(static_cast<uint32_t>(text.size()), 24);
  start.bits(0, 3);
  BitWriter chunk;
  chunk.bits(7, 16);
  chunk.bits(static_cast<uint32_t>(text.size()), 8);
  for (unsigned char c : text) chunk.u8(c);
  w.flag(true);
  w.flag(false);
  w.bits(0, 7);
  w.bits(static_cast<uint32_t>(idOf("BigDataStartEvent")), 12);
  w.bits(static_cast<uint32_t>(start.pos()), 14);
  w.append(start);
  w.flag(true);
  w.flag(true);
  w.bits(static_cast<uint32_t>(idOf("BigDataChunkEvent")), 12);
  w.bits(static_cast<uint32_t>(chunk.pos()), 14);
  w.append(chunk);
  w.flag(false);
  w.flag(false);
  link.receive(w.bytes(), 3);
  CHECK(got.size() == 1);
  CHECK(got.size() == 1 && got[0].s2 == "events" && got[0].data == text);

  // The client's own events message goes out as a start and a chunk.
  link.takeOutgoing();
  link.queueEventLine("w Bow");
  link.queueEventLine("s client.lab=1");
  link.flushEventLines();
  link.tick(4);
  auto out = link.takeOutgoing();
  CHECK(out.size() == 1);
  auto p = readClientPacket(out[0], ev);
  CHECK(p.commands.size() == 2);
  CHECK(p.commands.size() == 2 && p.commands[0].first == idOf("BigDataStartEvent") &&
        p.commands[1].first == idOf("BigDataChunkEvent"));
}

}  // namespace

int main() {
  testHuffmanAndRequest();
  testAcceptsAndFirstPackets();
  testPayloads();
  testServerSession();
  testLostEventIsResent();
  testTimeouts();
  testProtocols();
  testServerText();
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("graal3dengine link: all checks passed\n");
  return 0;
}
