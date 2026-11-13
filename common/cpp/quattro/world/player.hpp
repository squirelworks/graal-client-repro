// Players as the 6.x program's game connection fills them (the original's
// TServerPlayer): the prop stream of 9 (own) and 8 (others), and the props
// the client sends with 2.
//
// The prop table is Graal_analysis protocol/player-props.md as the 2.22
// parser reads it, plus X2/Y2/Z2 (78 to 80), which the lab saw 5.x and 6.x
// send (protocol/v6-props.md, protocol/v5v6-lab-play.md). It is the same
// table the graal-6.03r7 Pascal folder reads; no 6.x prop parser was read
// from the binary.
//
// Movement: the lab saw 6.03r7 send only the coordinate that changed, as X2
// or Y2, every 50 ms while walking.
#pragma once

#include "../net/gtypes.hpp"

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

namespace Quattro::World {

enum Prop : int {
  kNickname = 0, kMaxPower = 1, kCurPower = 2, kRupees = 3, kArrows = 4, kBombs = 5, kGlovePower = 6,
  kBombPower = 7, kSwordPower = 8, kShieldPower = 9, kGani = 10, kHeadGif = 11, kCurChat = 12,
  kColors = 13, kId = 14, kX = 15, kY = 16, kSprite = 17, kStatus = 18, kCarrySprite = 19,
  kCurLevel = 20, kHorseGif = 21, kHorseBushes = 22, kEffectColors = 23, kCarryNpc = 24,
  kApCounter = 25, kMagicPoints = 26, kKills = 27, kDeaths = 28, kOnlineSecs = 29, kIpAddr = 30,
  kUdpPort = 31, kAlignment = 32, kAdditFlags = 33, kAccountName = 34, kBodyImg = 35, kRating = 36,
  kGattrib1 = 37, kGattrib5 = 41, kAttachNpc = 42, kGmapX = 43, kGmapY = 44, kZ = 45,
  kGattrib6 = 46, kGattrib9 = 49, kJoinLeaveLevel = 50, kConnected = 51, kLanguage = 52,
  kStatusMsg = 53, kGattrib10 = 54, kGattrib30 = 74, kOsType = 75, kCodePage = 76,
  kX2 = 78, kY2 = 79, kZ2 = 80,
};

struct Player {
  int id = -1;
  std::string nickname, account, level, gani, head, body, chat, language, os_type;
  int max_power = 0, power = 0, rupees = 0, arrows = 0, bombs = 0;
  int sword_power = 0, shield_power = 0, glove_power = 0, bomb_power = 0;
  int ap = 50, mp = 0;  // alignment points 0..100, magic points
  std::string sword_image, shield_image;
  std::array<int, 5> colors{};
  double x = 30, y = 30;
  int z = 0;
  int sprite = 2, dir = 2, status = 0, gmap_x = 0, gmap_y = 0;
  int code_page = 0;
  int carry_sprite = -1;  // what is carried over the head, -1 none
  std::array<std::string, 31> attr;  // gattrib 1..30
  bool gone = false;
};

// Applies a prop stream. Stops at an id the parser does not accept or does
// not know the size of (the rest of the stream cannot be read). Returns
// the number of props applied.
int apply_props(Net::Reader& r, Player& p, bool other);

// X2/Y2/Z2 encoding: pixels (1/16 tile) times two, the low bit a sign.
unsigned to_pixels2(double tiles);
double from_pixels2(unsigned v);

// The props a 6.x client sends once logged in: nickname, colours,
// language, OS type, then the position as X2/Y2.
std::string initial_props(const Player& p, const std::string& os_type);

// Tracks what was last sent and builds the diff for this tick (empty when
// nothing changed).
class MoveSender {
 public:
  void reset(const Player& p) {
    x_ = p.x;
    y_ = p.y;
    dir_ = p.dir;
    gani_ = p.gani;
  }
  std::string diff(const Player& p);
  // The gani and facing were sent another way (the item keys).
  void gani_sent(const Player& p) {
    dir_ = p.dir;
    gani_ = p.gani;
  }

 private:
  double x_ = 0, y_ = 0;
  int dir_ = -1;
  std::string gani_;
};

}  // namespace Quattro::World
