// The Frankenstein 6.037 over loopback: the 6.03r7 login to a Login
// server, its 178 warp to a `3 ` server, then the two links at once: the
// TCP login on the listed port with the 6.03r7 token, and the 5.12 Graal3D
// link on port + 1 over UDP, driven through the recorded protocol-24
// server session (graal3dengine/tests/vectors.hpp) to login step 6. Then
// the 3D view over the frame, and the disconnect when the host goes.
#include "../src/bench.hpp"
#include "../src/host6037/host.hpp"
#include "../src/graal3d5120/gs2_3d.hpp"
#include "../../common/cpp/gs2/engine_commands.hpp"
#include "../../common/cpp/quattro/tests/fake_server.hpp"
#include "bits.hpp"
#include "udp.hpp"
#include "vectors.hpp"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>
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
  Torque::Gui::Image img(64, 48, {9, 9, 9, 255});
  graal3d::GhostTable ghosts;
  // No Camera named: black, as the 5.12 (no stand-in).
  {
    Frank::World3D none;
    none.roots.push_back("no-such-levels3d");
    std::map<int, std::string> noChunks;
    Frank::View3DStats st;
    CHECK(!Frank::draw_world3d(img, ghosts, -1, -1, 0, noChunks, 0, none, 0, &st));
    CHECK(img.at(32, 2) == (Torque::Gui::Color{0, 0, 0, 255}) && st.objects == 0);
  }
  // The draw distance from a game_config.txt.
  CHECK(Frank::visible_distance_from_config("foo=1\nVisibleDistance3D = 1800\r\nfogdistance3D=10\n") == 1800);
  CHECK(Frank::visible_distance_from_config("visibledistance3D=\n") == 0);
  CHECK(Frank::load_visible_distance({"no-such-config.txt"}) == 1000);
  graal3d::Ghost g;
  g.className = "GameObject";
  g.object.hasTransform = true;
  g.object.position = {0, 0, 0};
  ghosts[3] = g;
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

// The OpenGL backend against the software rasteriser on the conformance
// worlds (bench.hpp): the same pixels within the rasterisers' edge rules,
// and the conformance checks' colours in the same shares. Skipped when no
// OpenGL 3.2 core context can be made, unless FRANK_REQUIRE_GL is set (CI
// on Linux, macOS and Windows).
void test_renderers() {
  Frank::RendererChoice c;
  CHECK(Frank::parse_renderer("auto", c) && c == Frank::RendererChoice::Auto);
  CHECK(Frank::parse_renderer("opengl", c) && c == Frank::RendererChoice::OpenGL);
  CHECK(Frank::parse_renderer("gl", c) && c == Frank::RendererChoice::OpenGL);
  CHECK(Frank::parse_renderer("software", c) && c == Frank::RendererChoice::Software);
  CHECK(!Frank::parse_renderer("metal", c));

  Frank::FrameCounter counter;
  for (int i = 0; i <= 30; ++i) counter.add(100.0 + i / 30.0, 4.0);
  CHECK(std::fabs(counter.fps() - 30.0) < 0.5 && std::fabs(counter.mean_ms() - 4.0) < 1e-9);
  CHECK(counter.frames() == 31 && counter.summary().find("31 3D frames") == 0);

  std::string why;
  std::unique_ptr<Frank::SceneRenderer> gl = Frank::make_gl_renderer(why);
  const bool require = std::getenv("FRANK_REQUIRE_GL") != nullptr;
  if (!gl) {
    std::printf("renderers: OpenGL skipped (%s)\n", why.c_str());
    CHECK(!require);
    std::string note;
    auto fallback = Frank::make_renderer(Frank::RendererChoice::Auto, note);
    CHECK(fallback && std::string(fallback->name()) == "software");
    CHECK(!Frank::make_renderer(Frank::RendererChoice::OpenGL, note));
    return;
  }
  std::printf("renderers: %s\n", gl->description().c_str());
  namespace fs = std::filesystem;
  std::error_code ec;
  const fs::path dir = fs::temp_directory_path(ec) / "frankenstein-test-content";
  CHECK(Frank::write_bench_content(dir.string(), why));
  Frank::World3D glw, sww;
  glw.roots = sww.roots = {dir.string()};
  glw.renderer = std::move(gl);
  sww.renderer = Frank::make_software_renderer();
  std::map<std::string, Torque::Gui::Image> frames;
  for (const std::string& name : Frank::bench_world_names()) {
    Frank::BenchWorld w;
    CHECK(Frank::make_bench_world(name, w));
    Torque::Gui::Image a(320, 240), b(320, 240);
    Frank::View3DStats sa, sb;
    CHECK(Frank::draw_world3d(a, w.ghosts, w.camera, w.control, 0, w.chunks, w.chunkCount, glw, 0, &sa));
    CHECK(Frank::draw_world3d(b, w.ghosts, w.camera, w.control, 0, w.chunks, w.chunkCount, sww, 0, &sb));
    CHECK(sa.objects == sb.objects && sa.triangles == sb.triangles);
    const Frank::FrameDiff d = Frank::diff_frames(a, b);
    const auto ca = Frank::colour_shares(a), cb = Frank::colour_shares(b);
    bool shares = true;
    for (size_t i = 0; i < ca.size(); ++i) shares = shares && std::fabs(ca[i].share - cb[i].share) < 0.005;
    if (d.mismatched >= 0.01 || !shares) {
      std::fprintf(stderr, "  %s: %.2f%% of pixels apart (largest %d)\n", name.c_str(), d.mismatched * 100,
                   d.largest);
      // Where they differ, for a CI log: one character per 10x10 block
      // ('#' over half apart, '+' some), then a few pixels side by side.
      int samples = 0;
      for (int by = 0; by < a.height; by += 10) {
        std::string row = "    ";
        for (int bx = 0; bx < a.width; bx += 10) {
          int apart = 0, n = 0;
          for (int y = by; y < std::min(by + 10, a.height); ++y)
            for (int x = bx; x < std::min(bx + 10, a.width); ++x, ++n) {
              const auto& p = a.at(x, y);
              const auto& q = b.at(x, y);
              if (std::abs(p.r - q.r) > 24 || std::abs(p.g - q.g) > 24 || std::abs(p.b - q.b) > 24) ++apart;
            }
          row += apart * 2 > n ? '#' : apart ? '+' : '.';
        }
        std::fprintf(stderr, "%s\n", row.c_str());
      }
      for (int y = 5; y < a.height && samples < 8; y += 30)
        for (int x = 5; x < a.width && samples < 8; x += 40) {
          const auto& p = a.at(x, y);
          const auto& q = b.at(x, y);
          if (std::abs(p.r - q.r) > 24 || std::abs(p.g - q.g) > 24 || std::abs(p.b - q.b) > 24) {
            std::fprintf(stderr, "    (%d,%d) opengl %d,%d,%d  software %d,%d,%d\n", x, y, p.r, p.g, p.b, q.r, q.g,
                         q.b);
            ++samples;
          }
        }
      if (const char* out = std::getenv("FRANK_TEST_SHOTS")) {  // both frames, for a look
        fs::create_directories(out, ec);
        std::string err;
        Torque::Gui::write_file((fs::path(out) / (name + "-opengl.png")).string(), Torque::Gui::encode_png(a), err);
        Torque::Gui::write_file((fs::path(out) / (name + "-software.png")).string(), Torque::Gui::encode_png(b), err);
      }
    }
    CHECK(d.mismatched < 0.01);
    CHECK(shares);
    frames[name] = a;
  }
  // The conformance checks on the OpenGL frames: C005's red cube and
  // C006's green texture at least 0.2% of the view, C004's sky faces,
  // C019's water, and C035's grass changing the lower half of C046's view
  // (here the terrain world) by at least 5%.
  auto share = [&](const std::string& world, const char* colour) {
    for (const auto& s : Frank::colour_shares(frames[world]))
      if (std::string(s.name) == colour) return s.share;
    return 0.0;
  };
  CHECK(share("cube", "red") >= 0.002);
  CHECK(share("texture", "green") >= 0.002);
  CHECK(share("sky", "sky2") >= 0.1);
  CHECK(share("grass", "magenta") >= 0.01 && share("terrain", "magenta") == 0);
  auto lower_half_changed = [&](const std::string& world, const std::string& against) {
    const Torque::Gui::Image& g = frames[world];
    const Torque::Gui::Image& t = frames[against];
    size_t changed = 0, total = 0;
    for (int y = g.height / 2; y < g.height; ++y)
      for (int x = 0; x < g.width; ++x, ++total) {
        const auto& p = g.at(x, y);
        const auto& q = t.at(x, y);
        if (std::abs(p.r - q.r) > 24 || std::abs(p.g - q.g) > 24 || std::abs(p.b - q.b) > 24) ++changed;
      }
    return double(changed) / double(total);
  };
  CHECK(lower_half_changed("grass", "terrain") >= 0.05);
  // The water blends over the fog colour below the horizon.
  CHECK(lower_half_changed("water", "sky") >= 0.5);
  fs::remove_all(dir, ec);
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
  CHECK(host.view().worlds_drawn == 1);
  CHECK(window.last().width == 320 && window.last().height == 240);
  // A 3D script's player.position is where the control object is.
  if (const auto pos = host.program().scripts().player()->child("position")) {
    float x = -1, y = -1, z = -1;
    CHECK(std::sscanf(pos->string().c_str(), "%f %f %f", &x, &y, &z) == 3);
    // A script setting it moves the object (sent with the next tick).
    pos->setString("1 2 3");
    host.tick();
    const graal3d::Vec3 at = host.link3d().link()->controlPosition();
    CHECK(at.x == 1 && at.y == 2 && at.z == 3);
  } else {
    CHECK(false);
  }
  if (const char* shot = std::getenv("FRANK_SHOT")) {  // a look at the view, by hand
    std::string err;
    Torque::Gui::write_file(shot, Torque::Gui::encode_png(window.last()), err);
  }

  // The host going away sends the 3D disconnect (0x26).
  int disconnects = 0;
  host.close();
  // Data packets from the last ticks may come first, and on macOS the
  // loopback can hand the datagrams over one at a time: read for a while.
  const auto until = std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
  while (disconnects == 0 && std::chrono::steady_clock::now() < until) {
    udp.wait(50);
    std::string d, from;
    while (udp.receiveFrom(d, from))
      if (static_cast<uint8_t>(d[0]) == 0x26) ++disconnects;
  }
  CHECK(disconnects == 1);
  if (failures)
    for (const auto& l : logs) std::fprintf(stderr, "  log: %s\n", l.c_str());
}


// The conformance probes (Graal_analysis torque/conformance/scripts, our
// own GS2, compiled by seihai-core: tests/gs2/README.md) on the 6.x GS2
// machine with the 3D classes, against what the real 5.12 reported for the
// same probe (conformance results.tsv, C030 and C026, 5.12 Windows).
std::map<std::string, std::string> run_probe(const std::string& file, double seconds,
                                             std::function<void(gs2::Machine&, double)> each = nullptr) {
  std::map<std::string, std::string> cf;
  std::ifstream in("tests/gs2/" + file, std::ios::binary);
  std::stringstream bytes;
  bytes << in.rdbuf();
  CHECK(!bytes.str().empty());
  gs2::Machine m(gs2::Profile::Engine600);
  gs2::addEngineCommands(m, {});
  Frank::install_gs2_3d(m);
  m.addCommand("triggerserver", "ss", [&cf](gs2::Machine& mm, gs2::Var&, std::vector<gs2::Value>& a) {
    if (a.size() >= 5 && mm.toString(a[2]) == "cf") cf[mm.toString(a[3])] = mm.toString(a[4]);
    return gs2::Value::number(0);
  });
  m.logMissingFunctions = false;
  auto w = m.newVar("ConfProbe");
  std::string err;
  CHECK(m.setScript(w, bytes.str(), &err));
  for (double t = 0; t < seconds; t += 0.05) {
    if (each) each(m, t);
    m.runScripts();
  }
  return cf;
}

bool near_vec(const std::string& got, std::vector<double> want, double tol = 2e-3) {
  std::istringstream in(got);
  for (double w : want) {
    double g;
    if (!(in >> g) || std::fabs(g - w) > tol) return false;
  }
  return true;
}

void test_gs2_3d() {
  CHECK(Frank::g3d_number(0.9996241920001) == "0.999624192");
  CHECK(Frank::g3d_number(-0.0) == "0" && Frank::g3d_number(7) == "7" && Frank::g3d_number(3.25) == "3.25");

  auto cf = run_probe("probe_gameobject.gs2bc", 12);
  CHECK(cf.size() == 47);  // every report the probe makes
  const std::map<std::string, std::string> exact = {
      {"made", "1"},           {"d_position", "0 0 0"},  {"d_scale", "1 1 1"},
      {"d_transform", "0 0 0 1 0 0 0"},                  {"d_rotation", "1 0 0 0"},
      {"d_euler", "0 0 0"},    {"d_velocity", "0 0 0"},  {"d_alpha", "1"},
      {"d_shape", ""},         {"d_solid", "0"},         {"d_collision", "1"},
      {"d_forward", "0 1 0"},  {"d_up", "0 0 1"},        {"d_right", "1 0 0"},
      {"d_objectbox", "0 0 0 0 0 0"},                    {"d_drawn", "0"},
      {"p_get", "1.5 -2 3.25"}, {"p_prop", "1.5 -2 3.25"}, {"p_xyz", "1.5_-2_3.25"},
      {"p_afterx", "7 -2 3.25"}, {"p_assigned", "4 5 6"}, {"s_get", "2 3 4"},
      {"s_prop", "2 3 4"},     {"s_worldbox", "4 5 6 4 5 6"}, {"s_center", "4 5 6"},
      {"t_up", "0 0 1"},       {"t_position", "1 2 3"},  {"dir_forward", "1 0 0"},
      {"sh_shape", "conf_red.3ds"}, {"sh_objectbox", "0 0 0 0 0 0"}, {"sh_drawn", "0"},
      {"n_nickname", "conf"},  {"n_alpha", "0.25"},      {"f_byname", "0"},
      {"v_velocity", "0 0 0"}, {"v_after1s", "0 0 10"},  {"o_found", "0"},
      {"x_gone", "1"},         {"done", "1"}};
  for (const auto& [k, v] : exact) {
    if (cf[k] != v) std::fprintf(stderr, "  C030 %s: got \"%s\", 5.12 \"%s\"\n", k.c_str(), cf[k].c_str(), v.c_str());
    CHECK(cf[k] == v);
  }
  // The rotation rules, to the 5.12's float precision.
  CHECK(near_vec(cf["t_get"], {1, 2, 3, 0, 0, 1, 1.5708}));
  CHECK(near_vec(cf["t_rotation"], {0, 0, 1, 1.5708}));
  CHECK(near_vec(cf["t_euler"], {0, 0, -0.027415631}));
  CHECK(near_vec(cf["t_forward"], {0.027412196, 0.999624192, 0}));
  CHECK(near_vec(cf["t_right"], {0.999624192, -0.027412196, 0}));
  CHECK(near_vec(cf["e_transform"], {1, 2, 3, 0, 0, -1, 116.62015253}));
  CHECK(near_vec(cf["e_forward"], {-0.893996596, -0.448073625, 0}));
  CHECK(near_vec(cf["dir_euler"], {0, 0, -1.570796251}));

  // C026's slice of the typed table.
  auto typed = run_probe("probe_typed.gs2bc", 8);
  CHECK(typed["getposition"] == "2 3 4" && typed["position"] == "2 3 4" && typed["getscale"] == "2 2 2");
  CHECK(typed["x"] == "2" && typed["transform"] == "2 3 4 1 0 0 0" && typed["alpha"] == "0.5");
  CHECK(typed["nickname"] == "conf" && typed["ismounted"] == "0" && typed["done"] == "1");

  // timevar3 advances with the host's clock (C009).
  auto tv = run_probe("probe_timevar3.gs2bc", 10, [](gs2::Machine& mm, double t) {
    mm.universe()->childOrCreate("timevar3")->setNumber(12.0 + t);
  });
  CHECK(tv["tv3_advances"] == "1");

  // The 5.12's request names (T3D-033, C006, C007).
  CHECK(Frank::request_name_3d("conf_tex.png") == "conf_tex");
  CHECK(Frank::request_name_3d("conf_sky2") == "conf_sky2");
  CHECK(Frank::request_name_3d("base.marble") == "base.marble");
  CHECK(Frank::request_name_3d("conf_red.3ds") == "conf_red.3ds");
  CHECK(Frank::request_name_3d("conf_marker.cs").empty() && Frank::request_name_3d("conf_marker.ter").empty());
}

}  // namespace

int main() {
  test_marker();
  test_gs2_3d();
  test_view();
  test_renderers();
  test_warp_into_3d();
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("frankenstein-6037: Login -> 178 to \"3 Lab\" -> TCP 6.03r7 login + UDP login step 6\n");
  return 0;
}
