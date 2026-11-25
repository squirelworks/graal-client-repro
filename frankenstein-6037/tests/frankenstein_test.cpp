// The Frankenstein 6.037 over loopback: the 6.03r7 login to a Login
// server, its 178 warp to a `3 ` server, then the two links at once: the
// TCP login on the listed port with the 6.03r7 token, and the 5.12 Graal3D
// link on port + 1 over UDP, driven through the recorded protocol-24
// server session (graal3dengine/tests/vectors.hpp) to login step 6. Then
// the 3D view over the frame, and the disconnect when the host goes.
#include "../src/host6037/host.hpp"
#include "../../common/cpp/quattro/tests/fake_server.hpp"
#include "bits.hpp"
#include "udp.hpp"
#include "vectors.hpp"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>

using QuattroTest::FakeServer;
using namespace Quattro;

static int failures = 0;
#define CHECK(cond)                                                                  \
  do {                                                                               \
    if (!(cond)) {                                                                   \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                                    \
    }                                                                                \
  } while (0)

namespace {

void test_marker() {
  bool is3d = false;
  CHECK(Frank::strip_marker("3 Lab", is3d) == "Lab" && is3d);
  CHECK(Frank::strip_marker("2 Classic", is3d) == "Classic" && !is3d);
  CHECK(Frank::strip_marker("Login", is3d) == "Login" && !is3d);
  CHECK(Frank::strip_marker("3", is3d) == "3" && !is3d);
}

void test_view() {
  Torque::Gui::Image img(64, 48);
  graal3d::GhostTable ghosts;
  auto st = Frank::draw_view3d(img, ghosts, -1, {});
  CHECK(st.objects == 0 && !st.control);
  // Sky above, ground below, with nothing in the table.
  CHECK(img.at(32, 2).a == 255 && img.at(32, 45).a == 255);
  CHECK(img.at(32, 2) != img.at(32, 45));
  graal3d::Ghost g;
  g.className = "GameObject";
  g.object.hasTransform = true;
  g.object.position = {0, 0, 0};
  ghosts[3] = g;
  st = Frank::draw_view3d(img, ghosts, 3, {0, 0, 0});
  CHECK(st.objects == 1 && st.control);
  // The control object is drawn in yellow somewhere.
  bool yellow = false;
  for (const auto& p : img.pixels) yellow = yellow || (p.r == 255 && p.g == 220 && p.b == 64);
  CHECK(yellow);
  Torque::Gui::Image inset(64, 48, {1, 2, 3, 255});
  Frank::draw_inset(img, inset, 4);
  CHECK(img.at(8, 48 - 12 - 8) == (Torque::Gui::Color{1, 2, 3, 255}));

  // With a Camera the 5.12 renderer draws: a Sky without textures fills
  // the view above the horizon with its solid colour, and the fog colour
  // below (lab T3D-046).
  Frank::World3D world;
  world.roots.push_back("no-such-levels3d");
  std::map<int, std::string> chunks;
  CHECK(!Frank::draw_world3d(img, ghosts, -1, 3, 0, chunks, 0, world, 0));
  graal3d::Ghost cam;
  cam.className = "Camera";
  cam.camera.object.position = {0, -5, 2};
  ghosts[1] = cam;
  graal3d::Ghost sky;
  sky.className = "Sky";
  sky.sky.init = true;
  sky.sky.solidColor = {0, 0, 1};
  sky.sky.fogColor = {1, 0, 0};
  ghosts[2] = sky;
  Frank::View3DStats ws;
  CHECK(Frank::draw_world3d(img, ghosts, 1, 3, 0, chunks, 0, world, 0, &ws));
  CHECK(img.at(32, 4) == (Torque::Gui::Color{0, 0, 255, 255}));
  CHECK(img.at(32, 44) == (Torque::Gui::Color{255, 0, 0, 255}));
  CHECK(ws.control && ws.objects == 0);  // its shape is not on disk
}

void test_warp_into_3d() {
  // The game server's TCP port and the 3D port just above it.
  graal3d::UdpSocket udp;
  FakeServer login, game;
  bool ports = false;
  for (int tries = 0; tries < 50 && !ports; ++tries) {
    udp.close();
    game.listener.close();
    if (!udp.open(0, true)) continue;
    const uint16_t u = udp.localPort();
    if (u < 2) continue;
    ports = game.listener.listen_loopback(static_cast<uint16_t>(u - 1));
  }
  CHECK(ports);
  CHECK(login.start());
  if (!ports) return;
  const uint16_t gamePort = game.port();
  CHECK(udp.localPort() == gamePort + 1);

  Draw::HeadlessWindow window;
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = login.port();
  opt.account = "lab";
  opt.password = "pw";
  opt.nickname = "Frank";
  opt.width = 320;
  opt.height = 240;
  std::vector<std::string> logs;
  Frank::Host host(opt, window);
  host.log = [&](const std::string& s) { logs.push_back(s); };
  host.connect_sequence = 0x400;  // the recorded session's
  CHECK(host.start());
  CHECK(login.conn.accept_from(login.listener));
  CHECK(!host.mode3d());

  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!login.have_login && std::chrono::steady_clock::now() < deadline) {
    host.tick();
    login.pump();
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  }
  CHECK(login.have_login);
#ifdef _WIN32
  CHECK(login.login_line.rfind("G3D0311C", 0) == 0);
#else
  CHECK(login.login_line.rfind("G3D0511C", 0) == 0);
#endif

  // The Login server sends the player on to a Graal3D server.
  login.send(Net::gchar(178) + "0,3 Lab,127.0.0.1," + std::to_string(gamePort) + "\n");
  std::atomic<bool> accepted{false};
  std::thread acc([&] { accepted = game.conn.accept_from(game.listener); });

  std::string challengeResponse;
  {
    graal3d::BitWriter w;
    w.u8(0x1E);
    w.u32(0x400);
    const uint32_t digest[4] = {0x03020100, 0x07060504, 0x0b0a0908, 0x0f0e0d0c};
    for (auto d : digest) w.u32(d);
    challengeResponse = w.bytes();
  }
  size_t next = 0;
  int challenges = 0, requests = 0, dataPackets = 0;
  deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while ((host.login_step() < 6 || !game.have_login) && std::chrono::steady_clock::now() < deadline) {
    host.tick();
    login.pump();
    if (accepted) game.pump();
    udp.wait(5);
    std::string d, from;
    while (udp.receiveFrom(d, from)) {
      const uint8_t b0 = static_cast<uint8_t>(d[0]);
      if (b0 == 0x1A) {
        ++challenges;
        udp.sendTo(challengeResponse, from);
      } else if (b0 == 0x20) {
        ++requests;
        udp.sendTo(graal3d::fromHex(kAcceptFull), from);
      } else if (b0 & 1) {
        graal3d::BitReader r(d);
        r.bits(20);
        if (r.bits(2) != 0) continue;
        ++dataPackets;
        if (next < 5) udp.sendTo(graal3d::fromHex(kServer[next++]), from);
      }
    }
  }
  acc.join();
  CHECK(accepted);
  CHECK(game.have_login);
#ifdef _WIN32
  CHECK(game.login_line.rfind("G3D0311C", 0) == 0);
#else
  CHECK(game.login_line.rfind("G3D0511C", 0) == 0);
#endif
  CHECK(challenges >= 1 && requests >= 1 && dataPackets >= 4);
  CHECK(host.mode3d());
  CHECK(host.server() == "Lab");
  CHECK(host.login_step() == 6);
  CHECK(host.link3d().link() && host.link3d().link()->ghosts().size() == 2);

  // A frame later the 3D view is over the frame, with the player's object.
  host.tick();
  CHECK(window.frames() > 0);
  CHECK(host.view().last.control);
  CHECK(window.last().width == 320 && window.last().height == 240);
  if (const char* shot = std::getenv("FRANK_SHOT")) {  // a look at the view, by hand
    std::string err;
    Torque::Gui::write_file(shot, Torque::Gui::encode_png(window.last()), err);
  }

  // The host going away sends the 3D disconnect (0x26).
  int disconnects = 0;
  host.close();
  udp.wait(200);
  std::string d, from;
  while (udp.receiveFrom(d, from))
    if (static_cast<uint8_t>(d[0]) == 0x26) ++disconnects;
  CHECK(disconnects == 1);
  if (failures)
    for (const auto& l : logs) std::fprintf(stderr, "  log: %s\n", l.c_str());
}

}  // namespace

int main() {
  test_marker();
  test_view();
  test_warp_into_3d();
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("frankenstein-6037: Login -> 178 to \"3 Lab\" -> TCP 6.03r7 login + UDP login step 6\n");
  return 0;
}
