// Level reading and the world passes, from synthetic levels.
#include "../draw/body_colors.hpp"
#include "../draw/hud.hpp"
#include "../draw/world.hpp"
#include "../files/gani.hpp"
#include "../files/gmap.hpp"
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
         gc(3) + gc(4) + "npc.png#a;\xA7" "b;\n#\n" +
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
  CHECK(lv.npcs.size() == 1);
  if (!lv.npcs.empty())
    CHECK(lv.npcs[0].x == 3 && lv.npcs[0].y == 4 && lv.npcs[0].image == "npc.png" && lv.npcs[0].script == "a;\nb;");
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
  // 6.03r7 draws no chest of its own: only the board's tiles.
  w.chest_boxes = false;
  r.draw(c, w, v);
  CHECK((c.surface().at(2 * 16 + 4, 2 * 16 + 4) != Draw::Color{150, 90, 30, 255}));
  w.chest_boxes = true;

  // The view follows the player and stops at the level's edges.
  Draw::View f = Draw::follow(w, 640, 480);
  CHECK(f.left == 0 && f.top == 0);
  w.player.x = 60;
  w.player.y = 60;
  f = Draw::follow(w, 640, 480);
  CHECK(f.left == 64 - 40 && f.top == 64 - 30);
  // Wider than the level (1280 = 80 tiles): the player stays centred.
  w.player.x = 30;
  w.player.y = 30;
  f = Draw::follow(w, 1280, 1024);
  CHECK(f.left == 31.5 - 40 && f.top == 0);  // 1024 high fits: clamped
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
  // A carried object: its sprites.png cell at (8, head y - 22); while
  // lifting it starts on the ground row (8, +47). Effects at world pixels, over the player.
  Draw::Image sprites(64, 64, {0, 0, 0, 0});
  for (int y = 0; y < 32; ++y)
    for (int x = 0; x < 32; ++x) sprites.at(x, y) = {1, 2, 3, 255};
  for (int y = 32; y < 44; ++y)
    for (int x = 0; x < 24; ++x) sprites.at(x, y) = {4, 5, 6, 255};
  assets.put_image("sprites.png", sprites);
  w.player.carry = {0, 0, 32, 32};
  w.effects.push_back({{0, 32, 24, 12}, 9 * 16, 13 * 16, {}});
  Draw::Canvas e(160, 160);
  r.draw(e, w, v);
  CHECK(e.surface().at(32 + 8, 32 - 22).b == 3 && e.surface().at(32 + 8, 32 - 23).b != 3);
  CHECK(e.surface().at(16, 80).b == 6 && e.surface().at(16 + 24, 80).b != 6);
  w.player.lift_tick = 0;
  Draw::Canvas f(160, 160);
  r.draw(f, w, v);
  CHECK(f.surface().at(32 + 8, 32 + 47).b == 3 && f.surface().at(32 + 8, 32 + 46).b != 3);
  w.player.carry = {0, 0, 0, 0};
  w.player.lift_tick = -1;
  w.effects.clear();
  // An unknown gani falls back to idle, and with no idle to the box.
  w.player.gani = "nothing";
  Draw::Canvas d(160, 160);
  r.draw(d, w, v);
  CHECK(d.surface().at(32 + 10, 32 + 40).r == 230);
}

void test_body_colours() {
  Draw::Assets assets;
  // Palette slots 0..6 as distinct colours; a 7 x 1 image uses each once.
  std::vector<Torque::Gui::Color> pal;
  for (int i = 0; i < 7; ++i) pal.push_back({uint8_t(10 + i), 20, 30, 255});
  Draw::Image img(7, 1, {0, 0, 0, 255});
  for (int i = 0; i < 7; ++i) img.pixels[static_cast<size_t>(i)] = pal[static_cast<size_t>(i)];
  assets.put_image("body.png", img, pal);
  std::array<int, 5> colors = {2, 10, 4, 18, 7};  // skin orange, coat blue, sleeves red, shoes black, belt green
  const Draw::Image* b = assets.body("body.png", colors);
  CHECK(b != nullptr);
  auto px = [&](int x) { return b->pixels[static_cast<size_t>(x)]; };
  CHECK(px(5).r == 255 && px(5).g == 173);           // skin
  CHECK(px(6).b == 255 && px(6).r == 0);             // coat
  CHECK(px(4).r == 255 && px(4).g == 0);             // sleeves
  CHECK(px(3).b == 0 && px(3).a == 255);             // shoes: black
  CHECK(px(1).g == 255 && px(1).r == 0);             // belt
  CHECK(px(0).b == 0 && px(0).r == 0 && px(0).a == 255);  // outline: colour 18
  CHECK(px(2).a == 0);                               // clear
  // Cached per colour set; a different set is a different image.
  CHECK(assets.body("body.png", colors) == b);
  colors[0] = 4;
  CHECK(assets.body("body.png", colors)->pixels[5].g == 0);
  // No palette: the image as it is.
  assets.put_image("plain.png", img);
  CHECK(assets.body("plain.png", colors)->pixels[5].r == 15);
  CHECK(Draw::player_colour(19).a == 0 && Draw::player_colour(20).r == 255);
}

void test_hud() {
  bool small = true;
  // Up to 4 hearts: full size, one row, 45 px apart from width - 198.
  auto h = Draw::Hud::heart_slots(7, 1024, small);
  CHECK(!small && h.size() == 4);
  CHECK(h[0].x == 826 && h[3].x == 961 && h[0].y == 24 && h[3].half && !h[2].half);
  CHECK(Draw::Hud::heart_slots(0, 1024, small).empty());
  // 5 hearts: one small row, lower; 20: rows of 5, 6, 5, 4.
  h = Draw::Hud::heart_slots(10, 1024, small);
  CHECK(small && h.size() == 5 && h[0].y == 34 && h[4].x == 826 + 4 * 35);
  h = Draw::Hud::heart_slots(11, 1024, small);  // 5.5: the half in row 2, still 10 px lower
  CHECK(h.size() == 6 && h[5].half && h[5].x == 808 && h[5].y == 54);
  CHECK(Draw::Hud::heart_slots(12, 1024, small)[0].y == 24);
  h = Draw::Hud::heart_slots(40, 1024, small);
  CHECK(h.size() == 20);
  CHECK(h[5].x == 808 && h[5].y == 44 && h[11].x == 826 && h[11].y == 64 && h[16].x == 843 && h[16].y == 84);
  h = Draw::Hud::heart_slots(40, 800, small);
  CHECK(h[0].x == 602);  // anchored to the right edge
  CHECK(Draw::Hud::counter_text(0, false) == "0" && Draw::Hud::counter_text(1234, false) == "1234");
  CHECK(Draw::Hud::counter_text(5, true) == "05" && Draw::Hud::counter_text(100, true) == "10");
  // Drawing: a synthetic sheet, each piece its own colour.
  Draw::Assets assets;
  Draw::Image sheet(224, 145, {0, 0, 0, 0});
  auto paint = [&](int x, int y, int w, int hh, Torque::Gui::Color col) {
    for (int yy = y; yy < y + hh; ++yy)
      for (int xx = x; xx < x + w; ++xx) sheet.at(xx, yy) = col;
  };
  paint(0, 0, 40, 44, {255, 0, 0, 255});      // heart
  paint(202, 0, 22, 30, {0, 0, 255, 255});    // tab
  paint(0, 97, 130, 22, {0, 255, 0, 255});    // AP frame
  paint(0, 119, 100, 10, {255, 255, 0, 255}); // AP fill
  paint(1, 81, 11, 14, {255, 255, 255, 255}); // digit 0
  assets.put_image("state.png", sheet);
  Draw::Hud hud(&assets);
  Draw::Canvas c(1024, 200);
  Draw::HudState s;
  s.half_hearts = 2;
  s.ap = 30;
  hud.draw(c, s);
  CHECK(c.surface().at(826 + 5, 24 + 5).r == 255);       // the heart
  CHECK(c.surface().at(15 + 3, 30 + 3).b == 255);        // tab A
  CHECK(c.surface().at(145 + 3, 30 + 3).b == 255);       // tab D
  CHECK(c.surface().at(37 + 29, 71 + 2).g == 255 && c.surface().at(37 + 29, 71 + 2).r == 255);  // AP 30
  CHECK(c.surface().at(37 + 31, 71 + 2).r == 0);          // past it: the frame
  CHECK(c.surface().at(282, 48 + 3).r == 255);            // "0" under the gralat
  CHECK(c.surface().at(15 + 3, 90 + 3).g == 0);           // no MP bar at 0
  // Digits 12 px apart from centre - 6 * digits; sword and glove.
  Draw::Image sword(128, 96, {0, 0, 0, 0});
  for (int y = 36; y < 64; ++y) sword.at(100, y) = {9, 9, 9, 255};
  assets.put_image("sword1.png", sword);
  Draw::Image sprites(64, 256, {0, 0, 0, 0});
  sprites.at(28, 212) = {7, 7, 7, 255};
  assets.put_image("sprites.png", sprites);
  s.gralats = 0;
  s.bombs = 0;
  s.sword_power = 1;
  s.glove_power = 2;
  Draw::Canvas d(1024, 200);
  hud.draw(d, s);
  CHECK(d.surface().at(326 + 1, 48 + 1).r == 255 && d.surface().at(338 + 1, 48 + 1).r == 255);  // "00"
  CHECK(d.surface().at(105 + 6, 31 + 10).r == 9);   // sword: source + (11, -5)
  CHECK(d.surface().at(40, 29).r == 7);             // glove power 2
}

// GRMAP001: the LEVELNAMES grid, row-major and lowercased, and the short
// form rebuilt from GENERATED (the 4.04r2 offline tutorial's).
void test_gmap() {
  Files::Gmap g;
  std::string err;
  CHECK(Files::read_gmap("GRMAP001\r\nWIDTH 2\r\nHEIGHT 2\r\nLEVELNAMES\r\n\"A.nw\",\"b.nw\",\r\n\"\",\"d.nw\"\r\n"
                         "LEVELNAMESEND\r\nMAPIMG x.png\r\n",
                         g, err));
  CHECK(g.width == 2 && g.height == 2);
  CHECK(g.at(0, 0) == "a.nw" && g.at(1, 0) == "b.nw" && g.at(0, 1).empty() && g.at(1, 1) == "d.nw");
  CHECK(g.at(2, 0).empty() && g.at(-1, 0).empty());
  int x = 0, y = 0;
  CHECK(g.find("D.NW", x, y) && x == 1 && y == 1);
  CHECK(!g.find("", x, y));

  CHECK(Files::read_gmap("GRMAP001\nWIDTH 3\nHEIGHT 3\nGENERATED offlinetutorial_c-3.graal\nGENSEED 0\n"
                         "HEIGHTMAP\n-5,-5,-8,-5\nHEIGHTMAPEND\n",
                         g, err));
  CHECK(g.names.size() == 9);
  CHECK(g.at(0, 0) == "offlinetutorial_a-1.graal" && g.at(1, 1) == "offlinetutorial_b-2.graal" &&
        g.at(2, 0) == "offlinetutorial_c-1.graal" && g.at(0, 2) == "offlinetutorial_a-3.graal");

  CHECK(!Files::read_gmap("GLEVNW01\n", g, err));
  CHECK(!Files::read_gmap("GRMAP001\nWIDTH 2\n", g, err));
  CHECK(!Files::read_gmap("GRMAP001\nWIDTH 2\nHEIGHT 2\nGENERATED 1\n", g, err));  // the generator's flag
}

int main() {
  test_grv103();
  test_runs();
  test_grv105_layers();
  test_bad_levels();
  test_board_packet();
  test_sheet_pos();
  test_gmap();
  test_world_passes();
  test_gani();
  test_actor_drawing();
  test_body_colours();
  test_hud();
  TEST_MAIN_END();
}
