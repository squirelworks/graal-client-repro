// Both libraries as a launcher loads them: the engine library and the 3D
// library, linked as shared libraries, against a loopback UDP server that
// answers the handshake and replays the recorded protocol-24 server
// session of torque/udp-session.md §8 (mission phases, the Sun and the
// player's GameObject, the control object). The 3D link must reach login
// step 6 through the engine's exports.
#include "bits.hpp"
#include "graal3dengine.h"
#include "graalengine.h"
#include "udp.hpp"
#include "vectors.hpp"

#include <chrono>
#include <cstdio>
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

static std::vector<std::string> logs;
static void GE_CALL recLog(const char* line) { logs.push_back(line ? line : ""); }

static bool logged(const std::string& line) {
  for (const auto& l : logs)
    if (l == line) return true;
  return false;
}

int main() {
  UdpSocket server;
  if (!server.open(0, true)) {
    std::fprintf(stderr, "cannot open a loopback UDP socket\n");
    return 1;
  }
  const int udpPort = server.localPort();

  graal_setLogGraalMessage(recLog);
  CHECK(graalengine_setBuild("5.12") == 1);
  CHECK(graal_engineInitialize("/nowhere/Graal.exe") == 1);
  loadGraalGui();
  CHECK(graal3dengine_abi() == GRAAL3DENGINE_ABI);
  CHECK(loadGraal3DEngine("") == 1);
  CHECK(logged("Graal3D activated"));
  // The recorded session was made with connect sequence 0x400.
  graal3dengine_setConnectSequence(0x400);

  // The TCP side dials udpPort - 1 on loopback; nothing listens there, so
  // only the UDP link is under test.
  connectToGraalServer("3 Lab", "127.0.0.1", udpPort - 1);
  CHECK(isGraal3DMode() == 1);

  std::string challengeResponse;
  {
    BitWriter w;
    w.u8(0x1E);
    w.u32(0x400);
    const uint32_t digest[4] = {0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c};
    for (auto d : digest) w.u32(d);
    challengeResponse = w.bytes();
  }
  const char* const* session = kServer;
  size_t next = 0;
  int challenges = 0, requests = 0, dataPackets = 0, disconnects = 0;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (graal3dengine_loginStep() < 6 && std::chrono::steady_clock::now() < deadline) {
    runGraal3DEngine();
    renderGraalCanvas();
    server.wait(5);
    std::string d, from;
    while (server.receiveFrom(d, from)) {
      const uint8_t b0 = static_cast<uint8_t>(d[0]);
      if (b0 == 0x1A) {
        ++challenges;
        server.sendTo(challengeResponse, from);
      } else if (b0 == 0x20) {
        ++requests;
        server.sendTo(fromHex(kAcceptFull), from);
      } else if (b0 & 1) {
        BitReader r(d);
        r.bits(20);  // data bit, sequence bit, sequence, highest ack
        if (r.bits(2) != 0) continue;  // an ack
        ++dataPackets;
        if (next < 5) server.sendTo(fromHex(session[next++]), from);
      }
    }
  }
  CHECK(challenges >= 1);
  CHECK(requests >= 1);
  CHECK(dataPackets >= 4);
  CHECK(graal3dengine_state() == 3);
  CHECK(graal3dengine_loginStep() == 6);
  CHECK(graal3dengine_ghostCount() == 2);
  CHECK(logged("Connection established"));
  CHECK(logged("Phase 1: Download Ghost Objects"));
  CHECK(logged("Mission lighting done"));
  CHECK(logged("Initial Control Object"));
  CHECK(isGraal3DMode() == 1);

  // Ending the library sends the disconnect (0x26).
  endGraal3DEngine();
  server.wait(200);
  std::string d, from;
  while (server.receiveFrom(d, from))
    if (static_cast<uint8_t>(d[0]) == 0x26) ++disconnects;
  CHECK(disconnects == 1);

  prepareGraalShutdown();
  shutdownGraalEngine();
  if (failures) {
    for (const auto& l : logs) std::fprintf(stderr, "  log: %s\n", l.c_str());
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("graal3dengine bridge: login step 6 over loopback UDP\n");
  return 0;
}
