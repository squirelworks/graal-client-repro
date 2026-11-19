// The player prop stream and the props the client sends.
#include "../world/actions.hpp"
#include "../net/profile.hpp"
#include "../world/effects.hpp"
#include "../world/weapons.hpp"
#include "../world/floor_items.hpp"
#include "../world/health.hpp"
#include "../world/item_list.hpp"
#include "../world/npcs.hpp"
#include <map>
#include "../world/player.hpp"
#include "../world/walk.hpp"
#include "check.hpp"

#include <cmath>
#include <vector>

using namespace Quattro;
using namespace Quattro::World;
using Net::gchar;
using Net::gint3;
using Net::gint5;
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
  // 82 (community name) only where the build reads it; 51 marks a
  // disconnect apart from leaving the level (50).
  std::string cn = gchar(kCommunityName) + gstring("guest");
  Net::Reader c1(cn), c2(cn);
  Player a, b;
  CHECK(apply_props(c1, a, true) == 0 && a.community.empty());
  CHECK(apply_props(c2, b, true, 82) == 1 && b.community == "guest");
  std::string leave = gchar(kJoinLeaveLevel) + gchar(0);
  Net::Reader lv(leave);
  Player l;
  apply_props(lv, l, true);
  CHECK(l.gone && !l.disconnected && q.disconnected);
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

void test_item_keys(const char* build, int sprite_after, int still_after) {
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
  const auto* profile = Net::find_profile(build);
  CHECK(profile);
  if (!profile) return;
  ItemKeys k(profile->carry_sprite_after, profile->carry_still_after);
  auto out = k.tick(p, kKeyS, 0, l, tables, types);
  CHECK(out.size() == 2 && gani_of(out) == "sword" && out[0].body.substr(out[0].body.size() - 2) == gchar(kSprite) + gchar(3));
  CHECK(out[1].id == 1 && out[1].body == board_modify(34, 32, 2, 2, {677, 678, 693, 694}));
  CHECK(l.tile(35, 33) == 694 && k.busy());
  for (int t = 1; t < ItemKeys::kSwordTicks; ++t) CHECK(k.tick(p, kKeyS, 0, l, tables, types).empty());
  out = k.tick(p, kKeyS, 0, l, tables, types);  // 0.25 s: idle; holding S does not swing again
  CHECK(gani_of(out) == "idle" && !k.busy());
  CHECK(k.tick(p, kKeyS, 0, l, tables, types).empty());

  // Spin: STATUS 0x40, release S then press again during the swing.
  p.status = ItemKeys::kStatusHasSpin;
  k.tick(p, 0, 0, l, tables, types);  // clear the held S from the swing above
  out = k.tick(p, kKeyS, 0, l, tables, types);
  CHECK(gani_of(out) == "sword" && k.busy());
  k.tick(p, 0, 0, l, tables, types);  // release
  out = k.tick(p, kKeyS, 0, l, tables, types);
  CHECK(gani_of(out) == "spin" && p.gani == "spin" && k.busy());
  // S during the spin is ignored.
  CHECK(k.tick(p, kKeyS, 0, l, tables, types).empty() && p.gani == "spin");
  k.tick(p, 0, 0, l, tables, types);  // release; ticks_ == 2
  for (int t = 3; t < ItemKeys::kSpinTicks; ++t) CHECK(k.tick(p, 0, 0, l, tables, types).empty());
  out = k.tick(p, 0, 0, l, tables, types);  // ticks_ == kSpinTicks: idle
  CHECK(gani_of(out) == "idle" && !k.busy());
  // Without the bit, S again during the swing does not spin.
  p.status = 0;
  k.tick(p, kKeyS, 0, l, tables, types);
  k.tick(p, 0, 0, l, tables, types);
  CHECK(k.tick(p, kKeyS, 0, l, tables, types).empty() && p.gani == "sword");  // ticks_ == 2
  for (int t = 3; t < ItemKeys::kSwordTicks; ++t) k.tick(p, 0, 0, l, tables, types);
  CHECK(gani_of(k.tick(p, 0, 0, l, tables, types)) == "idle");

  // A on the bush: immediate lift, then profile-specific carry and still ticks.
  set_tile(l, 34, 32, 2);
  set_tile(l, 35, 32, 3);
  set_tile(l, 34, 33, 18);
  set_tile(l, 35, 33, 19);
  k.tick(p, 0, 0, l, tables, types);
  out = k.tick(p, kKeyA, 0, l, tables, types);
  CHECK(out.size() == 2 && out[0].id == 1 && gani_of(out) == "lift" && k.carrying());
  CHECK(out[1].body.substr(out[1].body.size() - 2) == gchar(kCarrySprite) + gchar(static_cast<unsigned>(-1)));
  std::vector<std::string> seen;
  for (int t = 1; t <= still_after; ++t) {
    const auto packets = k.tick(p, 0, 0, l, tables, types);
    if (t < sprite_after) CHECK(packets.empty() && p.carry_sprite == -1 && p.gani == "lift");
    for (const auto& pk : packets) seen.push_back(std::to_string(t) + ":" + pk.body);
  }
  CHECK(seen.size() == 2 && seen[0] == std::to_string(sprite_after) + ":" + gchar(kCarrySprite) + gchar(1) && p.carry_sprite == 1);
  CHECK(k.carry_sprite() == 1 && carried_sprite(p.carry_sprite) == 261);
  CHECK(seen[1] == std::to_string(still_after) + ":" + gchar(kGani) + gstring("carrystill") && !k.busy() && k.carrying());
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

  // Lay mode: clear the tip, hold S then press A (same as Adventure: AttackHeld).
  // Pressing A and S together on one tick would swing first.
  set_tile(l, 34, 32, 0);
  set_tile(l, 35, 32, 0);
  set_tile(l, 34, 33, 0);
  set_tile(l, 35, 33, 0);
  p.rupees = 6;
  p.bombs = 5;
  p.sword_power = 0;  // no sword on S while entering lay
  p.dir = 3;          // right: laid item at (x+0.5+2, y+1)
  k.tick(p, 0, 0, l, tables, types);
  k.tick(p, kKeyS, 0, l, tables, types);  // hold S
  CHECK(k.tick(p, kKeyA | kKeyS, 0, l, tables, types).empty() && k.laying() && k.laying_item() == 0 &&
        k.busy());
  // A with S held again: next layable (blue rupee, needs 5).
  k.tick(p, kKeyS, 0, l, tables, types);  // release A, keep S
  CHECK(k.tick(p, kKeyA | kKeyS, 0, l, tables, types).empty() && k.laying_item() == 1);
  // A alone: lay blue rupee, ITEMADD + rupees prop.
  k.tick(p, 0, 0, l, tables, types);
  out = k.tick(p, kKeyA, 0, l, tables, types);
  CHECK(!k.laying() && p.rupees == 1 && out.size() == 2 && out[0].id == 12);
  CHECK(out[0].body == gchar(static_cast<unsigned>(std::lround((p.x + 2.5) * 2))) +
                           gchar(static_cast<unsigned>(std::lround((p.y + 1) * 2))) + gchar(1));
  CHECK(out[1].id == 2 && out[1].body == gchar(kRupees) + gint3(1));
  // Arrow leaves the lay mode without laying.
  p.rupees = 1;
  k.tick(p, kKeyS, 0, l, tables, types);
  CHECK(k.tick(p, kKeyA | kKeyS, 0, l, tables, types).empty() && k.laying() && k.laying_item() == 0);
  CHECK(k.tick(p, kKeyS, 1, l, tables, types).empty() && !k.laying() && p.rupees == 1);
  // Spinattack (24) is a floor item: laying it clears STATUS 0x40 and sends ITEMADD.
  p.status = ItemKeys::kStatusHasSpin;
  p.rupees = 0;
  p.bombs = 0;
  p.arrows = 0;
  p.power = 0;
  p.glove_power = 0;
  p.sword_power = 0;
  p.shield_power = 0;
  k.tick(p, 0, 0, l, tables, types);
  k.tick(p, kKeyS, 0, l, tables, types);
  CHECK(k.tick(p, kKeyA | kKeyS, 0, l, tables, types).empty() && k.laying_item() == 24);
  k.tick(p, 0, 0, l, tables, types);
  out = k.tick(p, kKeyA, 0, l, tables, types);
  CHECK(out.size() == 2 && out[0].id == 12);
  CHECK(out[0].body == gchar(static_cast<unsigned>(std::lround((p.x + 2.5) * 2))) +
                           gchar(static_cast<unsigned>(std::lround((p.y + 1) * 2))) + gchar(24));
  CHECK(p.status == 0 && out[1].body == gchar(kStatus) + gchar(0));

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
  // 1 px and then 3 px a tick lower; its shadow centred on the ground at
  // y 514.
  Effects e;
  e.throw_object(1, 480, 480, 3);
  auto ps = e.pieces();
  CHECK(ps.size() == 2 && ps[0].sprite == 0 && ps[0].x == 492 && ps[0].y == 514);
  CHECK(ps[1].sprite == 261 && ps[1].x == 488 && ps[1].y == 458);
  CHECK(e.tick().empty());
  ps = e.pieces();
  CHECK(ps.size() == 2 && ps[1].x == 504 && ps[1].y == 459);
  for (int t = 2; t <= Effects::kThrowTicks; ++t) CHECK(e.tick().empty());
  ps = e.pieces();
  CHECK(ps.size() == 2 && ps[1].x == 488 + 128 && ps[1].y == 458 + 23 && ps[0].x == 620 && ps[0].y == 514);
  // On the 9th tick it breaks into 4 leaves a step on; nothing is sent.
  CHECK(e.tick().empty());
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].sprite == 25 && ps[0].x == 630 && ps[0].y == 490 && ps[3].x == 650 && ps[3].y == 510);
  CHECK(ps[1].sprite == 25 && ps[2].sprite == 26);  // out of phase
  for (int t = 0; t < Effects::kLeafTicks; ++t) e.tick();
  CHECK(e.empty());

  // A pot breaks into shards, 97 on the right and 99 on the left, which
  // swap images every tick and spread 4 px a tick; a stone into nothing.
  e.throw_object(5, 0, 0, 2);
  for (int t = 0; t <= Effects::kThrowTicks; ++t) e.tick();
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].sprite == 99 && ps[1].sprite == 97);
  int x0 = ps[0].x;
  e.tick();
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].sprite == 98 && ps[1].sprite == 96 && ps[0].x == x0 - 4);
  for (int t = 1; t < Effects::kBreakTicks; ++t) e.tick();
  CHECK(e.empty());
  e.throw_object(3, 0, 0, 2);
  for (int t = 0; t <= Effects::kThrowTicks; ++t) e.tick();
  CHECK(e.empty());

  // putleaps: bush leaves at once; sign shards; stone / unmeasured kinds empty.
  e.put_leaps(0, 10, 12);
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].sprite == 25 && ps[0].x == 158 && ps[0].y == 188);
  for (int t = 0; t < Effects::kLeafTicks; ++t) e.tick();
  CHECK(e.empty());
  e.put_leaps(3, 2, 3);
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].sprite == 102 && ps[1].sprite == 100);
  for (int t = 0; t < Effects::kBreakTicks; ++t) e.tick();
  CHECK(e.empty());
  e.put_leaps(2, 0, 0);
  e.put_leaps(1, 0, 0);
  e.put_leaps(4, 0, 0);
  e.put_leaps(5, 0, 0);
  e.put_leaps(9, 0, 0);  // clamped to water; still unmeasured
  CHECK(e.empty());

  // A cut bush: 4 leaves on its tiles from the 4th tick, for 6 ticks.
  e.cut_bush(34, 32);
  for (int t = 0; t < Effects::kCutLeafDelay; ++t) {
    CHECK(e.pieces().empty() && !e.empty());
    e.tick();
  }
  ps = e.pieces();
  CHECK(ps.size() == 4 && ps[0].x == 542 && ps[0].y == 508 && ps[1].x == 562 && ps[1].y == 512);
  CHECK(ps[2].x == 542 && ps[2].y == 528 && ps[3].x == 562 && ps[3].y == 528);
  for (int t = 0; t < 3; ++t) e.tick();
  ps = e.pieces();
  CHECK(ps[3].x == 564 && ps[3].y == 532);  // right leaves fall from the 3rd tick
  for (int t = 3; t < Effects::kLeafTicks; ++t) e.tick();
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
  std::string five = gchar(kCarrySprite) + gchar(5);  // the Reader keeps a view
  Net::Reader r(five);
  apply_props(r, p, false);
  CHECK(p.carry_sprite == 5);
  std::string none = gchar(kCarrySprite) + gchar(static_cast<unsigned>(-1));
  Net::Reader r2(none);
  apply_props(r2, p, false);
  CHECK(p.carry_sprite == -1);
}

void test_floor_items() {
  FloorItems f;
  Player p;
  p.x = 30;
  p.y = 30;
  // Server ITEMADD: green gralat at (30, 30).
  f.add(30, 30, 0);
  CHECK(f.list().size() == 1 && f.list()[0].item == 0 && f.list()[0].life == FloorItems::kItemLife);
  CHECK(is_floor_item(0) && is_floor_item(24) && !is_floor_item(6));
  // First draw: bounce + shadow + sprite 136.
  auto ps = f.pieces(nullptr, nullptr);
  CHECK(ps.size() == 2 && ps[1].sprite == 136);
  CHECK(ps[1].x == 30 * 16 + 16 - 8);  // centred on (x+1)*16 with w 16
  // After four ticks, walk onto it offline: GiveItem +1 rupee.
  for (int t = 0; t < 4; ++t) CHECK(f.tick(p, false).empty());
  p.rupees = 0;
  auto out = f.tick(p, false);
  CHECK(out.empty() && f.empty() && p.rupees == 1);
  // Online pickup sends ITEMTAKE.
  f.add(30, 30, 0);
  for (int t = 0; t < 4; ++t) f.tick(p, true);
  out = f.tick(p, true);
  CHECK(out.size() == 1 && out[0].id == FloorItems::kPlItemTake && f.empty());
  CHECK(out[0].body == gchar(60) + gchar(60) + gchar(0));
  // Expire: initial life >= 100 (not permanent); ages out → ITEMDEL.
  f.add(10, 12, 1, 100);
  for (int t = 0; t < 100; ++t) CHECK(f.tick(p, true).empty());
  out = f.tick(p, true);
  CHECK(out.size() == 1 && out[0].id == FloorItems::kPlItemDel &&
        out[0].body == gchar(20) + gchar(24) && f.empty());
  // Permanent (initial life < 100): no take, no ITEMDEL; still ages out locally.
  f.add(5, 5, 0, 50);
  CHECK(f.list()[0].permanent);
  for (int t = 0; t < 60; ++t) CHECK(f.tick(p, true).empty());
  CHECK(f.empty());
  f.add(5, 5, 0, 50);
  f.remove_at(5, 5);
  CHECK(f.empty());
  // Blink: after life falls below 37 and is odd, no pieces (far from player).
  f.add(0, 0, 0);
  for (int t = 0; t < FloorItems::kItemLife - 35; ++t) f.tick(p, true);
  CHECK(f.list()[0].life == 35 && f.pieces(nullptr, nullptr).empty());
  f.clear();
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


void test_weapon_list() {
  WeaponList w;
  CHECK(w.selected() == nullptr && !w.any_shown());
  CHECK(w.add("-System") && w.selected_index() == 0 && !w.any_shown());  // nothing else to pick
  CHECK(w.add_default(8) && w.selected()->name == "Bomb" && w.selected()->image == "wbomb1.png" && w.selected()->item == 8);
  CHECK(!w.add_default(5) && !w.add("Bomb"));  // a heart is no weapon; a name the list has is skipped
  CHECK(w.add_default(7) && w.selected()->name == "Bow" && w.selected_index() == 2);
  CHECK(w.add("Stick", "stick.png") && w.selected_index() == 3);
  w.select_next();  // wraps past the hidden -System to Bomb
  CHECK(w.selected()->name == "Bomb");
  w.select(3);
  w.remove("Stick");  // the index is gone: the new last entry
  CHECK(w.selected()->name == "Bow");
  w.select(1);
  w.remove("-System");  // index 1 still exists
  CHECK(w.selected_index() == 1 && w.selected()->name == "Bow");
  CHECK(default_weapon_name(23) == "Joltbomb" && default_weapon_image(22) == "wbowi4.png");
  w.clear();
  CHECK(w.list().empty() && w.selected() == nullptr);
}

void test_combat() {
  std::string d = items_dat();
  ObjectTables tables;
  TileTypes types;
  std::string err;
  CHECK(read_object_tables(d, tables) && read_arrays_dat(d, types, err));
  Files::Level l = open_level();
  // A bush one step past the bomb's corner, and a wall in the arrow's way.
  set_tile(l, 34, 32, 2);
  set_tile(l, 35, 32, 3);
  set_tile(l, 34, 33, 18);
  set_tile(l, 35, 33, 19);
  set_tile(l, 36, 32, 5);

  Player p;
  p.x = 31;
  p.y = 30;
  p.dir = 3;
  p.bombs = 1;
  Combat c;
  auto out = c.lay_bomb(p, 1);  // 1.5 tiles right of the body: (33, 31)
  CHECK(out.size() == 1 && out[0].id == 4 && out[0].body == gchar(66) + gchar(62) + gchar(9) + gchar(55));
  CHECK(p.bombs == 0 && c.bombs().size() == 1 && c.bombs()[0].mine);
  CHECK(c.lay_bomb(p, 1).empty());  // none left
  for (int t = 1; t < Combat::kFuse; ++t) CHECK(c.tick(l, tables, types).empty());
  out = c.tick(l, tables, types);  // the fuse ends: explosion, then the bush is cut
  CHECK(out.size() == 2 && out[0].id == 27 && out[0].body == gchar(2) + gchar(66) + gchar(62) + gchar(9));
  CHECK(out[1].id == 1 && out[1].body == board_modify(34, 32, 2, 2, {677, 678, 693, 694}));
  CHECK(l.tile(34, 32) == 677 && c.bombs().empty() && c.blasts().size() == 1);
  for (int t = 0; t < Combat::kBlastTicks; ++t) c.tick(l, tables, types);
  CHECK(c.blasts().empty());

  p.arrows = 1;
  out = c.shoot(p, 0);  // from (33.5, 31.75), right
  CHECK(out.size() == 1 && out[0].id == 9 && out[0].body == gchar(67) + gchar(64) + gchar(11) + gchar(110) + gchar(1));
  CHECK(p.arrows == 0 && c.shoot(p, 0).empty());
  c.tick(l, tables, types);
  c.tick(l, tables, types);
  CHECK(c.shots().size() == 1 && c.shots()[0].x == 35.5);
  c.tick(l, tables, types);  // its middle reaches the wall at (36, 32)
  CHECK(c.shots().empty());

  // Others' bombs, shots and explosions from the server.
  CHECK(c.on_message(11, gshort(5) + gchar(20) + gchar(40) + gchar(10) + gchar(30)));
  CHECK(c.bombs().size() == 1 && !c.bombs()[0].mine && c.bombs()[0].x == 10 && c.bombs()[0].power == 2 && c.bombs()[0].fuse == 30);
  CHECK(c.on_message(12, gchar(20) + gchar(40)) && c.bombs().empty());
  CHECK(c.on_message(19, gshort(5) + gchar(20) + gchar(40) + gchar(9) + gchar(108) + gchar(1)));
  CHECK(c.shots().size() == 1 && c.shots()[0].dir == 1 && c.shots()[0].kind == 0 && !c.shots()[0].mine);
  CHECK(c.on_message(36, gshort(5) + gchar(2) + gchar(20) + gchar(40) + gchar(11)));
  CHECK(c.blasts().size() == 1 && c.blasts()[0].power == 3 && !c.blasts()[0].mine);
  CHECK(!c.on_message(13, ""));
}

void test_health() {
  Files::Level l = open_level();
  TileTypes types = test_types();
  Player p;
  p.x = 30;
  p.y = 30;
  p.max_power = 3;
  p.power = 6;
  Health h;
  // Half a heart from the west: hearts sent, 31 ticks of hurt, 5 tiles east.
  auto out = h.hit(p, 0.5, 1, 0);
  CHECK(out.size() == 1 && out[0].id == 2 && out[0].body == gchar(kCurPower) + gchar(5) && p.gani == "hurt");
  CHECK(h.hit(p, 0.5, 1, 0).empty());  // no second hit while hurt
  for (int t = 0; t < Health::kHurtTicks - 1; ++t) h.tick(p, l, types);
  CHECK(p.x == 35 && p.y == 30 && h.hurting() && p.gani == "hurt");
  h.tick(p, l, types);
  CHECK(!h.hurting() && p.gani == "idle");
  // A wall stops the knockback.
  set_tile(l, 37, 31, 5);
  h.hit(p, 0.5, 1, 0);
  for (int t = 0; t < Health::kHurtTicks; ++t) h.tick(p, l, types);
  CHECK(p.x == 35);
  // AP 100 cannot be hurt.
  p.ap = 100;
  CHECK(h.hit(p, 1, 0, 1).empty());
  p.ap = 50;

  // Another player's swing: 4 tiles ahead counts, once a second.
  std::map<int, Player> others;
  Player a;
  a.x = 35;
  a.y = 26;
  a.dir = 2;
  a.gani = "sword";
  a.sword_power = 2;
  others[9] = a;
  out = h.check_swords(p, others);
  CHECK(out.size() == 1 && p.power == 2);
  for (int t = 0; t < Health::kHurtTicks; ++t) h.tick(p, l, types);
  CHECK(h.check_swords(p, others).empty());  // within a second of the last
  for (int t = 0; t < Health::kSwingGap; ++t) h.tick(p, l, types);
  // A spin hits beside the attacker too (every facing), not only ahead.
  others[9].gani = "spin";
  others[9].sword_power = 1;  // half a heart from power 2
  others[9].x = p.x + 2;
  others[9].y = p.y;
  others[9].dir = 2;  // facing down; victim is to the right
  out = h.check_swords(p, others);
  CHECK(out.size() == 1 && p.power == 1);
  for (int t = 0; t < Health::kHurtTicks; ++t) h.tick(p, l, types);
  for (int t = 0; t < Health::kSwingGap; ++t) h.tick(p, l, types);
  others[9].gani = "sword";
  others[9].x = p.x;
  others[9].y = p.y - 4;
  others[9].sword_power = 6;  // three hearts: dead, and the claim names player 9
  p.power = 6;
  out = h.check_swords(p, others);
  CHECK(out.size() == 2 && out[0].body == gchar(kCurPower) + gchar(0) && out[1].id == 14 && out[1].body == gshort(9));
  CHECK(h.dead() && p.gani == "dead" && h.hit(p, 1, 0, 0).empty());
  out = h.respawn(p, 30, 31, "start.nw");  // AP 50: every heart back
  CHECK(!h.dead() && p.power == 6 && p.x == 30 && p.y == 31 && p.gani == "idle");
  CHECK(out.size() == 2 && out[1].id == 0 && out[1].body == gchar(60) + gchar(62) + "start.nw");

  // HURTPLAYER: from a known player within 10 tiles; dx, dy as (v + 4) * 16.
  Health h2;
  others[9].x = 32;
  others[9].y = 31;
  out = h2.on_hurt_player(p, gshort(9) + gchar(0x40) + gchar(0x50) + gchar(2), others);
  CHECK(out.size() == 1 && p.power == 4);
  Health h3;
  CHECK(h3.on_hurt_player(p, gshort(8) + gchar(0x40) + gchar(0x40) + gchar(2), others).empty());  // unknown
}

void test_hits() {
  std::string d = items_dat();
  ObjectTables tables;
  CHECK(read_object_tables(d, tables));
  Player me;
  me.x = 30;
  me.y = 30;
  Combat c;
  std::vector<Packet> back;
  // A blast piece 2 tiles above a bomb at (29.5, 29): the arm's piece at
  // (30.5, 28) is no hit, the centre (30.5, 30) is a tile off on y: none;
  // a bomb at (30.5, 31) puts its centre at the body's centre.
  CHECK(c.on_message(36, gshort(5) + gchar(2) + gchar(61) + gchar(62) + gchar(1)));
  auto hits = c.hits_on(me, tables, back);
  CHECK(hits.size() == 1 && hits[0].hearts == 0.5 && hits[0].pvp);
  c.clear();
  CHECK(c.on_message(36, gshort(5) + gchar(2) + gchar(61) + gchar(62) + gchar(3)));
  CHECK(c.hits_on(me, tables, back)[0].hearts == 1.0);
  c.clear();
  // Another's arrow over the body hurts and goes; facing it with shield 2
  // sends it back as this player's own.
  CHECK(c.on_message(19, gshort(5) + gchar(62) + gchar(62) + gchar(1) + gchar(108) + gchar(1)));
  hits = c.hits_on(me, tables, back);
  CHECK(hits.size() == 1 && hits[0].kx == -1 && hits[0].pvp && c.shots().empty());
  me.dir = 3;
  me.shield_power = 2;
  CHECK(c.on_message(19, gshort(5) + gchar(62) + gchar(62) + gchar(1) + gchar(108) + gchar(1)));
  CHECK(c.hits_on(me, tables, back).empty() && back.size() == 1 && back[0].id == 9);
  CHECK(c.shots().size() == 1 && c.shots()[0].mine && c.shots()[0].dir == 3);
}

void test_item_list() {
  WeaponList w;
  w.add("-System");
  w.add_default(8);  // image 30 x 20
  w.add("LongNameWeapon");  // no image: 32 x 32
  w.add_default(7);
  auto img = [](const std::string& n) { return n == "wbomb1.png" ? std::pair<int, int>{30, 20} : std::pair<int, int>{0, 0}; };
  auto text = [](const std::string& t) { return static_cast<int>(t.size()) * 8; };
  // 640 wide: the cells run from x 48 to 592.
  auto cells = layout_items(w, 640, 480, img, text);
  CHECK(cells.size() == 3 && cells[0].index == 1);  // -System is not listed
  CHECK(cells[0].x == 48 && cells[0].y == 112 && cells[0].w == 42 && cells[0].h == 20 + 16 + 15);
  CHECK(cells[1].x == 90 && cells[1].w == 14 * 8 + 10 && cells[1].h == 32 + 16 + 15);
  CHECK(move_in_items(cells, 3, 1) == 2 && move_in_items(cells, 2, 1) == 1 && move_in_items(cells, 1, 1) == -1);
  CHECK(move_in_items(cells, 1, 3) == 2 && move_in_items(cells, 1, 2) == -1);
  // A narrow window wraps: Bow goes under Bomb, and down from Bomb takes it.
  cells = layout_items(w, 260, 480, img, text);
  CHECK(cells.size() == 3 && cells[2].x == 48 && cells[2].y == 112 + 63);
  CHECK(move_in_items(cells, 1, 2) == 3 && move_in_items(cells, 3, 0) == 1);
}
}  // namespace

// Own props as real 4.20r8, 5.24r4 and 6.03r7 read them, from injected
// packets (Graal_analysis protocol/probe-results.tsv, 2026-11-18). Each
// stream ends with a bombs "canary" that must land.
void test_own_props_probed() {
  using Net::OwnProps;
  auto run = [](OwnProps rules, const std::string& s, Player& p) {
    Net::Reader r(s);
    return apply_own_props(r, p, rules);
  };
  const std::string canary = gchar(kBombs) + gchar(11);
  {  // 6.03r7: 83 is five bytes and sets the gralat count prop 3 sets
    Player p;
    run(OwnProps::k6x, gchar(83) + gint5(1234) + canary, p);
    CHECK(p.rupees == 1234 && p.bombs == 11);
    run(OwnProps::k6x, gchar(83) + gint5(999999999) + gchar(kBombs) + gchar(12), p);
    CHECK(p.rupees == 999999999 && p.bombs == 12);
    // Over 999,999,999 is ignored, not clamped, and the rest is still read.
    run(OwnProps::k6x, gchar(83) + gint5(1000000000) + gchar(kBombs) + gchar(13), p);
    CHECK(p.rupees == 999999999 && p.bombs == 13);
    run(OwnProps::k6x, gchar(83) + gint5(34359738367ULL) + gchar(kBombs) + gchar(14), p);
    CHECK(p.rupees == 999999999 && p.bombs == 14);
    run(OwnProps::k6x, gchar(kRupees) + gint3(4321) + gchar(kBombs) + gchar(16), p);
    CHECK(p.rupees == 4321 && p.bombs == 16);
  }
  {  // 6.03r7: 77 five bytes, 78 to 80 two, 81 one, 82 a string
    Player p;
    std::string s = gchar(77) + gint5(123456) + gchar(kX2) + gshort(320) + gchar(kY2) + gshort(320) +
                    gchar(kZ2) + gshort(64) + gchar(81) + gchar(1) + gchar(kCommunityName) + gstring("Probe") + canary;
    run(OwnProps::k6x, s, p);
    CHECK(p.x == 10 && p.y == 10 && p.z == 2 && p.community == "Probe" && p.bombs == 11);
  }
  {  // no case (33, 50, 51, 53, 75, 76, 84 and up): the id and one byte
    for (int id : {33, 50, 51, 53, 75, 76, 84, 90, 200}) {
      for (OwnProps rules : {OwnProps::k4x, OwnProps::k5x, OwnProps::k6x}) {
        Player p;
        run(rules, gchar(static_cast<unsigned>(id)) + gchar(1) + canary, p);
        CHECK(p.bombs == 11);
        CHECK(!p.gone);  // 50 and 51 do nothing on the own stream
      }
    }
  }
  {  // a longer value loses only the rest of that message
    Player p;
    run(OwnProps::k6x, gchar(90) + gint3(300000) + canary, p);
    CHECK(p.bombs != 11);
    run(OwnProps::k6x, gchar(kBombs) + gchar(21), p);
    CHECK(p.bombs == 21);
  }
  {  // 4.20r8 and 5.24r4 have no case for 77 or 83; 4.20r8 none for 82
    for (OwnProps rules : {OwnProps::k4x, OwnProps::k5x}) {
      Player p;
      run(rules, gchar(77) + gchar(1) + gchar(83) + gchar(1) + canary, p);
      CHECK(p.bombs == 11 && p.rupees == 0);
    }
    Player p;
    run(OwnProps::k4x, gchar(kCommunityName) + gchar(1) + canary, p);
    CHECK(p.bombs == 11 && p.community.empty());
    Player q;
    run(OwnProps::k5x, gchar(kCommunityName) + gstring("x") + canary, q);
    CHECK(q.bombs == 11 && q.community == "x");
  }
  {  // the profiles
    CHECK(Net::find_profile("6.03r7 Linux")->own_props == OwnProps::k6x);
    CHECK(Net::find_profile("5.24r4")->own_props == OwnProps::k5x);
    CHECK(Net::find_profile("4.20r8")->own_props == OwnProps::k4x);
  }
}


// The 4.x / 5.x NPC prop parser: the values it reads, and an id outside
// 0-47 and 53-77 ending the stream with what came before kept.
void test_npc_props() {
  using namespace Quattro::World;
  using Quattro::Net::gchar;
  using Quattro::Net::gshort;
  using Quattro::Net::gstring;
  ServerNpc n;
  std::string s = npc_prop_string(kNpcImage, "door.png") + npc_prop_char(kNpcX, 61) + npc_prop_char(kNpcY, 20) +
                  gchar(kNpcImagePart) + gshort(32) + gshort(16) + gchar(48) + gchar(32) +
                  gchar(kNpcHeadImage) + gchar(100 + 9) + "head9.png" + gchar(kNpcColors) + gchar(1) + gchar(2) +
                  gchar(3) + gchar(4) + gchar(5) + npc_prop_string(kNpcGattrib1, "a1") +
                  npc_prop_string(kNpcGattrib10, "a10") + gchar(kNpcScript) + gshort(3) + "abc" +
                  npc_prop_char(kNpcVisFlags, 0);
  CHECK(apply_npc_props(n, s));
  CHECK(n.image == "door.png" && n.x == 30.5 && n.y == 10);
  CHECK(n.has_part && n.part_x == 32 && n.part_y == 16 && n.part_w == 48 && n.part_h == 32);
  CHECK(n.head == "head9.png" && n.colors[4] == 5 && n.attr[1] == "a1" && n.attr[10] == "a10");
  CHECK(n.gs1_text == "abc" && !n.visible() && !n.character());
  // X2 / Y2, then 48 ends it: the nickname after it is not read.
  ServerNpc m;
  std::string s2 = gchar(kNpcX2) + gshort(to_pixels2(12.5)) + gchar(kNpcY2) + gshort(to_pixels2(7)) +
                   npc_prop_string(kNpcGani, "walk") + gchar(48) + npc_prop_string(kNpcNickname, "x");
  CHECK(!apply_npc_props(m, s2));
  CHECK(m.x == 12.5 && m.y == 7 && m.gani == "walk" && m.character() && m.nickname.empty());
}

int main() {
  test_npc_props();
  test_pixels2();
  test_own_props();
  test_own_props_probed();
  test_other_props();
  test_sending();
  test_arrays_dat();
  test_walls();
  test_push();
  test_item_keys("6.03r7", 6, 8);
  test_item_keys("6.01r1", 4, 6);
  test_item_keys("4.04r2", 4, 6);
  test_effects();
  test_floor_items();
  test_carry_walk();
  test_weapon_list();
  test_combat();
  test_health();
  test_hits();
  test_item_list();
  TEST_MAIN_END();
}
