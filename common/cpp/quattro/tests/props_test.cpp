// The player prop stream and the props the client sends.
#include "../world/player.hpp"
#include "check.hpp"

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

}  // namespace

int main() {
  test_pixels2();
  test_own_props();
  test_other_props();
  test_sending();
  TEST_MAIN_END();
}
