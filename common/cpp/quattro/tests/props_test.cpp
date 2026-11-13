// The player prop stream and the props the client sends.
#include "../world/actions.hpp"
#include "../world/effects.hpp"
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

// arrays.dat with a bush (tiles 2, 3 / 18, 19) in the cut and lift lists,
// leaving 677, 678 / 693, 694; tile 5 a wall.
std::string flat(std::vector<uint32_t> v) {
  std::string s = u32(static_cast<uint32_t>(v.size()));
  for (auto x : v) s += u32(x);
  return s;
}
std::string obj_list(uint32_t a, uint32_t b, uint32_t c, uint32_t d) {
  // one object: column 0 (rows a, c), column 1 (rows b, d)
  return u32(0x10001) + u32(0x10002) + flat({a, c}) + flat({b, d});
}
std::string items_dat() {
  std::string d = flat({0, 2, 3, 18, 19, 677, 678, 693, 694}) + flat({});
  for (int i = 2; i <= 8; ++i) d += flat({});
  d += obj_list(2, 3, 18, 19) + obj_list(677, 678, 693, 694) + obj_list(2, 3, 18, 19) + obj_list(677, 678, 693, 694);
  return d;
}

std::string gani_of(const std::vector<Packet>& out) {
  for (const auto& p : out)
    if (p.id == 2 && !p.body.empty() && p.body[0] == gchar(kGani)[0]) {
      Net::Reader r(p.body);
      r.gchar();
      return r.gstring();
    }
  return {};
}

void test_item_keys() {
  std::string d = items_dat();
  ObjectTables tables;
  TileTypes types;
  std::string err;
  CHECK(read_object_tables(d, tables) && tables.loaded && tables.cut.size() == 1 && tables.lift_left.size() == 1);
  CHECK(read_arrays_dat(d, types, err));
  CHECK(object_tile(tables.cut[0], 1, 0) == 3 && object_tile(tables.cut[0], 0, 1) == 18);

  // S facing right with a bush at the blade's tip (x + 3.5, y + 2).
  Files::Level l = open_level();
  set_tile(l, 34, 32, 2);
  set_tile(l, 35, 32, 3);
  set_tile(l, 34, 33, 18);
  set_tile(l, 35, 33, 19);
  Player p;
  p.x = 31;
  p.y = 30;
  p.dir = 3;
  p.sword_power = 1;
  ItemKeys k;
  auto out = k.tick(p, kKeyS, 0, l, tables, types);
  CHECK(out.size() == 2 && gani_of(out) == "sword" && out[0].body.substr(out[0].body.size() - 2) == gchar(kSprite) + gchar(3));
  CHECK(out[1].id == 1 && out[1].body == board_modify(34, 32, 2, 2, {677, 678, 693, 694}));
  CHECK(l.tile(35, 33) == 694 && k.busy());
  for (int t = 1; t < ItemKeys::kSwordTicks; ++t) CHECK(k.tick(p, kKeyS, 0, l, tables, types).empty());
  out = k.tick(p, kKeyS, 0, l, tables, types);  // 0.25 s: idle; holding S does not swing again
  CHECK(gani_of(out) == "idle" && !k.busy());
  CHECK(k.tick(p, kKeyS, 0, l, tables, types).empty());

  // A on the bush: lift, the carry sprite at 0.20 s, carrystill at 0.30 s.
  set_tile(l, 34, 32, 2);
  set_tile(l, 35, 32, 3);
  set_tile(l, 34, 33, 18);
  set_tile(l, 35, 33, 19);
  k.tick(p, 0, 0, l, tables, types);
  out = k.tick(p, kKeyA, 0, l, tables, types);
  CHECK(out.size() == 2 && out[0].id == 1 && gani_of(out) == "lift" && k.carrying());
  CHECK(out[1].body.substr(out[1].body.size() - 2) == gchar(kCarrySprite) + gchar(static_cast<unsigned>(-1)));
  std::vector<std::string> seen;
  for (int t = 1; t <= ItemKeys::kCarryStillAfter; ++t)
    for (const auto& pk : k.tick(p, 0, 0, l, tables, types)) seen.push_back(std::to_string(t) + ":" + pk.body);
  CHECK(seen.size() == 2 && seen[0] == "4:" + gchar(kCarrySprite) + gchar(1) && p.carry_sprite == 1);
  CHECK(k.carry_sprite() == 1 && carried_sprite(p.carry_sprite) == 261);
  CHECK(seen[1] == "6:" + gchar(kGani) + gstring("carrystill") && !k.busy() && k.carrying());
  // A again: thrown.
  out = k.tick(p, kKeyA, 0, l, tables, types);
  CHECK(out.size() == 2 && out[0].id == 11 && out[0].body.empty() && gani_of(out) == "idle" && !k.carrying());
  CHECK(p.carry_sprite == -1 && k.carry_sprite() == -1);

  // A against a wall: grab; with the arrow away held, pull.
  set_tile(l, 34, 32, 5);
  k.tick(p, 0, 0, l, tables, types);
  CHECK(gani_of(k.tick(p, kKeyA, 0, l, tables, types)) == "grab");
  k.tick(p, 0, 0, l, tables, types);
  CHECK(gani_of(k.tick(p, kKeyA, 2, l, tables, types)) == "pull");

  // D toggles bit 0 of the status.
  p.status = 20;
  k.tick(p, 0, 0, l, tables, types);
  out = k.tick(p, kKeyD, 0, l, tables, types);
  CHECK(p.status == 21 && out.size() == 1 && out[0].body == gchar(kStatus) + gchar(21));

  // Walking up into a chest opens it once.
  Files::Level c = open_level();
  c.chests.push_back({49, 22, 1, 0});
  Player q;
  q.x = 48;
  q.y = 23;
  q.dir = 0;
  out = k.touch_chests(q, 1, c);
  CHECK(out.size() == 1 && out[0].id == 20 && out[0].body == gchar(49) + gchar(22));
  CHECK(k.touch_chests(q, 1, c).empty() && k.touch_chests(q, 0, c).empty());
}

void test_effects() {
  // The sprite list: 261 is the bush's (0, 338) 32 x 32 cell.
  std::string d = items_dat();
  std::vector<uint32_t> sprites(262, 0);
  sprites[261] = (0u << 23) | ((338u / 2) << 12) | ((32u / 2) << 6) | (32u / 2);
  for (int i = 13; i < 24; ++i) d += flat({});
  d += flat(sprites);
  ObjectTables tables;
  CHECK(read_object_tables(d, tables) && tables.sprites.size() == 262);
  int x, y, w, h;
  CHECK(sprite_rect(tables, 261, x, y, w, h) && x == 0 && y == 338 && w == 32 && h == 32);
  CHECK(!sprite_rect(tables, 260, x, y, w, h) && !sprite_rect(tables, 400, x, y, w, h));

  // A bush thrown right from (480, 480): from (488, 458), 16 px a tick,
  // 24 px lower after 8 ticks, its shadow on the ground at y 514.
  Effects e;
  e.throw_object(1, 480, 480, 3);
  auto ps = e.pieces();
  CHECK(ps.size() == 2 && ps[0].sprite == 0 && ps[0].x == 490 && ps[0].y == 514);
  CHECK(ps[1].sprite == 261 && ps[1].x == 488 && ps[1].y == 458);
  for (int t = 1; t < Effects::kThrowTicks; ++t) CHECK(e.tick().empty());
  ps = e.pieces();
  CHECK(ps.size() == 2 && ps[1].x == 488 + 7 * 16 && ps[1].y == 458 + 21 && ps[0].y == 514);
  // It lands 128 px on and breaks into 4 leaves; nothing is sent.
  CHECK(e.tick().empty());
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].sprite == 25 && ps[0].x == 616 && ps[0].y == 482 && ps[3].x == 632 && ps[3].y == 498);
  for (int t = 0; t < Effects::kBreakTicks; ++t) e.tick();
  CHECK(e.empty());

  // A pot breaks into shards, 97 on the right and 99 on the left; a stone
  // into nothing.
  e.throw_object(5, 0, 0, 2);
  for (int t = 0; t < Effects::kThrowTicks; ++t) e.tick();
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].sprite == 99 && ps[1].sprite == 97);
  e.clear();
  e.throw_object(3, 0, 0, 2);
  for (int t = 0; t < Effects::kThrowTicks; ++t) e.tick();
  CHECK(e.empty());

  // A cut bush: 4 leaves on its tiles, drifting down.
  e.cut_bush(34, 32);
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].x == 544 && ps[0].y == 512 && ps[3].x == 560 && ps[3].y == 528);
  e.tick();
  ps = e.pieces();
  CHECK(ps[0].x == 543 && ps[0].y == 514 && ps[1].x == 561);
  for (int t = 1; t < Effects::kLeafTicks; ++t) e.tick();
  CHECK(e.empty());

  // A chest at (30, 30) with a green gralat: the gralat one tile up, then
  // 13 ITEMDEL (60, 58) at 1.2 s.
  e.chest_item(0, 30, 30);
  ps = e.pieces();
  CHECK(ps.size() == 1 && ps[0].sprite == 136 && ps[0].x == 488 && ps[0].y == 462);
  for (int t = 1; t < Effects::kChestItemTicks; ++t) CHECK(e.tick().empty());
  auto out = e.tick();
  CHECK(out.size() == 1 && out[0].id == 13 && out[0].body == gchar(60) + gchar(58) && e.empty());
  e.chest_item(99, 30, 30);
  CHECK(e.empty());

  // The carry sprite prop: -1 is 255 on the wire.
  Player p;
  Net::Reader r(gchar(kCarrySprite) + gchar(5));
  apply_props(r, p, false);
  CHECK(p.carry_sprite == 5);
  Net::Reader r2(gchar(kCarrySprite) + gchar(static_cast<unsigned>(-1)));
  apply_props(r2, p, false);
  CHECK(p.carry_sprite == -1);
}

void test_carry_walk() {
  Files::Level l = open_level();
  TileTypes types;
  Player p;
  p.x = 30;
  p.y = 30;
  p.gani = "carrystill";
  Walker w;
  w.tick(p, 8, l, types, true);
  CHECK(p.gani == "carry" && p.x > 30);
  w.tick(p, 0, l, types, true);
  CHECK(p.gani == "carrystill");
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
  test_item_keys();
  test_effects();
  test_carry_walk();
  TEST_MAIN_END();
}
