// The 3D link against the decoded real-client vectors in Graal_analysis
// torque/udp-session.md (§3 handshake, §4 first client packets, §8 ghost
// payloads and the server session). The bytes are copied from that note;
// "[run]" vectors are a real 5.12 client's, "[srv]" ones the Seihai test
// gserver's.
#include "bits.hpp"
#include "link.hpp"
#include "world.hpp"
#include "vectors.hpp"

#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
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
  Vec3 position;
  GameObjectState own;
  uint32_t ownSections = 0;
  bool cameraMode = false, cameraFollow = false;
  std::vector<std::pair<int, std::string>> commands;  // class id, command name
};

// `seen`, when given, is the server's copy of the client's object: it
// keeps the movetype from one packet to the next, which decides whether
// section 7 is there.
ClientPacket readClientPacket(const std::string& bytes, const std::map<int, std::string>& events,
                              GameObjectState* seen = nullptr, bool cameraControl = false) {
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
  p.position.x = r.f32();
  p.position.y = r.f32();
  p.position.z = r.f32();
  if ((p.hasControl = r.flag())) p.controlGhost = static_cast<int>(r.bits(12));
  if ((p.ownState = r.flag())) {
    GameObjectState& o = seen ? *seen : p.own;
    readGameObjectUpdate(r, o, &p.ownSections);
    p.own = o;
    // A Camera control object: two Camera flags follow (lab T3D-023).
    if (cameraControl) {
      p.cameraMode = r.flag();
      p.cameraFollow = r.flag();
    }
  }
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
  Link link(login, {[&](const std::string& s) { logs.push_back(s); }, nullptr, nullptr, nullptr, nullptr});
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
  Link refused(old, {nullptr, nullptr, [&](const std::string& e) { error = e; }, nullptr, nullptr});
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
    // fxSunLight (fxsunlight-512.md): flag, name, transform, enable, two
    // bitmaps, azimuth, elevation, flare TP, RGBA, four 32-bit values.
    BitWriter w;
    w.flag(true);
    w.pstring("flare");
    for (float f : {1.0f, 2.0f, 3.0f, 0.0f, 0.0f, 0.0f}) w.f32(f);
    w.flag(false);
    w.u8(1);
    w.pstring("flare.png");
    w.pstring("");
    w.f32(90);
    w.f32(30);
    w.u8(0);
    for (uint32_t c : {255u, 200u, 0u, 128u}) w.u8(c);
    w.f32(1);
    w.f32(300);
    w.f32(0);
    w.u32(2);
    BitReader r(w.bytes());
    SunFlareState f;
    CHECK(readSunFlareUpdate(r, f) && f.init && f.name == "flare" && f.enable);
    CHECK(f.localBitmap == "flare.png" && near(f.azimuth, 90) && near(f.elevation, 30));
    CHECK(f.color[0] == 255 && f.color[1] == 200 && f.color[3] == 128 && near(f.flareSize, 300) && f.blendMode == 2);
    CHECK(near(f.position.y, 2) && near(f.rotation[3], 1));
    BitReader none(fromHex("00"));
    SunFlareState g;
    CHECK(readSunFlareUpdate(none, g) && !g.init);
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
                    nullptr, nullptr});
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

// Runs the recorded session of testServerSession up to the server's
// seq 5: the link has control object 1, has sent 5 data packets and has
// received 5.
void runSession(Link& link, uint32_t& t) {
  link.start(t);
  link.receive(challengeResponse(), ++t);
  link.receive(fromHex(kAcceptFull), ++t);
  for (int i = 0; i < 4; ++i) link.receive(fromHex(kServer[i]), ++t);
  t += Link::kKeepAliveMs;
  link.tick(t);
  link.receive(fromHex(kServer[4]), ++t);
  link.takeOutgoing();
}

// A server data packet whose game section updates control object 1 with
// `sections` of `o`, and nothing else.
std::string serverControlUpdate(uint32_t seq, uint32_t ack, const GameObjectState& o, uint32_t sections) {
  BitWriter w;
  w.flag(true);
  w.bits(0, 1);
  w.bits(seq & 0x1FF, 9);
  w.bits(ack & 0x1FF, 9);
  w.bits(0, 2);
  w.bits(1, 3);
  w.bits(0x01, 8);
  w.flag(false);  // current rate
  w.flag(false);  // max rate
  w.flag(true);   // control object
  w.flag(true);
  w.u32(1000 + seq);
  w.bits(1, 12);
  writeGameObjectUpdate(w, o, sections);
  w.flag(false);  // camera
  w.flag(false);  // fov
  w.flag(false);  // unguaranteed
  w.flag(false);  // guaranteed
  w.flag(false);  // ghosts
  return w.bytes();
}

constexpr uint32_t kSec(int n) { return 1u << (n - 1); }

void testOwnMove() {
  // A host moving the client's own object (moveControlTo): the next data
  // packet carries the new position and the transform section.
  LinkLogin login;
  Link link(login, {});
  uint32_t t = 0;
  runSession(link, t);
  link.takeOutgoing();
  GameObjectState seen;
  link.moveControlTo({5, 6, 7});
  link.tick(++t);
  auto out = link.takeOutgoing();
  CHECK(out.size() == 1);
  if (out.size() == 1) {
    auto p = readClientPacket(out[0], link.eventClasses(), &seen);
    CHECK(p.type == 0 && p.ownState);
    CHECK(near(p.position.x, 5) && near(p.position.y, 6) && near(p.position.z, 7));
    CHECK((p.ownSections & kSec(5)) != 0);
  }
  CHECK(near(link.controlPosition().x, 5) && near(link.controlPosition().z, 7));
  // Sent once: the next keep-alive has no transform.
  t += Link::kKeepAliveMs;
  link.tick(t);
  out = link.takeOutgoing();
  CHECK(out.size() == 1);
  if (out.size() == 1) CHECK((readClientPacket(out[0], link.eventClasses(), &seen).ownSections & kSec(5)) == 0);
}

void testServerMoveReported() {
  // A server move with no movetype (seihai-gserver g3dpos, conformance
  // C011): the control object's transform changes, and the client reports
  // the new place with its transform section in the next packet, as the
  // real 5.12 did; once only.
  LinkLogin login;
  Link link(login, {});
  uint32_t t = 0;
  runSession(link, t);
  link.takeOutgoing();
  GameObjectState seen;
  GameObjectState o;
  o.position = {3, 0, 1};
  o.hasTransform = true;
  uint32_t seq = 6;
  link.receive(serverControlUpdate(seq++, link.sentDataPackets(), o, kSec(5)), ++t);
  link.tick(++t);
  bool reported = false;
  for (const auto& d : link.takeOutgoing()) {
    auto p = readClientPacket(d, link.eventClasses(), &seen);
    if (p.type != 0) continue;
    reported = near(p.position.x, 3) && near(p.position.z, 1) && (p.ownSections & kSec(5)) != 0;
  }
  CHECK(reported);
  t += Link::kKeepAliveMs;
  link.tick(t);
  for (const auto& d : link.takeOutgoing()) {
    auto p = readClientPacket(d, link.eventClasses(), &seen);
    if (p.type == 0) CHECK((p.ownSections & kSec(5)) == 0);
  }
}

void testMovetypes() {
  // E#505 (protocol/lab-appe-hosta-2026-11-20d.md): a server moves the
  // player with a movetype and movement data on its control object.
  const uint32_t announce = kSec(3) | kSec(5) | kSec(6) | kSec(13);

  // interpolate: the client glides to each target, makes its shape,
  // transform, movetype and flags known once, and echoes its movement
  // data in every update.
  {
    LinkLogin login;
    Link link(login, {});
    uint32_t t = 0;
    runSession(link, t);
    GameObjectState seen;
    GameObjectState o;
    o.movetype = "interpolate";
    o.hasMovement = true;
    o.hasMovementData = true;
    o.movement.position = {0, 10, 1};
    uint32_t seq = 6;
    link.receive(serverControlUpdate(seq++, link.sentDataPackets(), o, kSec(6) | kSec(7)), ++t);
    CHECK(link.controlMovetype() == "interpolate");
    auto out = link.takeOutgoing();
    CHECK(out.size() == 1);
    auto p = readClientPacket(out[0], link.eventClasses(), &seen);
    CHECK(p.type == 0 && p.ownState);
    CHECK(p.ownSections == (announce | kSec(7)));
    CHECK(seen.movetype == "interpolate" && seen.shape == "labcube.3ds" && seen.flags == 0x48);

    // Targets 0.5 units apart each second: halfway through a glide the
    // client is 0.25 behind.
    t += 1000;
    o.movement.position = {0, 10.5f, 1};
    link.receive(serverControlUpdate(seq++, link.sentDataPackets(), o, kSec(7)), t);
    t += 1000;
    o.movement.position = {0, 11, 1};
    link.receive(serverControlUpdate(seq++, link.sentDataPackets(), o, kSec(7)), t);
    link.takeOutgoing();
    link.tick(t + 500);
    CHECK(near(link.controlPosition().y, 10.75f));
    link.takeOutgoing();  // perhaps a keep-alive mid-glide
    t += 1600;
    link.tick(t);
    out = link.takeOutgoing();
    CHECK(out.size() == 1);
    p = readClientPacket(out[0], link.eventClasses(), &seen);
    CHECK(near(p.position.y, 11) && near(p.position.z, 1));
    CHECK(p.ownSections == kSec(7));
    CHECK(seen.hasMovementData && near(seen.movement.position.y, 11));
    CHECK(seen.movement.rotation[0] == 127 && seen.movement.rotation[3] == 255);

    // The server's packets each 400 ms are answered with acks, and the
    // client still sends its data packet (position and movement data)
    // each second (the first lab run of the rebuild stopped here).
    int data = 0;
    for (int i = 0; i < 10; ++i) {
      t += 400;
      o.movement.position.y += 0.2f;
      link.receive(serverControlUpdate(seq++, link.sentDataPackets(), o, kSec(7)), t);
      link.tick(t);
      for (const auto& d : link.takeOutgoing()) {
        auto q = readClientPacket(d, link.eventClasses(), &seen);
        if (q.type != 0) continue;
        ++data;
        CHECK(q.ownSections == kSec(7));
      }
    }
    CHECK(data >= 3);
  }

  // list: the client jumps onto each position and echoes its transform.
  {
    LinkLogin login;
    Link link(login, {});
    uint32_t t = 0;
    runSession(link, t);
    GameObjectState seen;
    GameObjectState o;
    o.movetype = "list";
    o.hasMovement = true;
    o.hasMovementData = true;
    o.movement.position = {3, 25, 5};
    link.receive(serverControlUpdate(6, link.sentDataPackets(), o, kSec(6) | kSec(7)), ++t);
    CHECK(link.controlMovetype() == "list");
    CHECK(near(link.controlPosition().y, 25) && near(link.controlPosition().x, 3));
    auto out = link.takeOutgoing();
    CHECK(out.size() == 1);
    auto p = readClientPacket(out[0], link.eventClasses(), &seen);
    CHECK(p.ownSections == announce);
    CHECK(near(seen.position.y, 25) && near(seen.position.z, 5));
    t += Link::kKeepAliveMs;
    link.tick(t);
    out = link.takeOutgoing();
    CHECK(out.size() == 1);
    p = readClientPacket(out[0], link.eventClasses(), &seen);
    CHECK(p.ownSections == kSec(5));
    CHECK(near(p.position.y, 25));
  }

  // rigid: the client follows with the same glide but echoes no section.
  {
    LinkLogin login;
    Link link(login, {});
    uint32_t t = 0;
    runSession(link, t);
    GameObjectState seen;
    GameObjectState o;
    o.movetype = "rigid";
    o.hasMovement = true;
    o.hasMovementData = true;
    o.movement.position = {0, 0, 1};
    link.receive(serverControlUpdate(6, link.sentDataPackets(), o, kSec(6) | kSec(7)), ++t);
    CHECK(link.controlMovetype() == "rigid");
    auto out = link.takeOutgoing();
    CHECK(out.size() == 1 && out[0].size() == 5);  // only an ack
    t += 1000;
    o.movement.position = {0, 4, 1};
    link.receive(serverControlUpdate(7, link.sentDataPackets(), o, kSec(7)), t);
    link.takeOutgoing();
    link.tick(t + 1000);
    out = link.takeOutgoing();
    CHECK(out.size() == 1);
    auto p = readClientPacket(out[0], link.eventClasses(), &seen);
    CHECK(p.ownState && p.ownSections == 0);
    CHECK(near(p.position.y, 4));
  }

  // The movement data round-trips through the writer and reader.
  {
    GameObjectState a;
    a.movetype = "list";
    a.hasMovement = true;
    a.hasMovementData = true;
    std::array<uint32_t, 8> e{};
    float f = 7.5f;
    std::memcpy(&e[1], &f, 4);
    e[7] = 0xDEADBEEF;
    a.movement.list = {e, e};
    BitWriter w;
    writeGameObjectUpdate(w, a, kSec(6) | kSec(7));
    BitReader r(w.bytes());
    GameObjectState b;
    uint32_t got = 0;
    CHECK(readGameObjectUpdate(r, b, &got));
    CHECK(got == (kSec(6) | kSec(7)));
    CHECK(b.movement.list.size() == 2 && b.movement.list[1][7] == 0xDEADBEEF);
    CHECK(near(b.movement.position.y, 7.5f));
    CHECK(b.movementSerial == 1);
  }
}

// SharpServer's world (the Sharp3D capture, 2026-11-24): every object is a
// GhostAlwaysObjectEvent, no mission commands, and the control object is
// the Camera. The class ids are kAcceptFull's: object 0 Camera,
// 4 GameObject; event 3 GhostAlwaysObjectEvent.
BitWriter ghostAlwaysEvent(int ghost, int classId, const BitWriter& payload) {
  BitWriter ev;
  ev.bits(static_cast<uint32_t>(ghost), 12);
  ev.flag(true);
  ev.bits(static_cast<uint32_t>(classId), 12);
  ev.bits(static_cast<uint32_t>(payload.pos()), 14);
  ev.append(payload);
  return ev;
}

// Streamed terrain and water (Graal_analysis torque/terrain-512.md): a
// TerrainBlock and a WaterBlock as guaranteed ghosts, a chunk before and
// after the block, and the client's one TerrainRequestUpdatesEvent.
void testTerrainAndWater() {
  LinkLogin login;
  Link link(login, {nullptr, nullptr, nullptr, nullptr, nullptr});
  uint32_t t = 0;
  link.start(t);
  link.receive(challengeResponse(), ++t);
  link.receive(fromHex(kAcceptFull), ++t);
  link.takeOutgoing();
  auto id = [](const std::map<int, std::string>& m, const std::string& name) {
    for (const auto& [i, n] : m)
      if (n == name) return i;
    return -1;
  };
  const int terrainClass = id(link.objectClasses(), "TerrainBlock");
  const int waterClass = id(link.objectClasses(), "WaterBlock");
  const int chunkEvent = id(link.eventClasses(), "TerrainChunkEvent");
  const int requestEvent = id(link.eventClasses(), "TerrainRequestUpdatesEvent");
  const int ghostAlways = id(link.eventClasses(), "GhostAlwaysObjectEvent");
  CHECK(terrainClass >= 0 && waterClass >= 0 && chunkEvent >= 0 && requestEvent >= 0 && ghostAlways >= 0);

  BitWriter terrain;  // section 1, as a server writes it
  terrain.flag(true);
  terrain.pstring("Terrain");
  terrain.u32(0);
  terrain.pstring("");
  terrain.pstring("");
  terrain.f32(1.0f);
  terrain.f32(0.01f);
  terrain.u32(8);
  terrain.u32(8);  // square size
  terrain.u8(1);   // repeat
  BitWriter water;  // section 5
  water.flag(true);
  water.pstring("Lake");
  for (float f : {10.0f, 20.0f, 3.0f}) water.f32(f);
  for (float f : {0.0f, 0.0f, 0.0f}) water.f32(f);
  water.flag(false);
  for (float f : {2048.0f, 1024.0f, 5.0f}) water.f32(f);
  for (const char* tx : {"water", "spec", "envover", "envunder", "shore"}) water.pstring(tx);
  water.pstring("sub1");
  water.pstring("sub2");
  water.u32(1);
  for (float f : {1.0f, 0.5f, 0.2f, 0.75f, 0.3f}) water.f32(f);
  water.u8(1);
  water.u8(0);
  for (int i = 0; i < 12; ++i) water.f32(float(i));
  for (int i = 0; i < 4; ++i) water.u8(255);
  water.f32(8.0f);
  water.u8(1);
  auto chunk = [](int x, int y, const std::string& data) {
    BitWriter c;
    c.bits(uint32_t(x), 4);
    c.bits(uint32_t(y), 4);
    c.u32(0xDEADBEEF);
    c.bits(uint32_t(data.size()), 10);
    for (char ch : data) c.u8(uint8_t(ch));
    return c;
  };
  const std::vector<std::pair<int, BitWriter>> events = {
      {chunkEvent, chunk(1, 1, "early")},  // before the block: not kept
      {ghostAlways, ghostAlwaysEvent(1, terrainClass, terrain)},
      {ghostAlways, ghostAlwaysEvent(2, waterClass, water)},
      {chunkEvent, chunk(3, 4, "zlib bytes")},
      {chunkEvent, chunk(5, 5, "")},  // empty: ignored
  };
  BitWriter w;
  w.flag(true);
  w.bits(0, 1);
  w.bits(1, 9);
  w.bits(0, 9);
  w.bits(0, 2);
  w.bits(0, 3);
  for (int i = 0; i < 5; ++i) w.flag(false);  // rates, control, camera, fov
  w.flag(false);                              // unguaranteed
  for (size_t i = 0; i < events.size(); ++i) {
    w.flag(true);
    if (!w.flag(i > 0)) w.bits(0, 7);
    w.bits(uint32_t(events[i].first), 12);
    w.bits(static_cast<uint32_t>(events[i].second.pos()), 14);
    w.append(events[i].second);
  }
  w.flag(false);
  w.flag(false);
  link.receive(w.bytes(), ++t);
  CHECK(link.ghosts().count(1) && link.ghosts().at(1).className == "TerrainBlock");
  if (link.ghosts().count(1)) {
    const TerrainBlockState& tb = link.ghosts().at(1).terrain;
    CHECK(tb.init && tb.name == "Terrain" && tb.squareSize == 8 && tb.repeat);
  }
  CHECK(link.ghosts().count(2) && link.ghosts().at(2).className == "WaterBlock");
  if (link.ghosts().count(2)) {
    const WaterBlockState& wb = link.ghosts().at(2).water;
    CHECK(wb.name == "Lake" && near(wb.position.y, 20) && near(wb.scale.x, 2048) && near(wb.rotation[3], 1));
    CHECK(wb.textures[0] == "water" && wb.textures[4] == "shore" && wb.submergeTextures[1] == "sub2");
    CHECK(wb.liquidType == 1 && near(wb.opacity, 0.75f) && wb.removeWetEdges && !wb.useDepthMask);
    CHECK(near(wb.shading[11], 11) && near(wb.specularColor[2], 1) && near(wb.specularPower, 8) && wb.ignoreTerrain);
  }
  CHECK(link.terrainChunks().size() == 1 && link.terrainChunks().count(4 * 16 + 3) &&
        link.terrainChunks().at(4 * 16 + 3) == "zlib bytes");
  CHECK(link.terrainChunkCount() == 1);
  // The client answers with one request carrying 256 stamps, once.
  auto out = link.takeOutgoing();
  int requests = 0;
  for (const auto& o : out)
    for (const auto& [cls, name] : readClientPacket(o, link.eventClasses()).commands) requests += cls == requestEvent;
  CHECK(requests == 1);
  CHECK(link.state() == Link::State::Connected);
}

void testGhostAlwaysAndCameraControl() {
  std::vector<int> steps;
  LinkLogin login;
  Link link(login, {nullptr, [&](int s) { steps.push_back(s); }, nullptr, nullptr, nullptr});
  uint32_t t = 0;
  link.start(t);
  link.receive(challengeResponse(), ++t);
  link.receive(fromHex(kAcceptFull), ++t);
  link.takeOutgoing();

  GameObjectState cam;
  cam.name = "TestCamera";
  cam.position = {-3, 4, 2.8f};
  cam.axis = {0, 0, 1};
  cam.angle = 2.44f;
  BitWriter camPayload;
  writeGameObjectUpdate(camPayload, cam, kSec(1) | kSec(5));
  camPayload.flag(false);  // mode
  camPayload.flag(false);  // follow
  GameObjectState forest;
  forest.name = "KokiriForest";
  forest.shape = "forest.3ds";
  BitWriter forestPayload;
  writeGameObjectUpdate(forestPayload, forest, kSec(1) | kSec(3) | kSec(5));

  // seq 1: both objects as guaranteed events 0 and 1.
  BitWriter w;
  w.flag(true);
  w.bits(0, 1);
  w.bits(1, 9);
  w.bits(0, 9);
  w.bits(0, 2);
  w.bits(0, 3);
  w.flag(false);  // rates
  w.flag(false);
  w.flag(false);  // control object
  w.flag(false);  // camera
  w.flag(false);  // fov
  w.flag(false);  // unguaranteed
  const BitWriter events[2] = {ghostAlwaysEvent(2, 0, camPayload), ghostAlwaysEvent(1, 4, forestPayload)};
  for (int i = 0; i < 2; ++i) {
    w.flag(true);
    if (!w.flag(i > 0)) w.bits(0, 7);
    w.bits(3, 12);
    w.bits(static_cast<uint32_t>(events[i].pos()), 14);
    w.append(events[i]);
  }
  w.flag(false);  // end of guaranteed
  w.flag(false);  // ghosts
  link.receive(w.bytes(), ++t);
  CHECK(link.ghosts().size() == 2);
  CHECK(link.ghosts().count(2) && link.ghosts().at(2).className == "Camera");
  CHECK(link.ghosts().count(2) && link.ghosts().at(2).camera.object.name == "TestCamera");
  CHECK(link.ghosts().count(2) && near(link.ghosts().at(2).camera.object.angle, 2.44f));
  CHECK(link.ghosts().count(1) && link.ghosts().at(1).object.shape == "forest.3ds");
  link.takeOutgoing();

  // seq 2: the Camera as the control object (an empty Camera update),
  // then the camera ghost and a field of view of 60, as SharpServer sends
  // every packet. The packet must read to its end.
  BitWriter c;
  c.flag(true);
  c.bits(0, 1);
  c.bits(2, 9);
  c.bits(1, 9);
  c.bits(0, 2);
  c.bits(0, 3);
  c.flag(false);
  c.flag(false);
  c.flag(true);  // control object
  c.flag(true);
  c.u32(5000);
  c.bits(2, 12);
  writeGameObjectUpdate(c, GameObjectState(), 0);
  c.flag(false);  // mode
  c.flag(false);  // follow
  c.flag(true);   // camera
  c.bits(2, 12);
  c.flag(false);  // no camera update
  c.flag(true);   // fov
  c.bits(60, 8);
  c.flag(false);  // unguaranteed
  c.flag(false);  // guaranteed
  c.flag(false);  // ghosts
  link.receive(c.bytes(), ++t);
  CHECK(link.controlGhost() == 2);
  CHECK(link.cameraGhost() == 2);
  CHECK(link.fieldOfView() == 60);
  CHECK(link.serverTime() == 5000);
  CHECK(near(link.controlPosition().x, -3) && near(link.controlPosition().z, 2.8f));
  CHECK(link.state() == Link::State::Connected);
  // No mission phases came, so the login steps do not move.
  CHECK(steps.empty());
  // The client's next data packet names the Camera and writes it back as
  // the real 5.12 does (lab T3D-023): GameObject sections, the first time
  // its transform and flags 0, then two Camera flags; later ones an empty
  // update and the two flags.
  t += Link::kKeepAliveMs;
  link.tick(t);
  auto out = link.takeOutgoing();
  CHECK(!out.empty());
  if (!out.empty()) {
    const auto p = readClientPacket(out.front(), link.eventClasses(), nullptr, true);
    CHECK(p.hasControl && p.controlGhost == 2 && p.ownState);
    CHECK(p.ownSections == ((1u << 4) | (1u << 12)));
    CHECK(p.own.flags == 0 && p.own.shape.empty());
    CHECK(!p.cameraMode && !p.cameraFollow);
  }
  t += Link::kKeepAliveMs;
  link.tick(t);
  out = link.takeOutgoing();
  CHECK(!out.empty());
  if (!out.empty()) {
    const auto p = readClientPacket(out.back(), link.eventClasses(), nullptr, true);
    CHECK(p.ownState && p.ownSections == 0);
  }
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
  Link link(login, {nullptr, nullptr, [&](const std::string& e) { error = e; }, nullptr, nullptr});
  link.start(0);
  link.tick(Link::kResendMs);
  auto out = link.takeOutgoing();
  CHECK(out.size() == 2 && out[1] == out[0]);  // the challenge again
  link.tick(Link::kConnectTimeoutMs + 1);
  CHECK(link.state() == Link::State::Closed);
  CHECK(error == "The connection to the Graal3D server couldn't be established.");

  error.clear();
  Link quiet(login, {nullptr, nullptr, [&](const std::string& e) { error = e; }, nullptr, nullptr});
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
  Link link(login, {nullptr, nullptr, nullptr, [&](const BigText& t) { got.push_back(t); }, nullptr});
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

// A server data packet with RemoteCommandEvents as guaranteed events from
// event seq `first`, each a list of plain-string arguments.
std::string serverCommands(const Link& link, uint32_t seq, int first,
                           const std::vector<std::vector<std::string>>& commands) {
  int cmd = -1;
  for (const auto& [id, name] : link.eventClasses())
    if (name == "RemoteCommandEvent") cmd = id;
  BitWriter w;
  w.flag(true);
  w.bits(0, 1);
  w.bits(seq & 0x1FF, 9);
  w.bits(1, 9);
  w.bits(0, 2);
  w.bits(1, 3);
  w.bits(1, 8);
  for (int i = 0; i < 6; ++i) w.flag(false);  // rates, game section, unguaranteed
  for (size_t i = 0; i < commands.size(); ++i) {
    BitWriter e;
    e.bits(static_cast<uint32_t>(commands[i].size()), 5);
    for (const auto& a : commands[i]) {
      e.bits(1, 2);
      e.pstring(a);
    }
    w.flag(true);
    if (i == 0) {
      w.flag(false);
      w.bits(static_cast<uint32_t>(first), 7);
    } else {
      w.flag(true);
    }
    w.bits(static_cast<uint32_t>(cmd), 12);
    w.bits(static_cast<uint32_t>(e.pos()), 14);
    w.append(e);
  }
  w.flag(false);  // end of guaranteed
  w.flag(false);  // ghosts
  return w.bytes();
}

void testSeihai3d() {
  // seihai3d v1 (Graal_analysis torque/seihai3d-ext-v1.md): the hello as a
  // third connect argument, the reply before MissionStartPhase1, the
  // agreed bits, chat_3d and frame_stats.
  std::vector<std::pair<std::string, std::string>> chats;
  auto connect = [&](bool hello) {
    LinkLogin login;
    login.account = "guest";
    login.seihai3dHello = hello;
    login.seihai3dCaps = seihai3d::kFrameStats | seihai3d::kChat3d;
    Link::Callbacks cb;
    cb.chat3d = [&](const std::string& a, const std::string& t) { chats.emplace_back(a, t); };
    auto link = std::make_unique<Link>(login, cb);
    link->start(0);
    link->takeOutgoing();
    link->receive(challengeResponse(), 1);
    auto out = link->takeOutgoing();
    CHECK(out.size() == 1);
    if (out.size() == 1) {
      BitReader r(out[0]);
      r.u8();
      for (int i = 0; i < 5; ++i) r.u32();
      r.string();
      r.u32();
      r.u32();
      r.string();
      r.u32();
      r.u32();
      r.string();
      const uint32_t argc = r.u32();
      CHECK(argc == (hello ? 3u : 2u));
      r.string();
      r.string();
      if (hello) CHECK(r.string() == "seihai3d/1/00000003");
      CHECK(r.left() < 8);  // padding to the byte
    }
    link->receive(fromHex(kAcceptFull), 2);
    link->takeOutgoing();
    return link;
  };
  CHECK(seihai3d::helloArg(1, 3) == "seihai3d/1/00000003");

  // A server with the extension: the reply (offering more than asked),
  // a chat line, then the mission start.
  {
    auto link = connect(true);
    link->receive(serverCommands(*link, 1, 0,
                                 {{"seihai3d", "1", "000000ff"}, {"seihai3dChat", "bob", "hi", "there"},
                                  {"MissionStartPhase1"}}),
                  3);
    CHECK(link->extVersion() == 1 && link->extCaps() == 3);
    CHECK(link->extHas(seihai3d::kChat3d) && link->extHas(seihai3d::kFrameStats));
    CHECK(chats.size() == 1 && chats[0].first == "bob" && chats[0].second == "hi there");
    CHECK(link->loginStep() == 2);
    link->takeOutgoing();
    link->sendFrameStats(59.9, 4.5, 12, 3.25);
    link->tick(4);
    int commands = 0;
    for (const auto& d : link->takeOutgoing()) {
      auto p = readClientPacket(d, link->eventClasses());
      for (const auto& c : p.commands)
        if (link->eventClasses().at(c.first) == "RemoteCommandEvent") ++commands;
    }
    CHECK(commands >= 1);
  }
  // A server without it: no reply before Phase 1, a plain 5.12; a late
  // reply is ignored, and so is chat.
  {
    chats.clear();
    auto link = connect(true);
    link->receive(serverCommands(*link, 1, 0,
                                 {{"MissionStartPhase1"}, {"seihai3d", "1", "00000003"},
                                  {"seihai3dChat", "bob", "hi"}}),
                  3);
    CHECK(link->extVersion() == 0 && link->extCaps() == 0 && chats.empty());
    CHECK(link->loginStep() == 2);
  }
  // No hello: a reply is not ours.
  {
    auto link = connect(false);
    link->receive(serverCommands(*link, 1, 0, {{"seihai3d", "1", "00000003"}}), 3);
    CHECK(link->extVersion() == 0);
  }
}

}  // namespace

int main() {
  testHuffmanAndRequest();
  testAcceptsAndFirstPackets();
  testPayloads();
  testServerSession();
  testMovetypes();
  testOwnMove();
  testServerMoveReported();
  testSeihai3d();
  testGhostAlwaysAndCameraControl();
  testTerrainAndWater();
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
