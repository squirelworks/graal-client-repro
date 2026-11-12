// The player prop stream and the props the client sends.
#include "../world/player.hpp"
#include "../world/walk.hpp"
#include "check.hpp"

#include <cmath>
#include <vector>

using namespace Quattro;
using namespace Quattro::World;
using Net::gchar;
using Net::gint3;
using Net::gshort;
using Net::gstring;

namespace {

void test_pixels2() {
  CHECK(to_pixels2(1.0) == 32);
  CHECK(to_pixels2(-0.5) == 17);
  CHECK(from_pixels2(32) == 1.0);
  CHECK(from_pixels2(17) == -0.5);
  CHECK(from_pixels2(to_pixels2(30.5)) == 30.5);
}

void test_own_props() {
  std::string s = gchar(kNickname) + gstring("Bob") + gchar(kCurPower) + gchar(6) + gchar(kRupees) + gint3(1234) +
                  gchar(kSwordPower) + gchar(31) + gstring("sword1.png") + gchar(kShieldPower) + gchar(2) +
                  gchar(kGani) + gstring("idle.gani") + gchar(kHeadGif) + gchar(5) + gchar(kColors) + gchar(1) +
                  gchar(2) + gchar(3) + gchar(4) + gchar(5) + gchar(kSprite) + gchar(6) + gchar(kCurLevel) +
                  gstring("onlinestartlocal.nw") + gchar(kGattrib1 + 2) + gstring("g3") + gchar(kGattrib10) +
                  gstring("g10") + gchar(kX2) + gshort(to_pixels2(30.5)) + gchar(kY2) + gshort(to_pixels2(-1));
  Net::Reader r(s);
  Player p;
  CHECK(apply_props(r, p, false) == 14);
  CHECK(p.nickname == "Bob" && p.power == 6 && p.rupees == 1234);
  CHECK(p.sword_power == 1 && p.sword_image == "sword1.png");
  CHECK(p.shield_power == 2 && p.shield_image.empty());
  CHECK(p.gani == "idle" && p.head == "head5.png");
  CHECK(p.colors[4] == 5 && p.dir == 2);
  CHECK(p.level == "onlinestartlocal.nw");
  CHECK(p.attr[3] == "g3" && p.attr[10] == "g10");
  CHECK(p.x == 30.5 && p.y == -1);
}

void test_other_props() {
  // 14 (id) is not accepted for another player: the stream stops there.
  std::string s = gchar(kX) + gchar(20) + gchar(kId) + gshort(9) + gchar(kY) + gchar(20);
  Net::Reader r(s);
  Player o;
  CHECK(apply_props(r, o, true) == 1);
  CHECK(o.x == 10 && o.y == 30);
  // 51 ends the player.
  std::string gone = gchar(kConnected);
  Net::Reader g(gone);
  Player q;
  apply_props(g, q, true);
  CHECK(q.gone);
  // An unknown id stops the stream.
  std::string unk = gchar(77) + gchar(kX) + gchar(4);
  Net::Reader u(unk);
  Player w;
  CHECK(apply_props(u, w, false) == 0);
}

void test_sending() {
  Player p;
  p.nickname = "unknown";
  p.language = "English";
  p.x = 30;
  p.y = 31;
  std::string init = initial_props(p, "linux");
  Net::Reader r(init);
  Player back;
  CHECK(apply_props(r, back, false) == 6);
  CHECK(back.nickname == "unknown" && back.language == "English" && back.os_type == "linux");
  CHECK(back.x == 30 && back.y == 31);

  MoveSender m;
  m.reset(p);
  CHECK(m.diff(p).empty());
  p.x += 0.5;
  CHECK(m.diff(p) == gchar(kX2) + gshort(to_pixels2(30.5)));  // only what changed
  p.dir = 1;
  p.y -= 0.5;
  CHECK(m.diff(p) == gchar(kSprite) + gchar(1) + gchar(kY2) + gshort(to_pixels2(30.5)));
  CHECK(m.diff(p).empty());
}


std::string u32(uint32_t v) {
  return std::string{char(v >> 24), char((v >> 16) & 0xFF), char((v >> 8) & 0xFF), char(v & 0xFF)};
}

// Tile 0 and 7 passable, 9 a liquid, anything else (5) a wall.
TileTypes test_types() {
  std::string d = u32(2) + u32(0) + u32(7) + u32(1) + u32(9) + u32(0x10001) + u32(1) + u32(5);
  TileTypes t;
  std::string err;
  CHECK(read_arrays_dat(d, t, err));
  return t;
}

Files::Level open_level() {
  Files::Level l;
  l.layers.emplace_back();
  l.layers[0].fill(0);
  return l;
}

void set_tile(Files::Level& l, int x, int y, uint16_t t) { l.layers[0][static_cast<size_t>(y * Files::kBoardSide + x)] = t; }

void test_arrays_dat() {
  TileTypes t = test_types();
  CHECK(t.loaded && !t.blocks(0) && !t.blocks(7) && !t.blocks(9) && t.blocks(5));
  std::string err;
  TileTypes bad;
  CHECK(!read_arrays_dat(u32(3) + u32(1), bad, err) && !bad.loaded);
  CHECK(!read_arrays_dat(u32(0), bad, err));  // one array only
  // No table: nothing blocks.
  CHECK(!TileTypes{}.blocks(5));
}

void test_walls() {
  TileTypes t = test_types();
  Files::Level l = open_level();
  for (int y = 0; y < Files::kBoardSide; ++y) set_tile(l, 33, y, 5);
  Player p;
  p.x = 29.5;
  p.y = 30;
  CHECK(step(p, 3, l, t) && p.x == 30 && p.dir == 3);  // the box's right edge reaches 32.5
  CHECK(!step(p, 3, l, t) && p.x == 30);                // 33.0 is the wall
  CHECK(step(p, 1, l, t) && p.x == 29.5 && p.dir == 1);
  // A liquid is walkable.
  for (int y = 0; y < Files::kBoardSide; ++y) set_tile(l, 33, y, 9);
  p.x = 30;
  CHECK(step(p, 3, l, t));

  // Up into a lone wall tile under the first probe point: refused, nudged
  // 0.1 to the right.
  Files::Level n = open_level();
  set_tile(n, 30, 30, 5);
  Player q;
  q.x = 30;
  q.y = 30;
  CHECK(!step(q, 0, n, t) && q.y == 30 && std::abs(q.x - 30.1) < 1e-9);

  // A chest blocks its 2 x 2 tiles, edges included.
  Files::Level c = open_level();
  c.chests.push_back({31, 29, 0, 0});
  Player r;
  r.x = 30;
  r.y = 30;
  CHECK(!step(r, 0, c, t) && r.y == 30 && r.x == 30);
}

void test_push() {
  TileTypes t = test_types();
  Files::Level l = open_level();
  for (int y = 0; y < Files::kBoardSide; ++y) set_tile(l, 33, y, 5);
  Player p;
  p.x = 30;
  p.y = 30;
  Walker w;
  std::vector<int> pushed;
  for (int tick = 1; tick <= 70; ++tick) {
    if (!w.tick(p, 8, l, t).empty()) pushed.push_back(tick);
    if (tick == 17) CHECK(p.gani == "walk");
    if (tick == 18) CHECK(p.gani == "push");
  }
  // 0.55 s after the push starts, then every second.
  CHECK(pushed.size() == 3 && pushed[0] == 29 && pushed[1] == 49 && pushed[2] == 69);
  CHECK(w.tick(p, 0, l, t).empty() && p.gani == "idle" && !w.pushing());
  // Walking in the open never pushes.
  p.x = 10;
  for (int tick = 0; tick < 30; ++tick) w.tick(p, 4, l, t);
  CHECK(p.gani == "walk" && p.y > 30);
}

}  // namespace

int main() {
  test_pixels2();
  test_own_props();
  test_other_props();
  test_sending();
  test_arrays_dat();
  test_walls();
  test_push();
  TEST_MAIN_END();
}
