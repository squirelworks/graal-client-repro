// The program headless against two fake servers: in the Login lobby the
// 6.03r7 row draws no tiles; after the 178 warp the title names the new
// server and the board is drawn.
#include "../shell/program.hpp"
#include "check.hpp"
#include "fake_server.hpp"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <thread>

using namespace Quattro;
using QuattroTest::FakeServer;
using Quattro::Net::gchar;

namespace {

std::string board_packet(uint16_t tile) {
  std::string b;
  for (int i = 0; i < Files::kBoardTiles; ++i) {
    b.push_back(static_cast<char>(tile & 0xFF));
    b.push_back(static_cast<char>(tile >> 8));
  }
  return b;
}

// The board goes as a raw message (id 100 with the length, then 101).
std::string send_level(const std::string& name, uint16_t tile) {
  std::string raw = gchar(101) + board_packet(tile) + "\n";
  return gchar(6) + name + "\n" + gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw +
         gchar(4) + gchar(31) + gchar(31) + gchar(1) + gchar(0) + "\n";
}

template <typename Pred>
bool run(Shell::Program& p, FakeServer* a, FakeServer* b, Pred done, int ms = 3000) {
  auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(ms);
  while (std::chrono::steady_clock::now() < end) {
    p.tick();
    if (a && a->conn.connected()) a->pump();
    if (b && b->conn.connected()) b->pump();
    if (done()) return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  }
  return false;
}

void test_program() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer login, game;
  CHECK(login.start() && game.start());

  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = login.port();
  opt.account = "guest";
  opt.password = "pw";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(login.conn.accept_from(login.listener));
  CHECK(win.title() == "Graal 6.03r7 - Login");

  CHECK(run(p, &login, nullptr, [&] { return login.saw(37, "English"); }));
  login.send(send_level("onlinestartlocal.nw", 7));
  CHECK(run(p, &login, nullptr, [&] { return p.world().have_level && !p.world().level.chests.empty(); }));
  CHECK(p.level_name() == "onlinestartlocal.nw");
  CHECK(p.world().lobby);
  p.tick();
  CHECK(p.last_passes() == Draw::pass_order());
  // Lobby: black where the tiles are, the chest drawn at (31,31).
  CHECK((win.last().at(1, 1) == Draw::Color{0, 0, 0, 255}));
  Draw::View v = Draw::follow(p.world(), 640, 480);
  int cx = static_cast<int>((31 - v.left) * 16) + 4, cy = static_cast<int>((31 - v.top) * 16) + 4;
  CHECK((win.last().at(cx, cy) == Draw::Color{150, 90, 30, 255}));

  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::thread acc([&] { game.conn.accept_from(game.listener); });
  bool warped = run(p, &login, nullptr, [&] { return p.session().logins() == 2; });
  acc.join();
  CHECK(warped);
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  CHECK(win.title() == "Graal 6.03r7 - Lab Server");
  game.send(send_level("onlinestartlocal.nw", 7));
  CHECK(run(p, nullptr, &game, [&] { return p.world().have_level; }));
  p.tick();
  CHECK(!p.world().lobby);
  CHECK(win.last().at(1, 1) == Draw::tile_colour(7));
  // The same level name again with no board after it (a Seihai gserver
  // sends it with the level's props) keeps the board.
  game.send(gchar(6) + "onlinestartlocal.nw\n");
  for (int i = 0; i < 20; ++i) {
    p.tick();
    game.pump();
  }
  CHECK(p.world().have_level);

  // Own props from the server: the client answers once with its own.
  game.send(gchar(9) + gchar(World::kX2) + Net::gshort(World::to_pixels2(20)) + gchar(World::kY2) +
            Net::gshort(World::to_pixels2(22)) + "\n");
  CHECK(run(p, nullptr, &game, [&] {
    for (auto& [id, b] : game.got)
      if (id == 2) return true;
    return false;
  }));
  CHECK(p.me().x == 20 && p.me().y == 22);
  std::string sent;
  for (auto& [id, b] : game.got)
    if (id == 2) sent = b;
  CHECK(sent == World::initial_props(p.me(), "linux"));

  // Another player on the level, then gone.
  game.send(gchar(8) + Net::gshort(7) + gchar(World::kX) + gchar(48) + gchar(World::kY) + gchar(46) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().count(7) == 1; }));
  CHECK(p.world().others.size() == 1 && p.world().others[0].x == 24);
  game.send(gchar(8) + Net::gshort(7) + gchar(World::kConnected) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().empty(); }));
}

// The engine builds' downloads: missing images are asked for with 23, a
// 102 reply (and a large file in 68 / 102 / 69) is kept in the install's
// levels/images/downloads/ and drawn from; arrays.dat is read from an
// extra asset root.
void test_downloads() {
  namespace fs = std::filesystem;
  const Net::BuildProfile* prof = Net::find_profile("5.12 Windows");
  CHECK(prof);
  if (!prof) return;
  fs::path install = fs::temp_directory_path() / "quattro-downloads-install";
  fs::path extra = fs::temp_directory_path() / "quattro-downloads-common";
  fs::remove_all(install);
  fs::remove_all(extra);
  fs::create_directories(install);
  fs::create_directories(extra);
  {
    // arrays.dat: array 0 (passable) holds tile 7, array 1 (liquids) is empty.
    std::string a;
    auto u32 = [&](uint32_t v) {
      for (int k = 3; k >= 0; --k) a.push_back(static_cast<char>((v >> (8 * k)) & 0xFF));
    };
    u32(1);
    u32(7);
    u32(0);
    std::ofstream(extra / "arrays.dat", std::ios::binary) << a;
  }

  FakeServer game;
  game.round_down = true;
  CHECK(game.start());
  Shell::Options opt;
  opt.build = "5.12 Windows";
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  opt.assets = install.string();
  opt.asset_roots = {extra.string()};
  opt.download_files = true;
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("onlinestartlocal.nw", 7) + gchar(9) + gchar(World::kBodyImg) + Net::gstring("body7.png") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return game.saw(23, "pics1.png") && game.saw(23, "body7.png"); }));
  CHECK(p.asked().count("pics1.png") == 1);

  // pics1.png in one 102 (as a raw message), body7.png as a large file.
  Torque::Gui::Image sheet(2048, 512, {10, 200, 30, 255});
  auto png = Torque::Gui::encode_png(sheet);
  std::string file = gchar(102) + Net::gint5(0) + gchar(9) + "pics1.png" + std::string(png.begin(), png.end()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(file.size())) + "\n" + file);
  Torque::Gui::Image body(128, 128, {0, 0, 250, 255});
  auto bpng = Torque::Gui::encode_png(body);
  std::string half1(bpng.begin(), bpng.begin() + static_cast<long>(bpng.size() / 2)), half2(bpng.begin() + static_cast<long>(bpng.size() / 2), bpng.end());
  std::string c1 = gchar(102) + Net::gint5(0) + gchar(9) + "body7.png" + half1 + "\n";
  std::string c2 = gchar(102) + Net::gint5(0) + gchar(9) + "body7.png" + half2 + "\n";
  game.send(gchar(68) + "body7.png\n" + gchar(100) + Net::gint3(static_cast<uint32_t>(c1.size())) + "\n" + c1 +
            gchar(100) + Net::gint3(static_cast<uint32_t>(c2.size())) + "\n" + c2 + gchar(69) + "body7.png\n");
  CHECK(run(p, nullptr, &game, [&] { return fs::exists(install / "levels/images/downloads/body7.png"); }));
  CHECK(fs::exists(install / "levels/images/downloads/pics1.png"));
  CHECK(fs::file_size(install / "levels/images/downloads/body7.png") == bpng.size());
  CHECK(p.assets().image("body7.png") != nullptr);
  p.tick();
  CHECK((win.last().at(1, 1) == Draw::Color{10, 200, 30, 255}));  // drawn from the downloaded sheet

  // Walls from the extra root's arrays.dat: tile 7 is free, so the player walks.
  CHECK(p.tile_types().loaded && !p.tile_types().blocks(7) && p.tile_types().blocks(5));

  // A file the server does not have is not asked for again.
  game.send(gchar(30) + "body7.png\n");
  size_t n = 0;
  for (int i = 0; i < 30; ++i) {
    p.tick();
    game.pump();
  }
  for (auto& [id, b] : game.got)
    if (id == 23 && b == "pics1.png") ++n;
  CHECK(n == 1);
  fs::remove_all(install);
  fs::remove_all(extra);
}

}  // namespace

int main() {
  test_program();
  test_downloads();
  TEST_MAIN_END();
}
