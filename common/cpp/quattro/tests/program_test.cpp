// The program headless against two fake servers: in the Login lobby the
// 6.03r7 row draws no tiles; after the 178 warp the title names the new
// server and the board is drawn.
#include "../shell/program.hpp"
#include "check.hpp"
#include "fake_server.hpp"

#include <chrono>
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
}

}  // namespace

int main() {
  test_program();
  TEST_MAIN_END();
}
