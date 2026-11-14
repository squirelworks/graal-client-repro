// The program headless against two fake servers: in the Login lobby the
// 6.03r7 row draws no tiles; after the 178 warp the title names the new
// server and the board is drawn.
#include "../../gs2/tests/assembler.hpp"
#include "../shell/program.hpp"
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
  game.send(send_level("onlinestartlocal.nw", 7) + gchar(9) + gchar(World::kX) + gchar(60) + gchar(World::kY) +
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

int main() {
  test_script_native_bounds();
  test_program();
  test_offline();
  test_update_packages();
  test_downloads();
  test_weapons();
  test_weapon_scripts();
  TEST_MAIN_END();
}
