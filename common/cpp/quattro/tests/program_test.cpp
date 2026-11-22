// The program headless against two fake servers: in the Login lobby the
// 6.03r7 row draws no tiles; after the 178 warp the title names the new
// server and the board is drawn.
#include "../../gs2/tests/assembler.hpp"
#include "../shell/program.hpp"
#include "../draw/input_keys.hpp"
#include "check.hpp"
#include "fake_server.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <limits>
#include <set>
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
  std::vector<std::string> list;  // the player-list rows the launcher would hear
  int logins = 0;
  p.list_update = [&](const Shell::Program::ListRow& r) {
    list.push_back("+" + std::to_string(r.id) + "|" + r.nick + "|" + r.head + "|" + r.props + "|" + std::to_string(r.flags));
  };
  p.list_delete = [&](int id) { list.push_back("-" + std::to_string(id)); };
  p.logged_in = [&] { ++logins; };
  CHECK(p.start());
  CHECK(login.conn.accept_from(login.listener));
  CHECK(win.title() == "Login");
  CHECK((list == std::vector<std::string>{"-1"}));  // its own row, deleted before the first connect
  CHECK(logins == 0);

  CHECK(run(p, &login, nullptr, [&] { return login.saw(37, "English"); }));
  login.send(send_level("onlinestartlocal.nw", 7));
  CHECK(run(p, &login, nullptr, [&] { return p.world().have_level && !p.world().level.chests.empty(); }));
  CHECK(p.level_name() == "onlinestartlocal.nw");
  CHECK(p.world().lobby);
  p.tick();
  CHECK(p.last_passes() == Draw::pass_order());
  // Lobby: black where the tiles are; 6.03r7 draws no chest of its own,
  // so (31,31) stays black too.
  CHECK((win.last().at(1, 1) == Draw::Color{0, 0, 0, 255}));
  Draw::View v = Draw::follow(p.world(), 640, 480);
  int cx = static_cast<int>((31 - v.left) * 16) + 4, cy = static_cast<int>((31 - v.top) * 16) + 4;
  CHECK((win.last().at(cx, cy) == Draw::Color{0, 0, 0, 255}));

  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::thread acc([&] { game.conn.accept_from(game.listener); });
  bool warped = run(p, &login, nullptr, [&] { return p.session().logins() == 2; });
  acc.join();
  CHECK(warped);
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  CHECK(win.title() == "Lab Server");
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
  CHECK(logins == 1);  // the login counts once the server sends the player's props

  // Another player on the level, then gone.
  game.send(gchar(8) + Net::gshort(7) + gchar(World::kX) + gchar(48) + gchar(World::kY) + gchar(46) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().count(7) == 1; }));
  CHECK(p.world().others.size() == 1 && p.world().others[0].x == 24);
  game.send(gchar(8) + Net::gshort(7) + gchar(World::kConnected) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().empty(); }));

  // The player list: a player on another level is listed with the fields
  // the lab's 5.12 sent its launcher; moving sends nothing new, a new
  // head does; leaving the level keeps the row, leaving the server
  // deletes it.
  list.clear();
  game.send(gchar(8) + Net::gshort(4) + gchar(World::kNickname) + Net::gstring("lab205") + gchar(World::kHeadGif) +
            gchar(0) + gchar(World::kCurLevel) + Net::gstring("other.nw") + gchar(World::kAccountName) +
            Net::gstring("pc:9284355") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return !list.empty(); }));
  CHECK(list.size() == 1 &&
        list[0] == "+4|lab205|head0.png|account=pc:9284355,level=other.nw,communityname=,attr[1]=|8192");
  game.send(gchar(8) + Net::gshort(4) + gchar(World::kX) + gchar(40) + "\n" + gchar(8) + Net::gshort(4) +
            gchar(World::kHeadGif) + gchar(25) + "\n" + gchar(8) + Net::gshort(4) + gchar(World::kJoinLeaveLevel) +
            gchar(0) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return list.size() >= 2; }));
  for (int i = 0; i < 10; ++i) {
    p.tick();
    game.pump();
  }
  CHECK(list.size() == 2 && list[1].rfind("+4|lab205|head25.png|", 0) == 0);
  CHECK(p.player_list().count(4) == 1);
  game.send(gchar(8) + Net::gshort(4) + gchar(World::kConnected) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.player_list().count(4) == 0; }));
  CHECK(list.back() == "-4");
  // The client's own row: no nick, flag 0x4000.
  CHECK(p.player_list().size() == 1 && p.player_list().begin()->second.flags == Shell::Program::kListSelf &&
        p.player_list().begin()->second.nick.empty());
}

// The engine builds' downloads: missing images are asked for with 23, a
// 102 reply (and a large file in 68 / 102 / 69) is kept in the install's
// levels/images/downloads/ and drawn from; arrays.dat is read from an
// extra asset root.
void test_cold_gani_requests() {
  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() / "quattro-cold-gani";
  fs::create_directories(root / "levels/ganis");
  { std::ofstream f(root / "levels/ganis/broken.gani"); f << "invalid generated gani"; }
  for (const char* build : {"4.04r2", "5.00r7", "6.03r7"}) {
    const auto* profile = Net::find_profile(build);
    CHECK(profile);
    if (!profile) continue;
    FakeServer game, next;
    CHECK(game.start() && next.start());
    Shell::Options opt;
    opt.host = "127.0.0.1";
    opt.port = game.port();
    opt.server_name = "Lab Server";
    opt.assets = root.string();
    opt.download_files = true;
    Draw::HeadlessWindow win;
    Shell::Program p(*profile, opt, win);
    CHECK(p.start());
    CHECK(game.conn.accept_from(game.listener));
    CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
    const auto own = [](const std::string& gani) {
      return gchar(9) + gchar(World::kGani) + Net::gstring(gani) + "\n";
    };
    game.send(send_level("probe.nw", 7) + own("idle"));
    CHECK(run(p, nullptr, &game, [&] { return game.saw(23, "pics1.png"); }));
    for (int i = 0; i < 30; ++i) { p.tick(); game.pump(); }
    const std::string metadata = Net::gint5(0) + "idle";
    CHECK(game.saw(157, metadata) == profile->cold_gani_requests);
    if (!profile->cold_gani_requests) continue;
    auto count = [&](int id, const std::string& body) {
      return std::count(game.got.begin(), game.got.end(), std::make_pair(id, body));
    };
    CHECK(count(23, "idle.gani") == 1 && count(157, metadata) == 1);
    auto file = std::find(game.got.begin(), game.got.end(), std::make_pair(23, std::string("idle.gani")));
    CHECK(file != game.got.end() && std::next(file) != game.got.end() &&
          *std::next(file) == std::make_pair(157, metadata));
    CHECK(count(157, Net::gint5(0) + "pics1.png") == 0);
    game.send(own("shoot,wbow1.png"));
    CHECK(run(p, nullptr, &game, [&] { return game.saw(157, Net::gint5(0) + "shoot"); }));
    CHECK(p.me().gani == "shoot,wbow1.png"); // retain parameters in production player state
    CHECK(count(23, "shoot.gani") == 1 && count(157, Net::gint5(0) + "shoot") == 1);
    CHECK(!game.saw(23, "shoot,wbow1.png.gani") && !game.saw(157, Net::gint5(0) + "shoot,wbow1.png"));
    auto shoot = std::find(game.got.begin(), game.got.end(), std::make_pair(23, std::string("shoot.gani")));
    CHECK(shoot != game.got.end() && std::next(shoot) != game.got.end() &&
          *std::next(shoot) == std::make_pair(157, Net::gint5(0) + "shoot"));
    game.send(own("shoot,another-generated.png"));
    for (int i = 0; i < 30; ++i) { p.tick(); game.pump(); }
    CHECK(p.me().gani == "shoot,another-generated.png");
    CHECK(count(23, "shoot.gani") == 1 && count(157, Net::gint5(0) + "shoot") == 1);
    game.send(own("broken"));
    for (int i = 0; i < 30; ++i) { p.tick(); game.pump(); }
    CHECK(p.me().gani == "broken");
    CHECK(!game.saw(23, "broken.gani") && !game.saw(157, Net::gint5(0) + "broken"));
    game.send(own("idle"));
    for (int i = 0; i < 30; ++i) { p.tick(); game.pump(); }
    CHECK(count(23, "idle.gani") == 1 && count(157, metadata) == 1);
    game.send(gchar(178) + "0,Next Lab,127.0.0.1," + std::to_string(next.port()) + "\n");
    std::thread accept([&] { next.conn.accept_from(next.listener); });
    CHECK(run(p, &game, nullptr, [&] { return p.session().logins() == 2; }));
    accept.join();
    // Accepting TCP does not initialize the fake server codec: pump its login first.
    const bool ready = run(p, nullptr, &next, [&] { return next.saw(37, "English"); });
    CHECK(ready && next.enc != nullptr);
    if (!ready || !next.enc) continue;
    next.send(send_level("next.nw", 7) + own("idle"));
    CHECK(run(p, nullptr, &next, [&] { return next.saw(157, metadata); }));
    CHECK(next.saw(23, "idle.gani"));
  }
  fs::remove_all(root);
}
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
  opt.max_download = 1u << 20;
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

  // A file nobody asked for is not kept, nor is one whose name is unsafe
  // (a Windows device name or a stream) even when a player names it.
  std::string junk = gchar(102) + Net::gint5(0) + gchar(8) + "evil.png" + std::string(png.begin(), png.end()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(junk.size())) + "\n" + junk + gchar(68) + "big.png\n" +
            gchar(8) + Net::gshort(9) + gchar(World::kBodyImg) + Net::gstring("con.png") + gchar(World::kX) +
            gchar(60) + "\n" + gchar(8) + Net::gshort(10) + gchar(World::kBodyImg) + Net::gstring("a:b.png") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().count(10) == 1; }));
  for (int i = 0; i < 30; ++i) {
    p.tick();
    game.pump();
  }
  CHECK(!fs::exists(install / "levels/images/downloads/evil.png"));
  CHECK(p.asked().count("con.png") == 0 && p.asked().count("a:b.png") == 0);
  CHECK(!game.saw(23, "con.png") && !game.saw(23, "a:b.png"));

  // 5.12 reads the community name (prop 82) for its player list.
  game.send(gchar(8) + Net::gshort(12) + gchar(World::kAccountName) + Net::gstring("pc:1") +
            gchar(World::kCommunityName) + Net::gstring("guest") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.player_list().count(12) == 1; }));
  CHECK(p.player_list().count(12) && p.player_list().at(12).props == "account=pc:1,level=,communityname=guest,attr[1]=");

  // A large file over the cap is dropped, and so is every later chunk of it:
  // none is saved as if it were the whole file.
  game.send(gchar(8) + Net::gshort(11) + gchar(World::kBodyImg) + Net::gstring("huge.png") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return game.saw(23, "huge.png"); }));
  std::string big = gchar(102) + Net::gint5(0) + gchar(8) + "huge.png" + std::string((1u << 20) + 1, 'x') + "\n";
  std::string tail = gchar(102) + Net::gint5(0) + gchar(8) + "huge.png" + "tail" + "\n";
  game.send(gchar(68) + "huge.png\n" + gchar(100) + Net::gint3(static_cast<uint32_t>(big.size())) + "\n" + big +
            gchar(100) + Net::gint3(static_cast<uint32_t>(tail.size())) + "\n" + tail + gchar(69) + "huge.png\n" +
            gchar(100) + Net::gint3(static_cast<uint32_t>(tail.size())) + "\n" + tail);
  for (int i = 0; i < 30; ++i) {
    p.tick();
    game.pump();
  }
  CHECK(!fs::exists(install / "levels/images/downloads/huge.png"));

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

// The engine library's arrows: keys held by the test.
class HeldWindow : public Draw::HeadlessWindow {
 public:
  bool held(Draw::Key k) const override { return keys.count(k) != 0; }
  std::set<Draw::Key> keys;
};

void write(const std::filesystem::path& path, const std::string& data) {
  std::filesystem::create_directories(path.parent_path());
  std::ofstream(path, std::ios::binary) << data;
}

// Offline: a short-form gmap in levels/tutorial, no server. The centre part
// first; walking right crosses into the next part at x 64 and stops at the
// map's edge.
void test_offline() {
  const Net::BuildProfile* prof = Net::find_profile("4.04r2");
  CHECK(prof);
  if (!prof) return;
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / ("quattro-offline-" + std::to_string(std::rand()));
  write(root / "levels/tutorial/maze.gmap", "GRMAP001\r\nWIDTH 3\r\nHEIGHT 2\r\nGENERATED maze_c-2.graal\r\n");
  int n = 0;
  for (char col : {'a', 'b', 'c'})
    for (int row : {1, 2}) {
      Files::Board b{};
      b.fill(static_cast<uint16_t>(++n));
      // The centre part's NPC sets the look, the tile sheet and the ganis.
      std::string npcs;
      if (col == 'b' && row == 2)
        npcs = gchar(30) + gchar(30) +
               "#if (playerenters) {\xA7  addtiledef blue.png,maze,1;\xA7  setplayerprop #3,khead0.png;\xA7"
               "  setplayerprop #P5,klegs0.png;\xA7  replaceani idle,human2_idle;\xA7}\n";
      write(root / "levels/tutorial" / (std::string("maze_") + col + "-" + std::to_string(row) + ".graal"),
            "GR-V1.03" + Files::write_board_stream(b) + "#\n\xFF\xFF\xFF\n" + npcs + "#\n#\n\n");
    }
  Draw::Image blue(256, 32, {0, 0, 255, 255});  // tiles 0 to 15
  const auto png = Torque::Gui::encode_png(blue);
  write(root / "levels/tiles/blue.png", std::string(png.begin(), png.end()));
  Shell::Options opt;
  opt.assets = root.string();
  HeldWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start_offline("maze.gmap", 30, 30));
  CHECK(p.offline());
  CHECK(p.level_name() == "maze_b-2.graal");  // the centre cell of 3 x 2
  CHECK(p.world().have_level && p.world().level.tile(0, 0) == 4);
  p.tick();
  CHECK(!p.world().lobby);
  CHECK(win.title() == "Graal 4.04r2 - Offline");
  CHECK(p.me().head == "khead0.png" && p.me().attr[5] == "klegs0.png");
  CHECK(p.world().player.gani == "human2_idle");
  CHECK(win.last().width > 0 && win.last().at(4, 4).b == 255 && win.last().at(4, 4).r == 0);

  win.keys.insert(Draw::Key::Right);
  for (int i = 0; i < 68 && p.level_name() == "maze_b-2.graal"; ++i) p.tick();
  CHECK(p.level_name() == "maze_c-2.graal");
  CHECK(p.me().x >= 0 && p.me().x < 1);
  CHECK(p.me().level == "maze_c-2.graal");
  for (int i = 0; i < 200; ++i) p.tick();
  CHECK(p.level_name() == "maze_c-2.graal");  // nothing east of c
  CHECK(p.me().x == Files::kBoardSide - 2.0);

  win.keys = {Draw::Key::Up};
  for (int i = 0; i < 80 && p.level_name() == "maze_c-2.graal"; ++i) p.tick();
  CHECK(p.level_name() == "maze_c-1.graal");
  CHECK(p.me().y > 63 && p.me().y < 64);
  win.keys.clear();

  // The engine's bindings: a move walks; D toggles the weapon state on its
  // press, and Q (no weapon list) is D, so D held through Q is one press.
  const double x0 = p.me().x;
  CHECK(p.action("moveLeft2D", true));
  p.tick();
  CHECK(p.action("moveLeft2D", false));
  CHECK(p.me().x < x0);
  const int status = p.me().status;
  CHECK(p.action("doD", true));
  p.tick();
  CHECK(p.me().status == (status ^ 1));
  CHECK(p.action("doQ", true) && p.action("doD", false));
  p.tick();
  CHECK(p.me().status == (status ^ 1));
  CHECK(p.action("doQ", false));
  p.tick();
  CHECK(p.action("doQ", true));
  p.tick();
  CHECK(p.me().status == status);
  CHECK(p.action("doQ", false));
  p.tick();
  // A press released before the tick still counts once (a launcher that
  // sends a typed letter as down then up at once).
  CHECK(p.action("doD", true) && p.action("doD", false));
  p.tick();
  CHECK(p.me().status == (status ^ 1));
  p.tick();
  CHECK(p.me().status == (status ^ 1));
  CHECK(p.action("doD", true) && p.action("doD", false));
  p.tick();
  CHECK(p.me().status == status);
  CHECK(!p.action("doM", true) && !p.action("moveUp", true));

  CHECK(!p.start_offline("missing.gmap", 30, 30));
  CHECK(p.start_offline("maze_a-1.graal", 10, 12));  // a level alone, found below levels/
  CHECK(p.level_name() == "maze_a-1.graal" && p.me().x == 10);
  fs::remove_all(root);
}


// 4.04r2 after each login: basepackage.gupd twice (23, or 47 with the
// CRC-32 of a copy cached before the run), bigmap.txt on Login once; the
// served package kept in updatepackages/ and the game server's folder.
void test_update_packages() {
  const Net::BuildProfile* prof = Net::find_profile("4.04r2");
  CHECK(prof && prof->update_packages);
  if (!prof) return;
  CHECK(Shell::Program::package_dir("Login") == "updatepackages");
  CHECK(Shell::Program::package_dir("Lab Server") == "updatepackages/Lab%032Server");
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / ("quattro-gupd-" + std::to_string(std::rand()));
  fs::create_directories(root);
  auto count = [](const FakeServer& s, int id, const std::string& body) {
    int n = 0;
    for (const auto& [i, b] : s.got) n += (i == id && b == body);
    return n;
  };
  const std::string pkg = "GRPKG001\n";
  // A file with a newline in it goes raw (100 with the length, then 102).
  auto file_msg = [&](const std::string& name, const std::string& data) {
    std::string raw = gchar(102) + Net::gint5(0) + gchar(static_cast<unsigned>(name.size())) + name + data + "\n";
    return gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw;
  };
  {
    FakeServer login, game;
    CHECK(login.start() && game.start());
    Shell::Options opt;
    opt.host = "127.0.0.1";
    opt.port = login.port();
    opt.assets = root.string();
    opt.download_files = true;
    Draw::HeadlessWindow win;
    Shell::Program p(*prof, opt, win);
    CHECK(p.start());
    CHECK(login.conn.accept_from(login.listener));
    CHECK(run(p, &login, nullptr, [&] { return count(login, 23, "bigmap.txt") == 1; }));
    CHECK(count(login, 23, "basepackage.gupd") == 2);
    login.send(file_msg("basepackage.gupd", pkg));
    CHECK(run(p, &login, nullptr, [&] { return fs::exists(root / "updatepackages/basepackage.gupd"); }));

    login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
    std::thread acc([&] { game.conn.accept_from(game.listener); });
    CHECK(run(p, &login, nullptr, [&] { return p.session().logins() == 2; }));
    acc.join();
    // Within the run the cached copy is not checked: 23 again, no bigmap.
    CHECK(run(p, nullptr, &game, [&] { return count(game, 23, "basepackage.gupd") == 2; }));
    game.send(file_msg("basepackage.gupd", pkg));
    CHECK(run(p, nullptr, &game, [&] { return fs::exists(root / "updatepackages/Lab%032Server/basepackage.gupd"); }));
    p.tick();
    CHECK(count(game, 23, "bigmap.txt") == 0);
  }
  {
    // The next run: the cached Login copy goes as 47, "!MCt'" being the
    // CRC-32 0x15a8ea07 of "GRPKG001\n" (the live run's bytes).
    FakeServer login;
    CHECK(login.start());
    Shell::Options opt;
    opt.host = "127.0.0.1";
    opt.port = login.port();
    opt.assets = root.string();
    opt.download_files = true;
    Draw::HeadlessWindow win;
    Shell::Program p(*prof, opt, win);
    CHECK(p.start());
    CHECK(login.conn.accept_from(login.listener));
    CHECK(run(p, &login, nullptr, [&] { return count(login, 47, "!MCt'basepackage.gupd") == 2; }));
    CHECK(count(login, 23, "basepackage.gupd") == 0);
  }
  {
    // 6.03r7: basepackage.gupd twice, then the chat font when no folder
    // has it, and no bigmap.txt.
    const Net::BuildProfile* p6 = Net::find_profile("6.03r7");
    CHECK(p6 && p6->update_packages && !p6->asks_bigmap);
    if (!p6) return;
    const fs::path r6 = root / "six";
    fs::create_directories(r6);
    for (bool have_font : {false, true}) {
      if (have_font) {
        fs::create_directories(r6 / "levels/fonts");
        std::ofstream(r6 / "levels/fonts/arial.ttf") << "x";
      }
      FakeServer login;
      CHECK(login.start());
      Shell::Options opt;
      opt.host = "127.0.0.1";
      opt.port = login.port();
      opt.server_name = "Login Lab 603";
      opt.assets = r6.string();
      opt.download_files = true;
      Draw::HeadlessWindow win;
      Shell::Program p(*p6, opt, win);
      CHECK(p.start());
      CHECK(login.conn.accept_from(login.listener));
      CHECK(run(p, &login, nullptr, [&] { return count(login, 23, "basepackage.gupd") == 2; }));
      for (int i = 0; i < 5; ++i) p.tick(), login.pump();
      CHECK(count(login, 23, "arial.ttf") == (have_font ? 0 : 1));
      CHECK(count(login, 23, "bigmap.txt") == 0);
    }
  }
  fs::remove_all(root);
}

// D with the weapon list: the built-in Bomb lays a bomb (4 BOMBADD and the
// new count), a GS2 weapon gets onWeaponFired (here putbomb), Q steps the
// selection, and 194 clears the list.
void test_weapons() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  // Own props: 3 bombs, at (30, 30) facing down; then the weapon list.
  game.send(send_level("onlinestartlocal.nw", 7) + gchar(9) + gchar(World::kBombs) + gchar(3) + gchar(World::kX) +
            gchar(60) + gchar(World::kY) + gchar(60) + gchar(World::kSprite) + gchar(2) + "\n" + gchar(194) + "\n" +
            gchar(43) + gchar(8) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().selected() && p.weapons().selected()->name == "Bomb"; }));
  CHECK(run(p, nullptr, &game, [&] { return p.me().bombs == 3; }));

  p.action("doD", true);  // 1.5 tiles below the body: (30.5, 32.5)
  CHECK(run(p, nullptr, &game, [&] { return game.saw(4, gchar(61) + gchar(65) + gchar(9) + gchar(55)); }));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(2, gchar(World::kBombs) + gchar(2)); }));
  CHECK(p.me().bombs == 2 && p.combat().bombs().size() == 1);
  p.action("doD", false);

  // A GS2 weapon whose onWeaponFired puts a power-2 bomb at (10, 12).
  gs2asm::Asm a;
  a.function("onWeaponFired", {});
  // putbomb(2, 10, 12): the arguments go on the stack last first.
  a.op(gs2asm::Asm::MARKER).num(12).num(10).num(2).callName("putbomb").op(gs2asm::Asm::POP);
  a.num(0).op(gs2asm::Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Stick";
  // The bytecode goes as a raw message (100 with the length, then 140).
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(33) + Net::gstring("Stick") + "\n" + gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().selected() && p.weapons().selected()->name == "Stick"; }));
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Stick")); }));
  p.action("doD", true);
  CHECK(run(p, nullptr, &game, [&] { return game.saw(4, gchar(20) + gchar(24) + gchar(10) + gchar(55)); }));
  CHECK(p.me().bombs == 2);  // a script's bomb takes none
  p.action("doD", false);

  // Q opens the item list: Bomb and Stick side by side, Stick selected.
  p.action("doQ", true);
  CHECK(run(p, nullptr, &game, [&] { return p.item_list_open(); }));
  p.action("doQ", false);
  auto cells = p.item_cells();
  CHECK(cells.size() == 2 && cells[0].x == 48 && cells[0].y == 112 && cells[1].x == cells[0].x + cells[0].w);
  Draw::InputEvent left;
  left.key = "left";
  win.push_input(left);
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().selected()->name == "Bomb"; }));
  CHECK(std::find(p.last_passes().begin(), p.last_passes().end(), "ItemList") != p.last_passes().end());
  Draw::InputEvent del;
  del.key = "delete";
  win.push_input(del);  // Delete drops Bomb and tells the server
  CHECK(run(p, nullptr, &game, [&] { return game.saw(29, "Bomb"); }));
  CHECK(p.weapons().list().size() == 1 && p.weapons().selected()->name == "Stick");
  Draw::InputEvent esc;
  esc.key = "escape";
  win.push_input(esc);
  CHECK(run(p, nullptr, &game, [&] { return !p.item_list_open(); }));

  // Another player's HURTPLAYER: one heart off, the hurt pose, the new hearts sent.
  game.send(gchar(9) + gchar(World::kMaxPower) + gchar(3) + gchar(World::kCurPower) + gchar(6) + "\n" + gchar(8) +
            Net::gshort(7) + gchar(World::kX) + gchar(64) + gchar(World::kY) + gchar(60) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().count(7) == 1 && p.me().power == 6; }));
  game.send(gchar(40) + Net::gshort(7) + gchar(0x40) + gchar(0x40) + gchar(2) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return game.saw(2, gchar(World::kCurPower) + gchar(4)); }));
  CHECK(p.me().power == 4 && p.health().hurting());

  game.send(gchar(194) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().list().empty() && !p.scripts().weapon("Stick"); }));
}

// A GS2 weapon on the fired-weapon path of the corpus (steps 1 to 5): it
// plays a gani, holds the player, tells the server, writes player.chat,
// shows an image and a sign; the events onPlayerChats, onKeyPressed,
// onActionClientSide and onPlayerEnters reach it.
void test_escape_menu() {
  class InputWindow : public Draw::HeadlessWindow {
   public:
    Draw::Key pending = Draw::Key::NoKey;
    Draw::Key poll_key() override {
      const auto k = pending;
      pending = Draw::Key::NoKey;
      return k;
    }
  };
  for (const char* build : {"6.03r7", "6.01r1"}) {
    const auto* profile = Net::find_profile(build);
    CHECK(profile);
    if (!profile) continue;
    FakeServer game;
    CHECK(game.start());
    Shell::Options opt;
    opt.host = "127.0.0.1";
    opt.port = game.port();
    opt.server_name = "Lab Server";
    InputWindow win;
    Shell::Program p(*profile, opt, win);
    CHECK(p.start());
    CHECK(game.conn.accept_from(game.listener));
    CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
    game.send(send_level("probe.nw", 7) + gchar(9) + gchar(World::kStatus) + gchar(0) + "\n");
    CHECK(run(p, nullptr, &game, [&] { return p.world().have_level; }));
    Draw::InputEvent esc;
    esc.key = "escape";
    win.pending = Draw::Key::Escape;
    win.push_input(esc);
    if (!profile->escape_menu) {
      CHECK(!p.tick()); // legacy Escape still quits
      continue;
    }
    CHECK(p.tick() && p.me().status == 1);
    CHECK(run(p, nullptr, &game, [&] { return game.saw(2, gchar(World::kStatus) + gchar(1)); }));
    win.push_input(esc); // repeated keydown without release is not a second press
    CHECK(p.tick() && p.me().status == 1);
    esc.type = Draw::InputEvent::KeyUp;
    win.push_input(esc);
    CHECK(p.tick() && p.me().status == 1);
    esc.type = Draw::InputEvent::KeyDown;
    win.pending = Draw::Key::Escape;
    win.push_input(esc);
    CHECK(p.tick() && p.me().status == 0);
    CHECK(run(p, nullptr, &game, [&] { return game.saw(2, gchar(World::kStatus) + gchar(0)); }));
    esc.type = Draw::InputEvent::KeyUp;
    win.push_input(esc);
    p.tick();
    game.send(gchar(33) + Net::gstring("Stick") + "\n");
    CHECK(run(p, nullptr, &game, [&] { return p.weapons().any_shown(); }));
    p.action("doQ", true);
    p.tick();
    p.action("doQ", false);
    p.tick();
    CHECK(p.item_list_open());
    esc.type = Draw::InputEvent::KeyDown;
    win.pending = Draw::Key::Escape;
    win.push_input(esc);
    CHECK(p.tick() && !p.item_list_open() && p.me().status == 0);
    esc.type = Draw::InputEvent::KeyUp;
    win.push_input(esc);
    p.tick();
    p.action("doQ", true);
    p.tick();
    p.action("doQ", false);
    p.tick();
    CHECK(p.item_list_open());
    game.send(gchar(34) + "Stick\n");
    // Deliver the production session message before Program's later list cleanup.
    for (int i = 0; i < 200 && p.weapons().any_shown(); ++i) {
      p.session().tick();
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    CHECK(!p.weapons().any_shown() && p.item_list_open());
    esc.type = Draw::InputEvent::KeyDown;
    win.pending = Draw::Key::Escape;
    win.push_input(esc);
    CHECK(p.tick() && !p.weapons().any_shown() && !p.item_list_open() && p.me().status == 0);
    esc.type = Draw::InputEvent::KeyUp;
    win.push_input(esc);
    p.tick();
    auto control = std::make_shared<gs2::gui::Control>("ProbeGui", "GuiControl");
    p.gui().screen().setContent(control);
    esc.type = Draw::InputEvent::KeyDown;
    win.pending = Draw::Key::Escape;
    win.push_input(esc);
    CHECK(p.tick() && p.me().status == 0); // GUI content owns the key
    win.pending = Draw::Key::Close;
    CHECK(!p.tick()); // explicit window Close still quits
  }
}
void test_weapon_scripts() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  // Establish living login props before exercising damage notifications.
  game.send(send_level("onlinestartlocal.nw", 7) + gchar(9) + gchar(World::kMaxPower) + gchar(3) +
            gchar(World::kCurPower) + gchar(6) + gchar(World::kX) + gchar(60) + gchar(World::kY) +
            gchar(60) + "\n" + gchar(194) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.world().have_level; }));

  using gs2asm::Asm;
  const int PLAYER = 182;
  Asm a;
  a.function("onWeaponFired", {});
  a.op(Asm::MARKER).str("sword").callName("setani").op(Asm::POP);
  a.op(Asm::MARKER).num(0.5).callName("freezeplayer").op(Asm::POP);
  a.op(Asm::MARKER).str("zap").str("Wand").str("gui").callName("triggerserver").op(Asm::POP);
  a.op(PLAYER).var("chat").op(Asm::MEMBER).str("zap!").op(Asm::ASSIGN);
  a.op(Asm::MARKER).num(31).num(31).str("light.png").num(200).callName("showimg").op(Asm::POP);
  a.op(Asm::MARKER).str("Hello#bthere").callName("say2").op(Asm::POP);
  a.num(0).op(Asm::RET);
  a.function("onPlayerChats", {});
  a.var("heard").op(PLAYER).var("chat").op(Asm::MEMBER).op(Asm::ASSIGN).num(0).op(Asm::RET);
  a.function("onKeyPressed", {"code", "ch"});
  a.var("key_events").op(Asm::INC).op(Asm::POP);
  a.var("key").var("code").op(Asm::ASSIGN).num(0).op(Asm::RET);
  a.function("onPlayerHurt", {"damage"});
  a.var("hurt_events").op(Asm::INC).op(Asm::POP).num(0).op(Asm::RET);
  a.function("onPlayerDies", {});
  a.var("death_events").op(Asm::INC).op(Asm::POP).num(0).op(Asm::RET);
  a.function("public.held", {"code"});
  a.op(Asm::MARKER).var("code").callName("keydown2").op(Asm::RET);
  a.function("onActionClientSide", {"cmd"});
  a.op(PLAYER).var("chat").op(Asm::MEMBER).var("cmd").op(Asm::ASSIGN).num(0).op(Asm::RET);
  a.function("onPlayerEnters", {});
  a.var("entered").op(Asm::INC).op(Asm::POP).num(0).op(Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Wand";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(33) + Net::gstring("Wand") + "\n" + gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Wand")); }));
  auto u = p.scripts().machine().universe();
  auto g = [&](const char* k) { return u->child(k) ? u->child(k)->string() : std::string("<none>"); };

  p.action("doD", true);
  CHECK(run(p, nullptr, &game, [&] {
    return game.saw(38, Net::gint3(0) + gchar(0) + gchar(0) + "serverside,Wand,zap");
  }));
  p.action("doD", false);
  CHECK(run(p, nullptr, &game, [&] { return game.saw(2, gchar(World::kCurChat) + Net::gstring("zap!")); }));
  CHECK(p.me().gani == "sword");
  CHECK(p.freeze_left() > 0);
  CHECK(p.show_images().size() == 1);
  CHECK(p.sign_text() == "Hello#bthere");
  p.tick();
  bool drew_sign = false;
  for (const auto& n : p.last_passes()) drew_sign |= n == "Sign";
  CHECK(drew_sign);
  // The freeze runs out (0.5 s is 10 ticks).
  CHECK(run(p, nullptr, &game, [&] { return p.freeze_left() == 0; }));

  // A key the sign does not take reaches onKeyPressed; A closes the sign.
  Draw::InputEvent k;
  k.key = "k";
  k.ch = 'k';
  win.push_input(k);
  CHECK(run(p, nullptr, &game, [&] { return g("key") == "75"; }));
  CHECK(g("key_events") == "1");
  k.key = "a";
  k.ch = 'a';
  win.push_input(k);
  CHECK(run(p, nullptr, &game, [&] { return p.sign_text().empty(); }));
  auto wand = p.scripts().weapon("Wand");
  CHECK(p.scripts().machine().callFunction(wand, "held", {gs2::Value::number(75)}).num == 1);
  p.action("doQ", true);
  p.tick();
  p.action("doQ", false);
  p.tick();
  CHECK(p.item_list_open());
  k.type = Draw::InputEvent::KeyUp;
  k.key = "k";
  k.ch = 'k';
  win.push_input(k);
  p.tick();
  CHECK(p.scripts().machine().callFunction(wand, "held", {gs2::Value::number(75)}).num == 0);
  CHECK(g("key_events") == "1");
  p.action("doQ", true);
  p.tick();
  p.action("doQ", false);
  p.tick();
  CHECK(!p.item_list_open());

  p.say("hello");
  CHECK(run(p, nullptr, &game, [&] { return g("heard") == "hello"; }));

  // 48 clientside,Wand,open -> onActionClientSide("open") -> player.chat.
  game.send(gchar(48) + Net::gshort(0) + Net::gint3(0) + gchar(0) + gchar(0) + "clientside,Wand,open\n");
  CHECK(run(p, nullptr, &game, [&] { return p.me().chat == "open"; }));

  game.send(send_level("second.nw", 7));
  CHECK(run(p, nullptr, &game, [&] { return g("entered") == "1"; }));
  CHECK(p.me().max_power == 3 && p.me().power == 6);
  CHECK(g("hurt_events") == "<none>" && g("death_events") == "<none>");
  game.send(gchar(9) + gchar(World::kCurPower) + gchar(4) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return g("hurt_events") == "1"; }));
  game.send(gchar(9) + gchar(World::kCurPower) + gchar(4) + "\n");
  for (int i = 0; i < 5; ++i) p.tick();
  CHECK(g("hurt_events") == "1"); // unchanged server echo is not a second hit
  game.send(gchar(9) + gchar(World::kCurPower) + gchar(0) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return g("death_events") == "1"; }));
  CHECK(g("hurt_events") == "2");
  for (const auto& e : p.scripts().machine().errors()) std::fprintf(stderr, "%s\n", e.c_str());
  CHECK(p.scripts().machine().errors().empty());
}


void test_script_native_bounds() {
  const auto* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() / "quattro-script-bounds";
  Files::Board board{};
  board.fill(7);
  write(root / "levels/probe.graal", "GR-V1.03" + Files::write_board_stream(board) + "#\n\xFF\xFF\xFF\n#\n" +
        gchar(17) + gchar(17) + gchar(0) + gchar(0) + "\n#\n\n");
  Draw::Image pixels(16, 8, {255, 0, 0, 255});
  for (int y = 0; y < 8; ++y)
    for (int x = 8; x < 16; ++x) pixels.at(x, y) = {0, 255, 0, 255};
  auto png = Torque::Gui::encode_png(pixels);
  write(root / "frames.png", std::string(png.begin(), png.end()));
  const std::string gani = "GANI0001\nSPRITE 0 frames.png 0 0 8 8\nSPRITE 1 frames.png 8 0 8 8\n"
                           "SINGLEDIRECTION\nLOOP\nANI\n0 0 0\n1 0 0\nANIEND\n";
  write(root / "first.gani", gani);
  write(root / "second.gani", gani);
  Shell::Options opt;
  opt.assets = root.string();
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start_offline("probe.graal", 30, 30));
  gs2asm::Asm a;
  for (const char* name : {"onwall2", "onwater2"}) {
    a.function(std::string("public.") + name + "_probe", {"x", "y", "w", "h"});
    a.op(gs2asm::Asm::MARKER).var("h").var("w").var("y").var("x").callName(name).op(gs2asm::Asm::RET);
  }
  a.function("public.image", {"index"});
  a.op(gs2asm::Asm::MARKER).var("index").callName("findimg").op(gs2asm::Asm::RET);
  auto& m = p.scripts().machine();
  auto one = m.newVar("probe-one"), two = m.newVar("probe-two");
  CHECK(m.setScript(one, a.bytes()));
  CHECK(m.setScript(two, a.bytes()));
  const double inf = std::numeric_limits<double>::infinity();
  const double nan = std::numeric_limits<double>::quiet_NaN();
  for (const char* name : {"onwall2", "onwater2"})
    for (double size : {1e100, inf, nan, -1.0})
      CHECK(m.callFunction(one, std::string(name) + "_probe", {gs2::Value::number(0), gs2::Value::number(0),
            gs2::Value::number(size), gs2::Value::number(1)}).num == 0);
  CHECK(m.callFunction(one, "onwall2_probe", {gs2::Value::number(16.75), gs2::Value::number(17.5),
        gs2::Value::number(0.25), gs2::Value::number(0)}).num == 1); // includes the far edge on the chest
  auto image = [&](const gs2::VarPtr& owner, int index) {
    return m.callFunction(owner, "image", {gs2::Value::number(index)}).obj;
  };
  auto first = image(one, -7), second = image(two, -7);
  CHECK(first && second && first != second);
  if (!first || !second) return;
  for (auto im : {first, second}) {
    im->childOrCreate("type")->setString("ani");
    im->childOrCreate("layer")->setNumber(4);
    im->childOrCreate("y")->setNumber(100);
  }
  first->childOrCreate("x")->setNumber(100);
  second->childOrCreate("x")->setNumber(200);
  first->childOrCreate("ani")->setString("first");
  second->childOrCreate("ani")->setString("second");
  p.tick();
  CHECK(win.last().at(100, 100).r == 255 && win.last().at(200, 100).r == 255);
  p.tick();
  CHECK(win.last().at(100, 100).g == 255 && win.last().at(200, 100).g == 255);
  auto huge = image(one, 99);
  huge->childOrCreate("type")->setString("image");
  huge->childOrCreate("image")->setString("frames.png");
  huge->childOrCreate("layer")->setNumber(4);
  huge->childOrCreate("red")->setNumber(0.5);
  huge->childOrCreate("zoom")->setNumber(60000);
  huge->childOrCreate("x")->setNumber(500000);
  CHECK(p.tick()); // huge tinted, wholly offscreen: no full-image iteration
  huge->childOrCreate("x")->setNumber(nan);
  CHECK(p.tick()); // no nonfinite double-to-int conversion
  huge->childOrCreate("x")->setNumber(0);
  huge->childOrCreate("type")->setString("poly");
  auto polygon = huge->childOrCreate("polygon");
  polygon->setArray(6);
  const double coords[] = {-1000000, -1000000, 1000000, -1000000, 0, 1000000};
  for (int i = 0; i < 6; ++i) polygon->elements()[i]->setNumber(coords[i]);
  CHECK(p.tick()); // clip scanlines and pixels to the viewport
  polygon->elements()[0]->setNumber(inf);
  CHECK(p.tick());
  CHECK(m.errors().empty());
  fs::remove_all(root);
}

// disableselectweapons blocks Q/Tab from opening the item list; enable restores it.
void test_select_weapons() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("probe.nw", 7) + gchar(9) + gchar(World::kStatus) + gchar(0) + "\n" +
            gchar(33) + Net::gstring("Stick") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().any_shown(); }));
  CHECK(p.select_weapons_enabled());

  using gs2asm::Asm;
  Asm a;
  a.function("public.lock_select", {});
  a.op(Asm::MARKER).callName("disableselectweapons").op(Asm::POP);
  a.num(0).op(Asm::RET);
  a.function("public.open_select", {});
  a.op(Asm::MARKER).callName("enableselectweapons").op(Asm::POP);
  a.num(0).op(Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Stick";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Stick")); }));
  auto stick = p.scripts().weapon("Stick");

  p.action("doQ", true);
  p.tick();
  p.action("doQ", false);
  p.tick();
  CHECK(p.item_list_open());

  CHECK(p.scripts().machine().callFunction(stick, "lock_select", {}).num == 0);
  CHECK(!p.select_weapons_enabled());
  CHECK(!p.item_list_open());  // disable closes an open list

  p.action("doQ", true);
  p.tick();
  p.action("doQ", false);
  p.tick();
  CHECK(!p.item_list_open());  // Q does not open while disabled

  CHECK(p.scripts().machine().callFunction(stick, "open_select", {}).num == 0);
  CHECK(p.select_weapons_enabled());
  p.action("doQ", true);
  p.tick();
  p.action("doQ", false);
  p.tick();
  CHECK(p.item_list_open());
}

// testnpc(x, y): index of the level NPC whose image box covers the point, or -1.
void test_testnpc() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / ("quattro-testnpc-" + std::to_string(std::rand()));
  Files::Board b{};
  // Two NPCs: later one is on top for the same point (NpcAt walks reverse).
  const std::string npcs = gchar(10) + gchar(12) + "box.png#;\n" + gchar(10) + gchar(12) + "box.png#;\n";
  write(root / "levels/probe.nw",
        "GR-V1.03" + Files::write_board_stream(b) + "#\n\xFF\xFF\xFF\n" + npcs + "#\n#\n\n");
  Draw::Image box(32, 32, {255, 0, 0, 255});  // 2 x 2 tiles
  const auto png = Torque::Gui::encode_png(box);
  write(root / "levels/images/box.png", std::string(png.begin(), png.end()));

  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  opt.assets = root.string();
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("probe.nw", 7) + gchar(9) + gchar(World::kStatus) + gchar(0) + "\n" +
            gchar(33) + Net::gstring("Probe") + "\n");
  CHECK(run(p, nullptr, &game, [&] {
    return p.world().have_level && p.world().level.npcs.size() == 2 && p.weapons().any_shown();
  }));

  using gs2asm::Asm;
  Asm a;
  a.function("public.at", {"x", "y"});
  a.op(Asm::MARKER).var("y").var("x").callName("testnpc").op(Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Probe";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Probe")); }));
  auto probe = p.scripts().weapon("Probe");
  auto& m = p.scripts().machine();
  // Inside the 2 x 2 box: topmost NPC is index 1.
  CHECK(m.callFunction(probe, "at", {gs2::Value::number(10.5), gs2::Value::number(12.5)}).num == 1);
  CHECK(m.callFunction(probe, "at", {gs2::Value::number(11.9), gs2::Value::number(13.9)}).num == 1);
  // Outside the box, or on the exclusive right/bottom edge.
  CHECK(m.callFunction(probe, "at", {gs2::Value::number(12), gs2::Value::number(12.5)}).num == -1);
  CHECK(m.callFunction(probe, "at", {gs2::Value::number(9.5), gs2::Value::number(12.5)}).num == -1);
  fs::remove_all(root);
}


// findplayer(account): online player object by account, or 0 (GS2).
void test_findplayer() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  opt.account = "Seich";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("probe.nw", 7) + gchar(9) + gchar(World::kNickname) + Net::gstring("Self") +
            gchar(World::kX) + gchar(40) + gchar(World::kY) + gchar(42) + "\n" + gchar(33) +
            Net::gstring("Lookup") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().any_shown() && p.me().x == 20; }));

  // Another online player with an account (also lands in everyone_).
  game.send(gchar(8) + Net::gshort(9) + gchar(World::kNickname) + Net::gstring("Other") +
            gchar(World::kAccountName) + Net::gstring("pc:other") + gchar(World::kX) + gchar(50) +
            gchar(World::kY) + gchar(52) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().count(9) == 1; }));

  using gs2asm::Asm;
  Asm a;
  a.function("public.by", {"name"});
  a.op(Asm::MARKER).var("name").callName("findplayer").op(Asm::RET);
  a.function("public.nick_of", {"name"});
  a.op(Asm::MARKER).var("name").callName("findplayer").var("nick").op(Asm::MEMBER).op(Asm::RET);
  a.function("public.x_of", {"name"});
  a.op(Asm::MARKER).var("name").callName("findplayer").var("x").op(Asm::MEMBER).op(Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Lookup";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Lookup")); }));
  auto lookup = p.scripts().weapon("Lookup");
  auto& m = p.scripts().machine();
  p.tick();  // sync_player_in so self.account is set from opt.account

  // Self by login account (case-insensitive); same object as player.
  auto self = m.callFunction(lookup, "by", {gs2::Value::string("seich")});
  CHECK(self.tag == gs2::Value::Tag::Object && self.obj.get() == p.scripts().player().get());
  CHECK(m.callFunction(lookup, "nick_of", {gs2::Value::string("Seich")}).str == "Self");

  // Other by account; missing account is 0.
  CHECK(m.callFunction(lookup, "nick_of", {gs2::Value::string("pc:other")}).str == "Other");
  CHECK(m.callFunction(lookup, "x_of", {gs2::Value::string("PC:OTHER")}).num == 25);
  auto miss = m.callFunction(lookup, "by", {gs2::Value::string("nobody")});
  CHECK(miss.tag == gs2::Value::Tag::Number && miss.num == 0);
}


// putleaps(kind, x, y): object-explosion burst (GS1; kind 0..5).
void test_putleaps() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("probe.nw", 7) + gchar(9) + gchar(World::kStatus) + gchar(0) + "\n" +
            gchar(33) + Net::gstring("Burst") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().any_shown(); }));
  CHECK(p.effects().empty());

  using gs2asm::Asm;
  Asm a;
  a.function("public.bush", {});
  a.op(Asm::MARKER).num(12).num(10).num(0).callName("putleaps").op(Asm::POP);
  a.num(0).op(Asm::RET);
  a.function("public.stone", {});
  a.op(Asm::MARKER).num(1).num(1).num(2).callName("putleaps").op(Asm::POP);
  a.num(0).op(Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Burst";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Burst")); }));
  auto burst = p.scripts().weapon("Burst");
  CHECK(p.scripts().machine().callFunction(burst, "bush", {}).num == 0);
  CHECK(!p.effects().empty() && p.effects().pieces().size() == 4);
  CHECK(p.effects().pieces()[0].sprite == 25);
  for (int i = 0; i < World::Effects::kLeafTicks; ++i) p.tick();
  CHECK(p.effects().empty());
  CHECK(p.scripts().machine().callFunction(burst, "stone", {}).num == 0);
  CHECK(p.effects().empty());
}


// noplayerkilling turns off other players' swings and HURTPLAYER for the level.
void test_noplayerkilling() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("probe.nw", 7) + gchar(9) + gchar(World::kMaxPower) + gchar(3) +
            gchar(World::kCurPower) + gchar(6) + gchar(World::kX) + gchar(60) + gchar(World::kY) +
            gchar(60) + "\n" + gchar(33) + Net::gstring("Guard") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().any_shown() && p.me().power == 6; }));
  CHECK(p.player_killing());

  using gs2asm::Asm;
  Asm a;
  a.function("public.lock_pvp", {});
  a.op(Asm::MARKER).callName("noplayerkilling").op(Asm::POP);
  a.num(0).op(Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Guard";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Guard")); }));
  auto guard = p.scripts().weapon("Guard");
  CHECK(p.scripts().machine().callFunction(guard, "lock_pvp", {}).num == 0);
  CHECK(!p.player_killing());

  // Another player's swing and HURTPLAYER do nothing while PvP is off.
  // Sprite 2 = facing down; 4 tiles north of the body is in sword reach.
  game.send(gchar(8) + Net::gshort(9) + gchar(World::kX) + gchar(60) + gchar(World::kY) + gchar(52) +
            gchar(World::kSprite) + gchar(2) + gchar(World::kGani) + Net::gstring("sword") +
            gchar(World::kSwordPower) + gchar(2) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.others().count(9) == 1; }));
  for (int i = 0; i < 5; ++i) p.tick();
  CHECK(p.me().power == 6 && !p.health().hurting());
  game.send(gchar(40) + Net::gshort(9) + gchar(0x40) + gchar(0x40) + gchar(2) + "\n");
  for (int i = 0; i < 5; ++i) p.tick();
  CHECK(p.me().power == 6 && !p.health().hurting());

  // A new level restores player killing.
  game.send(send_level("next.nw", 7) + gchar(9) + gchar(World::kCurPower) + gchar(6) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.player_killing() && p.level_name() == "next.nw"; }));
}

// seteffect(r,g,b,a): global day/night tint (GS1; clamped 0..1).
void test_seteffect() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.server_name = "Lab Server";
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("probe.nw", 7) + gchar(9) + gchar(World::kStatus) + gchar(0) + "\n" +
            gchar(33) + Net::gstring("Tint") + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.weapons().any_shown(); }));
  const double* e0 = p.screen_effect();
  CHECK(e0[0] == 1 && e0[1] == 1 && e0[2] == 1 && e0[3] == 1);

  using gs2asm::Asm;
  Asm a;
  a.function("public.night", {});
  a.op(Asm::MARKER).num(0.99).num(0.4).num(0.5).num(0.6).callName("seteffect").op(Asm::POP);
  a.num(0).op(Asm::RET);
  Shell::ScriptDescriptor d;
  d.type = "weapon";
  d.name = "Tint";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Tint")); }));
  auto tint = p.scripts().weapon("Tint");
  CHECK(p.scripts().machine().callFunction(tint, "night", {}).num == 0);
  const double* e = p.screen_effect();
  CHECK(e[0] == 0.6 && e[1] == 0.5 && e[2] == 0.4 && e[3] == 0.99);

  // Out-of-range args clamp to 0..1.
  Asm b;
  b.function("public.clamp", {});
  b.op(Asm::MARKER).num(2).num(-1).num(0.25).num(1.5).callName("seteffect").op(Asm::POP);
  b.num(0).op(Asm::RET);
  d.name = "Clamp";
  raw = gchar(140) + Shell::make_script_packet(d, b.bytes()) + "\n";
  game.send(gchar(33) + Net::gstring("Clamp") + "\n");
  game.send(gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon("Clamp")); }));
  CHECK(p.scripts().machine().callFunction(p.scripts().weapon("Clamp"), "clamp", {}).num == 0);
  const double* c = p.screen_effect();
  CHECK(c[0] == 1 && c[1] == 0.25 && c[2] == 0 && c[3] == 1);
}

// 5.24r4 on Quattro: login + level + walk. Login draws tiles (unlike 6.03r7).
void test_program_524_or_beta2(const char* build) {
  const Net::BuildProfile* prof = Net::find_profile(build);
  CHECK(prof && prof->login_draws_tiles);
  if (!prof) return;
  FakeServer login, game;
  CHECK(login.start() && game.start());

  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = login.port();
  opt.account = "guest";
  opt.password = "pw";
  HeldWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(login.conn.accept_from(login.listener));
  CHECK(run(p, &login, nullptr, [&] { return login.saw(37, "English"); }));
  CHECK(login.login_line.find("G3D15010") == 0);
  CHECK(login.login_line.find("win,") != std::string::npos);

  login.send(send_level("onlinestartlocal.nw", 7));
  CHECK(run(p, &login, nullptr, [&] { return p.world().have_level; }));
  CHECK(p.world().lobby);
  p.tick();
  // Login mode still draws tiles on 5.24.
  CHECK(win.last().at(1, 1) == Draw::tile_colour(7));

  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::thread acc([&] { game.conn.accept_from(game.listener); });
  bool warped = run(p, &login, nullptr, [&] { return p.session().logins() == 2; });
  acc.join();
  CHECK(warped);
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  game.send(send_level("walk.nw", 7));
  CHECK(run(p, nullptr, &game, [&] { return p.world().have_level && !p.world().lobby; }));
  game.send(gchar(9) + gchar(World::kX2) + Net::gshort(World::to_pixels2(20)) + gchar(World::kY2) +
            Net::gshort(World::to_pixels2(22)) + "\n");
  CHECK(run(p, nullptr, &game, [&] {
    for (auto& [id, b] : game.got)
      if (id == 2) return true;
    return false;
  }));
  CHECK(p.me().x == 20 && p.me().y == 22);

  const double x0 = p.me().x;
  win.keys.insert(Draw::Key::Right);
  for (int i = 0; i < 20; ++i) {
    p.tick();
    game.pump();
  }
  win.keys.clear();
  CHECK(p.me().x > x0);
}

// 5.31r4 on Quattro: login, the 178 warp and walk, as the lab played it.
// Login mode draws no tiles before the warp (v5v6-lab-play.md).
void test_program_531_or_600(const char* build) {
  const Net::BuildProfile* prof = Net::find_profile(build);
  CHECK(prof && !prof->login_draws_tiles);
  if (!prof) return;
  FakeServer login, game;
  CHECK(login.start() && game.start());

  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = login.port();
  opt.account = "guest";
  opt.password = "pw";
  HeldWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(login.conn.accept_from(login.listener));
  CHECK(run(p, &login, nullptr, [&] { return login.saw(37, "English"); }));
  CHECK(login.login_line.find("G3D26090") == 0);
  CHECK(login.login_line.find("win,") != std::string::npos);

  login.send(send_level("onlinestartlocal.nw", 7));
  CHECK(run(p, &login, nullptr, [&] { return p.world().have_level; }));
  CHECK(p.world().lobby);
  p.tick();
  CHECK(win.last().at(1, 1) != Draw::tile_colour(7));

  login.send(gchar(178) + "0,Lab Server,127.0.0.1," + std::to_string(game.port()) + "\n");
  std::thread acc([&] { game.conn.accept_from(game.listener); });
  bool warped = run(p, &login, nullptr, [&] { return p.session().logins() == 2; });
  acc.join();
  CHECK(warped);
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  CHECK(game.login_line.find("G3D26090") == 0);
  game.send(send_level("walk.nw", 7));
  CHECK(run(p, nullptr, &game, [&] { return p.world().have_level && !p.world().lobby; }));
  p.tick();
  CHECK(win.last().at(1, 1) == Draw::tile_colour(7));
  game.send(gchar(9) + gchar(World::kX2) + Net::gshort(World::to_pixels2(20)) + gchar(World::kY2) +
            Net::gshort(World::to_pixels2(22)) + "\n");
  CHECK(run(p, nullptr, &game, [&] {
    for (auto& [id, b] : game.got)
      if (id == 2) return true;
    return false;
  }));
  CHECK(p.me().x == 20 && p.me().y == 22);
  const double x0 = p.me().x;
  win.keys.insert(Draw::Key::Right);
  for (int i = 0; i < 20; ++i) {
    p.tick();
    game.pump();
  }
  win.keys.clear();
  CHECK(p.me().x > x0);
  // The profiles share a token, but only the 6.x row sends ENTERLEVEL.
  CHECK(game.saw(46, gchar(1)) == prof->sends_enter_level);
}

// 6.03r7's level entry and the general handlers it added over 6.00:
// 46 (`c 1`) before the first props of each level, 111 kept as
// creationtime.dat, 198 stored, 109 kept as a redirect (Graal_analysis
// protocol/v6x-clients.md, protocol/enterlevel-focus-builds.md).
void test_program_603_level_entry() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof && prof->sends_enter_level);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  const auto dir = std::filesystem::temp_directory_path() / "quattro-603-entry";
  std::filesystem::remove_all(dir);
  std::filesystem::create_directories(dir);

  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.account = "guest";
  opt.password = "pw";
  opt.assets = dir.string();
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, &game, nullptr, [&] { return game.saw(37, "English"); }));
  game.send(send_level("onlinestartlocal.nw", 7));
  CHECK(run(p, &game, nullptr, [&] { return p.world().have_level; }));
  for (int i = 0; i < 5; ++i) {
    p.tick();
    game.pump();
  }
  for (auto& [id, b] : game.got) CHECK(id != 46);  // held until the props go
  game.send(gchar(9) + gchar(World::kX2) + Net::gshort(World::to_pixels2(20)) + gchar(World::kY2) +
            Net::gshort(World::to_pixels2(22)) + "\n");
  auto index_of = [&](int want, size_t from) {
    for (size_t i = from; i < game.got.size(); ++i)
      if (game.got[i].first == want) return static_cast<int>(i);
    return -1;
  };
  CHECK(run(p, &game, nullptr, [&] { return index_of(2, 0) >= 0; }));
  const int enter = index_of(46, 0), props = index_of(2, 0);
  CHECK(enter >= 0 && enter < props);
  CHECK(enter >= 0 && game.got[static_cast<size_t>(enter)].second == gchar(1));

  // A new level: 46 again at once.
  const size_t before = game.got.size();
  game.send(send_level("other.nw", 3));
  CHECK(run(p, &game, nullptr, [&] { return index_of(46, before) >= 0; }));
  int count = 0;
  for (auto& [id, b] : game.got) count += id == 46;
  CHECK(count == 2);

  // 111, 198 and 109.
  const std::string stamp = std::string("2026-11-20 \x01\x7f", 13);
  game.send(gchar(111) + stamp + "\n" + gchar(198) + Net::gint5(123456) + "\n" + gchar(109) + Net::gint5(42) +
            Net::gstring("logo.png") + Net::gstring("http://127.0.0.1/logo.png") + "\n");
  CHECK(run(p, &game, nullptr, [&] { return !p.file_redirects().empty(); }));
  CHECK(p.creation_time() == stamp);
  std::ifstream f(dir / "creationtime.dat", std::ios::binary);
  std::string disk((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  f.close();  // Windows will not remove an open file
  CHECK(disk == stamp);
  CHECK(p.server_value_198() == 123456);
  CHECK(p.file_redirects().count("logo.png") == 1 &&
        p.file_redirects().at("logo.png").url == "http://127.0.0.1/logo.png" &&
        p.file_redirects().at("logo.png").time == 42);
  std::filesystem::remove_all(dir);
}

// PLO 195: header lines for a gani already shown take effect (the newest
// wins); for one not loaded yet they are lost. A non-looping gani with a
// SETBACKTO falls back once it has played, and the client says so.
void test_program_603_load_gani() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof != nullptr);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  const auto dir = std::filesystem::temp_directory_path() / "quattro-603-gani";
  std::filesystem::remove_all(dir);
  std::filesystem::create_directories(dir);
  const std::string gani = "GANI0001\nSPRITE 0 body.png 0 0 32 32\nSINGLEDIRECTION\nANI\n0 0 0\n0 0 0\nANIEND\n";
  for (const char* name : {"kick.gani", "slash.gani"}) {
    std::ofstream f(dir / name, std::ios::binary);
    f << gani;
  }

  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.account = "guest";
  opt.password = "pw";
  opt.server_name = "Lab Server";
  opt.assets = dir.string();
  Draw::HeadlessWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, &game, nullptr, [&] { return game.saw(37, "English"); }));
  game.send(send_level("onlinestartlocal.nw", 7));
  CHECK(run(p, &game, nullptr, [&] { return p.world().have_level; }));
  game.send(gchar(9) + gchar(World::kX2) + Net::gshort(World::to_pixels2(20)) + gchar(World::kY2) +
            Net::gshort(World::to_pixels2(22)) + "\n");
  CHECK(run(p, &game, nullptr, [&] { return !p.world().lobby; }));

  // Not shown yet: the list is lost, and slash plays on.
  game.send(gchar(195) + Net::gstring("slash") + "\"SETBACKTO idle\"\n");
  game.send(gchar(9) + gchar(World::kGani) + Net::gstring("slash") + "\n");
  CHECK(run(p, &game, nullptr, [&] { return p.me().gani == "slash"; }));
  for (int i = 0; i < 40; ++i) p.tick(), game.pump();
  CHECK(p.me().gani == "slash");
  const Files::Gani* slash = p.assets().gani("slash");
  CHECK(slash && slash->set_back_to.empty());

  // Shown: the newest SETBACKTO wins, unknown lines are ignored, and the
  // player falls back to it once kick has played.
  game.send(gchar(9) + gchar(World::kGani) + Net::gstring("kick") + "\n");
  CHECK(run(p, &game, nullptr, [&] { return p.me().gani == "kick"; }));
  const size_t before = game.got.size();
  game.send(gchar(195) + Net::gstring("KICK") + "\"SETBACKTO walk\",BOGUS 1,\"SETBACKTO idle\"\n");
  CHECK(run(p, &game, nullptr, [&] { return p.me().gani == "idle"; }));
  const Files::Gani* kick = p.assets().gani("kick");
  CHECK(kick && kick->set_back_to == "idle" && !kick->loop);
  auto told = [&] {
    for (size_t i = before; i < game.got.size(); ++i)
      if (game.got[i].first == 2 && game.got[i].second.find(gchar(World::kGani) + Net::gstring("idle")) != std::string::npos)
        return true;
    return false;
  };
  CHECK(run(p, &game, nullptr, told));

  // An empty SETBACKTO means no fallback; LOOP sticks.
  game.send(gchar(195) + Net::gstring("kick") + "\"SETBACKTO \",LOOP\n");
  game.send(gchar(9) + gchar(World::kGani) + Net::gstring("kick") + "\n");
  CHECK(run(p, &game, nullptr, [&] { return p.me().gani == "kick"; }));
  for (int i = 0; i < 40; ++i) p.tick(), game.pump();
  CHECK(p.me().gani == "kick");
  kick = p.assets().gani("kick");
  CHECK(kick && kick->loop && kick->set_back_to.empty());
  std::filesystem::remove_all(dir);
}

// A level link the server leaves to the client: walking onto it sends
// one LEVELWARP (0) with the arrival and the level, then no more until
// the server answers.
void test_program_603_level_link() {
  const Net::BuildProfile* prof = Net::find_profile("6.03r7");
  CHECK(prof != nullptr);
  if (!prof) return;
  FakeServer game;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1";
  opt.port = game.port();
  opt.account = "guest";
  opt.password = "pw";
  opt.server_name = "Lab Server";
  HeldWindow win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, &game, nullptr, [&] { return game.saw(37, "English"); }));
  game.send(send_level("issho_a.nw", 7));
  game.send(gchar(1) + "issho_b.nw 40 0 1 64 2 playery\n");
  CHECK(run(p, &game, nullptr, [&] { return p.world().have_level; }));
  game.send(gchar(9) + gchar(World::kX2) + Net::gshort(World::to_pixels2(30)) + gchar(World::kY2) +
            Net::gshort(World::to_pixels2(40)) + "\n");
  CHECK(run(p, &game, nullptr, [&] { return !p.world().lobby && p.me().x == 30; }));
  win.keys.insert(Draw::Key::Right);
  CHECK(run(p, &game, nullptr, [&] { return p.link_warps_sent() == 1; }));
  // Centre x + 1.5 plus 1.25 ahead reaches column 40 from x 37.25 on.
  CHECK(p.me().x >= 37.25 && p.me().x < 38);
  CHECK(run(p, &game, nullptr, [&] { return game.saw(0, gchar(4) + gchar(80) + "issho_b.nw"); }));
  const size_t after_warp = game.got.size();
  for (int i = 0; i < 20; ++i) p.tick(), game.pump();
  CHECK(p.link_warps_sent() == 1);
  for (size_t i = after_warp; i < game.got.size(); ++i)
    CHECK(game.got[i].first != 2 || game.got[i].second.find(gchar(World::kX2)) == std::string::npos);
  win.keys.clear();
  // The server answers with the level alone, twice (as gs2emu did): the
  // client puts itself at the arrival and sends 46 once.
  const double y_before = p.me().y;
  auto count46 = [&] {
    int n = 0;
    for (auto& [id, b] : game.got) n += id == 46;
    return n;
  };
  const int entries = count46();
  game.send(gchar(6) + "issho_b.nw\n");
  game.send(send_level("issho_b.nw", 7));
  game.send(gchar(1) + "issho_a.nw 0 0 1 64 37 playery\n");
  CHECK(run(p, &game, nullptr, [&] { return p.world().have_level && p.level_name() == "issho_b.nw"; }));
  for (int i = 0; i < 5; ++i) p.tick(), game.pump();
  CHECK(p.me().x == 2 && p.me().y == y_before);
  CHECK(count46() == entries + 1);
  // A second link on the new level fires again.
  win.keys.insert(Draw::Key::Left);
  CHECK(run(p, &game, nullptr, [&] { return p.link_warps_sent() == 2; }));
  win.keys.clear();
  // The own chat clears itself 3 s (60 ticks) after it was set, and the
  // client says so with an empty prop 12 (lab: 2.97 to 2.99 s).
  game.send(gchar(9) + gchar(World::kCurChat) + Net::gstring("hello") + "\n");
  CHECK(run(p, &game, nullptr, [&] { return p.me().chat == "hello"; }));
  const std::string cleared = gchar(World::kCurChat) + Net::gstring("");
  const size_t chat_from = game.got.size();
  auto cleared_sent = [&] {
    for (size_t i = chat_from; i < game.got.size(); ++i)
      if (game.got[i].first == 2 && game.got[i].second.find(cleared) != std::string::npos) return true;
    return false;
  };
  for (int i = 0; i < 50; ++i) p.tick(), game.pump();
  CHECK(p.me().chat == "hello" && !cleared_sent());
  for (int i = 0; i < 15; ++i) p.tick(), game.pump();
  CHECK(run(p, &game, nullptr, cleared_sent));
  CHECK(p.me().chat.empty());
}


// Own-project composer through the same window queue used by native adapters.
// This is not a native-client shortcut or Unicode/IME contract.
void test_project_chat_input() {
  const auto* prof = Net::find_profile("6.03r7");
  CHECK(prof);
  if (!prof) return;
  FakeServer game;
  // The peer must use the selected profile's packed cipher rule too: the
  // capped repeated-text message compresses to a short final cipher group.
  game.round_down = prof->packed_round_down;
  CHECK(game.start());
  Shell::Options opt;
  opt.host = "127.0.0.1"; opt.port = game.port();
  opt.server_name = "Project Game"; opt.width = 320; opt.height = 240;
  class InputWindow : public HeldWindow {
   public:
    Draw::Key pending = Draw::Key::NoKey;
    Draw::Key poll_key() override { auto k = pending; pending = Draw::Key::NoKey; return k; }
  } win;
  Shell::Program p(*prof, opt, win);
  CHECK(p.start());
  CHECK(game.conn.accept_from(game.listener));
  CHECK(run(p, nullptr, &game, [&] { return game.saw(37, "English"); }));
  auto key = [&](const std::string& name, int ch = 0, const std::string& mods = "", bool up = true) {
    Draw::InputEvent e; e.key = name; e.ch = ch; e.mods = mods;
    win.push_input(e);
    if (up) { e.type = Draw::InputEvent::KeyUp; win.push_input(e); }
  };
  auto release = [&](const std::string& name) {
    Draw::InputEvent e; e.type = Draw::InputEvent::KeyUp; e.key = name; win.push_input(e);
  };
  auto frame = [&] { CHECK(p.tick()); game.pump(); };
  auto panel = [&] {
    const auto& passes = p.last_passes();
    return std::find(passes.begin(), passes.end(), "ChatInput") != passes.end();
  };
  auto sent = [&](const std::string& text) {
    const std::string body = gchar(World::kCurChat) + Net::gstring(text);
    return std::count_if(game.got.begin(), game.got.end(), [&](const auto& pk) {
      return pk.first == 2 && pk.second == body;
    });
  };
  key("enter", 13, "ctrl"); frame(); CHECK(!panel()); // no level/own props yet
  game.send(send_level("onlinestartlocal.nw", 7) + gchar(9) + gchar(World::kMaxPower) + gchar(3) +
            gchar(World::kCurPower) + gchar(6) + gchar(World::kX) + gchar(40) +
            gchar(World::kY) + gchar(40) + "\n");
  CHECK(run(p, nullptr, &game, [&] { return p.world().have_level && p.me().power == 6; }));
  using gs2asm::Asm;
  Asm a;
  a.function("onKeyPressed", {"code", "ch", "scancode"});
  a.var("chat_input_keys").op(Asm::INC).op(Asm::POP).num(0).op(Asm::RET);
  a.function("onWeaponFired", {});
  a.var("chat_input_fired").op(Asm::INC).op(Asm::POP).num(0).op(Asm::RET);
  a.function("onPlayerChats", {});
  a.var("chat_input_chats").op(Asm::INC).op(Asm::POP);
  a.var("chat_input_heard").op(182).var("chat").op(Asm::MEMBER).op(Asm::ASSIGN).num(0).op(Asm::RET);
  Shell::ScriptDescriptor d; d.type = "weapon"; d.name = "InputControl";
  std::string raw = gchar(140) + Shell::make_script_packet(d, a.bytes()) + "\n";
  game.send(gchar(33) + Net::gstring(d.name) + "\n" +
            gchar(100) + Net::gint3(static_cast<uint32_t>(raw.size())) + "\n" + raw);
  CHECK(run(p, nullptr, &game, [&] { return p.scripts().machine().hasScript(p.scripts().weapon(d.name)); }));
  auto u = p.scripts().machine().universe();
  auto value = [&](const char* name) { return u->child(name) ? u->child(name)->string() : ""; };
  key("enter", 13); frame(); CHECK(value("chat_input_keys") == "1" && !panel()); // existing plain Enter
  key("enter", 13, "ctrl", false); frame(); CHECK(panel());
  const auto edge = win.last().at(0, 240 - 36);
  CHECK(edge.r == 255 && edge.g == 255 && edge.b == 255);
  win.keys.insert(Draw::Key::Right); win.keys.insert(Draw::Key::A); win.keys.insert(Draw::Key::D);
  const double x = p.me().x;
  key("h", 'h'); key("x", 'x'); key("backspace", 8); key("i", 'i');
  key("enter", 13, "ctrl", false); // held Enter repeat must not submit
  frame(); CHECK(panel() && p.me().chat.empty() && sent("hi") == 0 && p.me().x == x);
  CHECK(value("chat_input_keys") == "1" && value("chat_input_fired").empty()); // no typed actions
  release("enter"); frame(); key("enter", 13, "", false); key("m", 'm', "", false); frame();
  CHECK(run(p, nullptr, &game, [&] { return sent("hi") == 1; }));
  CHECK(p.me().chat == "hi" && value("chat_input_heard") == "hi" && value("chat_input_chats") == "1");
  key("enter", 13, "", false); key("x", 'x'); frame();
  CHECK(sent("hi") == 1 && !panel() && value("chat_input_keys") == "1");
  CHECK(p.me().x == x); // no held-key escape into gameplay after submit
  win.keys.clear(); release("enter"); frame();
  key("m", 'm', "", false); frame(); // held non-gameplay letter is still composer-owned
  CHECK(value("chat_input_keys") == "1" && !panel());
  win.pending = Draw::Key::Escape; key("escape", 27, "", false); frame();
  CHECK(!panel() && value("chat_input_keys") == "1"); // pending composer owns physical Escape too
  release("escape"); release("m"); frame(); frame();
  key("enter", 13, "ctrl"); key("x", 'x'); frame();
  win.pending = Draw::Key::Escape; key("escape", 27, "", false); frame();
  CHECK(!panel() && sent("x") == 0 && p.me().status == 0);
  key("z", 'z'); frame(); CHECK(value("chat_input_keys") == "1");
  win.pending = Draw::Key::Escape; key("escape", 27, "", false); frame();
  CHECK(p.me().status == 0 && value("chat_input_keys") == "1"); // no cancel-repeat callback leak
  release("escape"); frame(); frame();
  key("r", 'r'); win.keys.insert(Draw::Key::Right); win.keys.insert(Draw::Key::D); frame();
  CHECK(value("chat_input_keys") == "2");
  CHECK(value("chat_input_fired") == "1");
  CHECK(p.me().x > x); // authored position is away from the helper's chest at (31,31)
  std::fprintf(stderr, "chat resume: keys=%s fired=%s x=%.1f before=%.1f status=%d panel=%d\n",
               value("chat_input_keys").c_str(), value("chat_input_fired").c_str(),
               p.me().x, x, p.me().status, panel());
  win.keys.clear(); frame();
  key("enter", 13, "ctrl"); key("enter", 13); frame(); CHECK(sent("") == 0);
  key("enter", 13, "ctrl");
  for (int i = 0; i < 230; ++i) key("a", 'a');
  key("c", 'c', "ctrl"); key("unicode", 233); // explicit portable ASCII contract
  key("enter", 13); frame();
  const std::string limit(223, 'a');
  std::fprintf(stderr, "chat cap immediate: local=%zu heard=%zu callbacks=%s panel=%d status=%d\n",
               p.me().chat.size(), value("chat_input_heard").size(), value("chat_input_chats").c_str(),
               panel(), p.me().status);
  const bool delivered_limit = run(p, nullptr, &game, [&] { return sent(limit) == 1; });
  if (!delivered_limit) {
    for (const auto& packet : game.got) {
      if (packet.first == 2)
        std::fprintf(stderr, "chat cap wire: bytes=%zu property=%u length_byte=%u\n", packet.second.size(),
                     packet.second.empty() ? 0u : static_cast<unsigned char>(packet.second[0]),
                     packet.second.size() < 2 ? 0u : static_cast<unsigned char>(packet.second[1]));
    }
  }
  CHECK(delivered_limit);
  CHECK(game.dec && !game.dec->failed());
  CHECK(p.me().chat == limit && value("chat_input_heard") == limit && value("chat_input_chats") == "2");
  frame(); frame();
  // An ordinary server peer update reaches the actor consumed by the renderer.
  game.send(gchar(8) + Net::gshort(7) + gchar(World::kNickname) + Net::gstring("Peer") +
            gchar(World::kX) + gchar(48) + gchar(World::kY) + gchar(60) +
            gchar(World::kCurChat) + Net::gstring("hi") + "\n");
  CHECK(run(p, nullptr, &game, [&] {
    return p.world().others.size() == 1 && p.world().others[0].chat == "hi";
  }));
  key("enter", 13, "ctrl"); key("s", 's'); frame(); CHECK(panel());
  game.send(gchar(6) + "onlinestartlocal.nw\n"); // unchanged level does not discard the draft
  for (int i = 0; i < 5; ++i) frame();
  CHECK(panel());
  game.send(send_level("next.nw", 7));
  CHECK(run(p, nullptr, &game, [&] { return p.level_name() == "next.nw"; }));
  CHECK(!panel() && sent("s") == 0);
  frame(); frame();
  auto content = std::make_shared<gs2::gui::Control>("ChatPriority", "GuiControl");
  p.gui().screen().setContent(content);
  key("enter", 13, "ctrl"); key("z", 'z'); frame(); CHECK(!panel() && sent("z") == 0);
  win.pending = Draw::Key::Close; CHECK(!p.tick()); // native Close still owns termination
}

// The actual X11 adapter helper: release identity must survive modifier
// changes and focus loss, so a modal composer cannot retain phantom keys.
void test_adapter_key_release_identity() {
  Draw::detail::InputKeys keys;
  Draw::InputEvent first; first.key = "!"; first.ch = '!'; first.mods = "shift";
  const auto down = keys.press(10, first);
  Draw::InputEvent repeat; repeat.key = "1"; repeat.ch = '1';
  const auto again = keys.press(10, repeat);
  CHECK(down.key == "!" && again.key == "!" && again.ch == '1' && again.mods.empty());
  const auto up = keys.release(10);
  CHECK(up && up->type == Draw::InputEvent::KeyUp && up->key == "!" && up->ch == '!');
  CHECK(!keys.release(10));
  Draw::InputEvent m; m.key = "m"; m.ch = 'm';
  Draw::InputEvent enter; enter.key = "enter"; enter.mods = "ctrl";
  keys.press(58, m); keys.press(36, enter);
  const auto lost = keys.release_all();
  CHECK(lost.size() == 2);
  CHECK(std::all_of(lost.begin(), lost.end(), [](const auto& e) { return e.type == Draw::InputEvent::KeyUp; }));
  CHECK(std::any_of(lost.begin(), lost.end(), [](const auto& e) { return e.key == "m"; }));
  CHECK(std::any_of(lost.begin(), lost.end(), [](const auto& e) { return e.key == "enter"; }));
  CHECK(keys.release_all().empty() && !keys.release(58) && !keys.release(36));
}

int main() {
  test_adapter_key_release_identity();
  test_project_chat_input();
  test_script_native_bounds();
  test_program();
  test_program_524_or_beta2("5.24r4");
  test_program_524_or_beta2("6.00b2");
  test_program_531_or_600("5.31r4");
  test_program_531_or_600("6.00r4");
  test_program_603_level_entry();
  test_program_603_load_gani();
  test_program_603_level_link();
  test_offline();
  test_update_packages();
  test_downloads();
  test_cold_gani_requests();
  test_weapons();
  test_weapon_scripts();
  test_escape_menu();
  test_select_weapons();
  test_testnpc();
  test_findplayer();
  test_putleaps();
  test_noplayerkilling();
  test_seteffect();
  TEST_MAIN_END();
}
