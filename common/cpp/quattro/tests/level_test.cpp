// Level reading and the world passes, from synthetic levels.
#include "../draw/world.hpp"
#include "../files/gani.hpp"
#include "../files/level.hpp"
#include "check.hpp"

#include <string>

using namespace Quattro;

namespace {

Files::Board pattern() {
  Files::Board b{};
  for (int i = 0; i < Files::kBoardTiles; ++i) b[static_cast<size_t>(i)] = static_cast<uint16_t>((i / 64) % 7 == 0 ? 5 : i % 4000);
  return b;
}

std::string gc(int v) { return std::string(1, static_cast<char>(v + 32)); }

std::string sections() {
  return "next.nw 0 10 1 20 playerx 30\n#\n" +
         std::string("\x05\x06\x01" "a\\b\\c\n", 9) + std::string("\xFF\xFF\xFF\n", 4) +
         gc(3) + gc(4) + "npc.png#script\n#\n" +
         gc(10) + gc(12) + gc(2) + gc(0) + "\n#\n" +
         gc(1) + gc(2) + "ABC\n\nHEIGHTS\n";
}

void test_grv103() {
  Files::Board b = pattern();
  std::string file = "GR-V1.03" + Files::write_board_stream(b) + sections();
  Files::Level lv;
  std::string err;
  CHECK(Files::read_level(file, lv, err));
  CHECK(lv.layers.size() == 1);
  CHECK(lv.layers[0] == b);
  CHECK(lv.links.size() == 1);
  if (!lv.links.empty()) {
    CHECK(lv.links[0].dest == "next.nw");
    CHECK(lv.links[0].y == 10 && lv.links[0].h == 20);
    CHECK(lv.links[0].newx == "playerx" && lv.links[0].newy == "30");
  }
  CHECK(lv.chests.size() == 1);
  if (!lv.chests.empty()) CHECK(lv.chests[0].x == 10 && lv.chests[0].y == 12 && lv.chests[0].item == 2);
  CHECK(lv.signs.size() == 1);
  if (!lv.signs.empty()) CHECK(lv.signs[0].x == 1 && lv.signs[0].encoded == "ABC");
}

// Codes written by hand: a double run and a single run.
void test_runs() {
  std::string bits;
  uint32_t buf = 0;
  int n = 0;
  auto put = [&](unsigned code) {
    buf |= code << n;
    n += 13;
    while (n >= 8) {
      bits.push_back(static_cast<char>(buf & 0xFF));
      buf >>= 8;
      n -= 8;
    }
  };
  put(0x1100 | 3);  // double run of 3 pairs
  put(7);
  put(9);
  put(0x1000 | 64);  // 64 x tile 11, and so on to fill the board
  put(11);
  int filled = 6 + 64;
  while (filled < Files::kBoardTiles) {
    int c = std::min(64, Files::kBoardTiles - filled);
    put(0x1000 | static_cast<unsigned>(c));
    put(1);
    filled += c;
  }
  if (n) bits.push_back(static_cast<char>(buf & 0xFF));
  Files::Level lv;
  std::string err;
  CHECK(Files::read_level("GR-V1.04" + bits + "#\n" + std::string("\xFF\xFF\xFF\n", 4) + "#\n#\n", lv, err));
  CHECK(lv.tile(0, 0) == 7 && lv.tile(1, 0) == 9 && lv.tile(4, 0) == 7 && lv.tile(5, 0) == 9);
  CHECK(lv.tile(6, 0) == 11 && lv.tile(5, 1) == 11 && lv.tile(6, 1) == 1);
}

void test_grv105_layers() {
  Files::Board a = pattern(), b{};
  b[100] = 42;
  std::string file = "GR-V1.05" + gc(2) + Files::write_board_stream(a) + Files::write_board_stream(b) + sections();
  Files::Level lv;
  std::string err;
  CHECK(Files::read_level(file, lv, err));
  CHECK(lv.layers.size() == 2);
  CHECK(lv.tile(36, 1, 1) == 42);
  CHECK(lv.links.size() == 1 && lv.chests.size() == 1);
}

void test_bad_levels() {
  Files::Level lv;
  std::string err;
  CHECK(!Files::read_level("GLEVNW01", lv, err));
  CHECK(!Files::read_level("GR-V1.03\x01\x02", lv, err));
  CHECK(!Files::read_level("GR-V", lv, err));
}

void test_board_packet() {
  std::string body(8192, '\0');
  body[2 * 65] = '\x34';
  body[2 * 65 + 1] = '\x02';
  Files::Level lv;
  std::string err;
  CHECK(Files::apply_board_packet(body, lv, err));
  CHECK(lv.tile(1, 1) == 0x234);
  CHECK(!Files::apply_board_packet("short", lv, err));
}

void test_sheet_pos() {
  int c, r;
  Files::tile_sheet_pos(0, c, r);
  CHECK(c == 0 && r == 0);
  Files::tile_sheet_pos(17, c, r);
  CHECK(c == 1 && r == 1);
  Files::tile_sheet_pos(512 + 3, c, r);
  CHECK(c == 19 && r == 0);
}

void test_world_passes() {
  Draw::WorldState w;
  w.level.layers.push_back(pattern());
  w.have_level = true;
  w.level.chests.push_back({2, 2, 0, 0});
  w.player.x = 10;
  w.player.y = 10;
  Draw::Canvas c(160, 120);
  Draw::WorldRenderer r;
  std::vector<std::string> seen;
  Draw::View v{};
  r.draw(c, w, v, [&](const std::string& p) { seen.push_back(p); });
  CHECK(seen == Draw::pass_order());
  // Tile (0,0) is tile 5 at pixel (1,1) in the stand-in colours.
  CHECK(c.surface().at(1, 1) == Draw::tile_colour(5));

  // The lobby without tiles: the chest is drawn, the tiles and player are not.
  w.lobby = true;
  w.lobby_tiles = false;
  r.draw(c, w, v);
  CHECK((c.surface().at(1, 1) == Draw::Color{0, 0, 0, 255}));
  CHECK((c.surface().at(2 * 16 + 4, 2 * 16 + 4) == Draw::Color{150, 90, 30, 255}));

  // The view follows the player and stops at the level's edges.
  Draw::View f = Draw::follow(w, 640, 480);
  CHECK(f.left == 0 && f.top == 0);
  w.player.x = 60;
  w.player.y = 60;
  f = Draw::follow(w, 640, 480);
  CHECK(f.left == 64 - 40 && f.top == 64 - 30);
}

}  // namespace


const char* kWalk =
    "GANI0001\n"
    "SPRITE    0  SPRITES    0    0   24   12 shadow\n"
    "SPRITE  200     HEAD    0   64   32   32 head down\n"
    "SPRITE   10     BODY    0    0   32   32 body\n"
    "SPRITE   20    ATTR1    0    0   16   16 hat\n"
    "ATTACHSPRITE 200 20 8 -4\n"
    "ATTACHSPRITE2 10 0 4 28\n"
    "LOOP\n"
    "DEFAULTATTR1 hat0.png\n"
    "\n"
    "ANI\n"
    " 10 8 16, 200 8 0\n"
    " 10 8 16, 200 8 0\n"
    " 10 8 16, 200 8 0\n"
    " 10 8 16, PARAM1 0 0, 200 8 0\n"
    "WAIT 2\n"
    "\n"
    " 10 8 17, 200 8 1\n"
    " 10 8 17, 200 8 1\n"
    " 10 8 17, 200 8 1\n"
    " 10 8 17, 200 8 1\n"
    "PLAYSOUND step.wav 0 0\n"
    "ANIEND\n";

void test_gani() {
  Files::Gani g;
  CHECK(Files::read_gani(kWalk, g));
  CHECK(g.sprites.size() == 4 && g.loop && g.default_attr[1] == "hat0.png");
  CHECK(g.steps.size() == 2 && g.steps[0].ticks == 3 && g.steps[1].ticks == 1 && g.steps[1].sound == "step.wav");
  // The body's shadow goes under it, the hat over the head.
  const auto& d = g.steps[0].dirs[2];
  CHECK(d.size() == 4);
  if (d.size() == 4) {
    CHECK(d[0].sprite == 0 && d[0].x == 12 && d[0].y == 44);
    CHECK(d[1].sprite == 10 && d[2].sprite == 200 && d[3].sprite == 20 && d[3].x == 16 && d[3].y == -4);
  }
  CHECK(g.steps[0].dirs[3].size() == 5 && g.steps[0].dirs[3][2].sprite == Files::kParamSprite - 1);
  // Steps by tick, looping over 4 ticks.
  CHECK(g.step_at(0) == 0 && g.step_at(2) == 0 && g.step_at(3) == 1 && g.step_at(4) == 0 && g.step_at(7) == 1);
  g.loop = false;
  CHECK(g.step_at(100) == 1);

  Files::Gani one;
  CHECK(Files::read_gani("SPRITE 1 SPRITES 0 0 8 8 x\nSINGLEDIRECTION\nANI\n1 0 0\n1 1 1\nANIEND\n", one));
  CHECK(one.steps.size() == 2 && one.steps[0].dirs[3].size() == 1 && one.steps[1].dirs[0][0].x == 1);
  // Script and movie blocks are skipped; no steps is a failure.
  Files::Gani none;
  CHECK(!Files::read_gani("SCRIPT\nANI\n1 0 0\nSCRIPTEND\n", none));
  CHECK(!Files::read_gani("1 2", none));
}

void test_actor_drawing() {
  Draw::Assets assets;
  Files::Gani g;
  CHECK(Files::read_gani(kWalk, g));
  assets.put_gani("walk", g);
  assets.put_image("body.png", Draw::Image(32, 32, {0, 200, 0, 255}));
  assets.put_image("head0.png", Draw::Image(32, 96, {200, 0, 0, 255}));
  assets.put_image("hat0.png", Draw::Image(16, 16, {0, 0, 200, 255}));
  Draw::WorldState w;
  w.player.x = 10;
  w.player.y = 10;
  w.player.gani = "walk";
  Draw::WorldRenderer r;
  r.set_assets(&assets);
  Draw::Canvas c(160, 160);
  Draw::View v;
  v.left = 8;
  v.top = 8;
  r.draw(c, w, v);
  // The player's top-left is at (32, 32): body at +8,+16, head at +8,+0,
  // the hat over the head at +16,-4.
  CHECK(c.surface().at(32 + 10, 32 + 40).g == 200);
  CHECK(c.surface().at(32 + 10, 32 + 2).r == 200);
  CHECK(c.surface().at(32 + 18, 32 + 2).b == 200);
  CHECK(c.surface().at(32 + 30, 32 - 6).r == 0);  // above the hat: nothing
  // An unknown gani falls back to idle, and with no idle to the box.
  w.player.gani = "nothing";
  Draw::Canvas d(160, 160);
  r.draw(d, w, v);
  CHECK(d.surface().at(32 + 10, 32 + 40).r == 230);
}

int main() {
  test_grv103();
  test_runs();
  test_grv105_layers();
  test_bad_levels();
  test_board_packet();
  test_sheet_pos();
  test_world_passes();
  test_gani();
  test_actor_drawing();
  TEST_MAIN_END();
}
