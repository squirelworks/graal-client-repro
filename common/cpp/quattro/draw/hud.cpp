#include "hud.hpp"

#include <algorithm>
#include <string>

namespace Quattro::Draw {

using Torque::Gui::Image;
using Torque::Gui::Rect;

namespace {

// state.png positions.
constexpr Rect kHeart{0, 0, 40, 44}, kHalfHeart{40, 0, 30, 44};
constexpr Rect kSmallHeart{80, 0, 31, 33}, kSmallHalfHeart{111, 0, 24, 33};
constexpr Rect kTab{202, 0, 22, 30};
constexpr Rect kMpFrame{0, 49, 130, 22}, kMpFill{0, 71, 100, 10};
constexpr Rect kApFrame{0, 97, 130, 22}, kApFill{0, 119, 100, 10};
constexpr int kDigitsY = 81, kDigitH = 16, kDigitCell = 14, kDigitAdvance = 12;
// The counter icons, drawn at their sheet position plus (194, -3).
constexpr Rect kGralat{80, 32, 16, 16}, kBomb{136, 32, 16, 16}, kArrow{184, 32, 16, 16};
constexpr int kIconDx = 194, kIconDy = -3, kNumberY = 48;
// A number's first digit is at centre - 6 * digits.
constexpr int kGralatC = 280, kBombC = 332, kArrowC = 380;
// The S slot: swordN.png from (94, 36), 28 x 28, at (105, 31). The A slot:
// the glove's 28 x 32 cell in sprites.png at (40, 29), from power 2.
constexpr Rect kSwordSrc{94, 36, 28, 28};
constexpr int kSwordX = 105, kSwordY = 31;
constexpr Rect kGlove2{28, 212, 28, 32}, kGlove3{0, 212, 28, 32};
constexpr int kGloveX = 40, kGloveY = 29;

// Client positions.
constexpr int kTabX[3] = {15, 80, 145}, kTabY = 30;
constexpr int kBarX = 15, kApY = 65, kMpY = 90, kFillDx = 22, kFillDy = 6;
constexpr int kHeartsFromRight = 198, kHeartY = 24, kHeartStep = 45;
constexpr int kSmallStep = 35, kSmallRowStep = 20, kFiveHeartsDrop = 10;
constexpr int kRowLen[4] = {5, 6, 5, 4}, kRowDx[4] = {0, -18, 0, 17};

}  // namespace

std::vector<Hud::HeartSlot> Hud::heart_slots(int half_hearts, int width, bool& small) {
  std::vector<HeartSlot> out;
  int n = (std::max(0, half_hearts) + 1) / 2;
  bool half = half_hearts % 2 == 1 && n <= 20;
  int left = width - kHeartsFromRight;
  small = n > 4;
  if (!small) {
    for (int i = 0; i < n; ++i) out.push_back({left + i * kHeartStep, kHeartY, half && i == n - 1});
    return out;
  }
  n = std::min(n, 20);
  for (int row = 0, i = 0; row < 4 && i < n; ++row) {
    // At 5 and 5.5 hearts the block sits 10 px lower.
    int y = kHeartY + row * kSmallRowStep + (half_hearts / 2 == 5 ? kFiveHeartsDrop : 0);
    for (int k = 0; k < kRowLen[row] && i < n; ++k, ++i)
      out.push_back({left + kRowDx[row] + k * kSmallStep, y, half && i == n - 1});
  }
  return out;
}

std::string Hud::counter_text(int value, bool two_digits) {
  std::string t = std::to_string(std::max(0, value));
  if (!two_digits) return t;
  if (t.size() < 2) t = "0" + t;
  return t.substr(0, 2);
}

void Hud::draw_number(Torque::Gui::Canvas& c, const Image& sheet, const std::string& text, int centre_x,
                      int y) const {
  int x = centre_x - 6 * static_cast<int>(text.size());
  for (char ch : text) {
    c.blit(sheet, {(ch - '0') * kDigitCell, kDigitsY, kDigitCell, kDigitH}, x, y);
    x += kDigitAdvance;
  }
}

void Hud::draw(Torque::Gui::Canvas& c, const HudState& s) const {
  const Image* sheet = assets_ ? assets_->image("state.png") : nullptr;
  if (!sheet || sheet->width < 224 || sheet->height < 129) return;
  for (int x : kTabX) c.blit(*sheet, kTab, x, kTabY);
  c.blit(*sheet, kApFrame, kBarX, kApY);
  int ap = std::clamp(s.ap, 0, 100);
  if (ap) c.blit(*sheet, {kApFill.x, kApFill.y, ap, kApFill.height}, kBarX + kFillDx, kApY + kFillDy);
  if (s.mp > 0) {
    c.blit(*sheet, kMpFrame, kBarX, kMpY);
    int mp = std::min(s.mp, 100);
    c.blit(*sheet, {kMpFill.x, kMpFill.y, mp, kMpFill.height}, kBarX + kFillDx, kMpY + kFillDy);
  }
  if (s.glove_power >= 2) {
    if (const Image* sprites = assets_->image("sprites.png"))
      c.blit(*sprites, s.glove_power >= 3 ? kGlove3 : kGlove2, kGloveX, kGloveY);
  }
  if (s.sword_power > 0) {
    std::string name = s.sword_image.empty() ? "sword" + std::to_string(s.sword_power) + ".png" : s.sword_image;
    if (const Image* sword = assets_->image(name)) c.blit(*sword, kSwordSrc, kSwordX, kSwordY);
  }
  struct Counter {
    Rect icon;
    int value, centre;
    bool two;
  } counters[3] = {{kGralat, s.gralats, kGralatC, false}, {kBomb, s.bombs, kBombC, true},
                   {kArrow, s.arrows, kArrowC, true}};
  for (const auto& k : counters) {
    c.blit(*sheet, k.icon, k.icon.x + kIconDx, k.icon.y + kIconDy);
    draw_number(c, *sheet, counter_text(k.value, k.two), k.centre, kNumberY);
  }
  bool small = false;
  for (const auto& h : heart_slots(s.half_hearts, c.width(), small)) {
    Rect src = small ? (h.half ? kSmallHalfHeart : kSmallHeart) : (h.half ? kHalfHeart : kHeart);
    c.blit(*sheet, src, h.x, h.y);
  }
}

}  // namespace Quattro::Draw
