#include "player.hpp"

#include <cmath>

namespace Quattro::World {

using Net::gchar;
using Net::gshort;
using Net::gstring;

unsigned to_pixels2(double tiles) {
  long p = std::lround(tiles * 16);
  return p < 0 ? static_cast<unsigned>(((-p) << 1) | 1) : static_cast<unsigned>(p << 1);
}

double from_pixels2(unsigned v) {
  double t = static_cast<double>(v >> 1) / 16.0;
  return (v & 1) ? -t : t;
}

namespace {

bool rejected(int prop, bool other, int last_prop) {
  // The ids each 2.22 parser accepts (protocol/player-props.md).
  if (other)
    return prop == 1 || (prop >= 3 && prop <= 7) || prop == 14 || prop == 22 || (prop >= 25 && prop <= 29) ||
           prop == 77 || prop > last_prop;
  return prop == 50 || prop == 51 || prop == 53 || prop == 77 || prop > last_prop;
}

// Reads one prop's value into p. False for an id whose size is not known
// (nothing is read).
bool apply_one(int prop, Net::Reader& r, Player& p) {
  switch (prop) {
    case kNickname: p.nickname = r.gstring(); break;
    case kMaxPower: p.max_power = static_cast<int>(r.gchar()); break;
    case kCurPower: p.power = static_cast<int>(r.gchar()); break;
    case kRupees: p.rupees = static_cast<int>(r.gint3()); break;
    case kArrows: p.arrows = static_cast<int>(r.gchar()); break;
    case kBombs: p.bombs = static_cast<int>(r.gchar()); break;
    case kGlovePower: p.glove_power = static_cast<int>(r.gchar()); break;
    case kBombPower: p.bomb_power = static_cast<int>(r.gchar()); break;
    case kSwordPower: {  // c(power + 30) + image, or c(power)
      int v = static_cast<int>(r.gchar());
      if (v > 4) {
        p.sword_power = v - 30;
        p.sword_image = r.gstring();
      } else {
        p.sword_power = v;
      }
      break;
    }
    case kShieldPower: {  // c(power + 10) + image, or c(power)
      int v = static_cast<int>(r.gchar());
      if (v > 3) {
        p.shield_power = v - 10;
        p.shield_image = r.gstring();
      } else {
        p.shield_power = v;
      }
      break;
    }
    case kGani: {
      std::string g = r.gstring();
      if (g.size() > 5 && g.compare(g.size() - 5, 5, ".gani") == 0) g.resize(g.size() - 5);
      if (!g.empty()) p.gani = g;
      break;
    }
    case kHeadGif: {
      unsigned v = r.gchar();
      if (v >= 100) {
        std::string s;
        for (unsigned i = 0; i < v - 100 && !r.at_end(); ++i) s.push_back(static_cast<char>(r.gchar() + 32));
        p.head = s;
      } else {
        p.head = "head" + std::to_string(v) + ".png";
      }
      break;
    }
    case kCurChat: p.chat = r.gstring(); break;
    case kColors:
      for (int& c : p.colors) c = static_cast<int>(r.gchar());
      break;
    case kId: p.id = static_cast<int>(r.gshort()); break;
    case kX: p.x = r.gchar() / 2.0; break;
    case kY: p.y = r.gchar() / 2.0; break;
    case kSprite:
      p.sprite = static_cast<int>(r.gchar());
      p.dir = p.sprite % 4;
      break;
    case kStatus: p.status = static_cast<int>(r.gchar()); break;
    case kGmapX: p.gmap_x = static_cast<int>(r.gchar()); break;
    case kGmapY: p.gmap_y = static_cast<int>(r.gchar()); break;
    case kZ: p.z = static_cast<int>(r.gchar()) - 50; break;
    case kMagicPoints: p.mp = static_cast<int>(r.gchar()); break;
    case kAlignment: p.ap = static_cast<int>(r.gchar()); break;
    case kCarrySprite: {
      int v = static_cast<int>(r.gchar());
      p.carry_sprite = v >= 128 ? v - 256 : v;
      break;
    }
    case kHorseBushes: case kEffectColors:
    case kAdditFlags: case kStatusMsg:
      r.gchar();
      break;
    case kJoinLeaveLevel:
      if (r.gchar() == 0) p.gone = true;
      break;
    case kCurLevel: p.level = r.gstring(); break;
    case kAccountName: p.account = r.gstring(); break;
    case kBodyImg: p.body = r.gstring(); break;
    case kLanguage: p.language = r.gstring(); break;
    case kOsType: p.os_type = r.gstring(); break;
    case kCommunityName: p.community = r.gstring(); break;
    case kListCategory: r.gchar(); break;
    case kCodePage: p.code_page = static_cast<int>(r.gint3()); break;
    case kX2: p.x = from_pixels2(r.gshort()); break;
    case kY2: p.y = from_pixels2(r.gshort()); break;
    case kZ2: p.z = static_cast<int>(std::lround(from_pixels2(r.gshort()))); break;
    case kCarryNpc: case kKills: case kDeaths: case kOnlineSecs: case kUdpPort: case kRating:
      r.gint3();
      break;
    case kApCounter: r.gshort(); break;
    case kIpAddr: r.gint5(); break;
    case kAttachNpc:
      r.gchar();
      r.gint3();
      break;
    case kConnected:
      p.gone = true;
      p.disconnected = true;
      if (!r.at_end()) r.gchar();
      break;
    default:
      if (prop >= kGattrib1 && prop <= kGattrib5) {
        p.attr[static_cast<size_t>(prop - kGattrib1 + 1)] = r.gstring();
      } else if (prop >= kGattrib6 && prop <= kGattrib9) {
        p.attr[static_cast<size_t>(prop - kGattrib6 + 6)] = r.gstring();
      } else if (prop >= kGattrib10 && prop <= kGattrib30) {
        p.attr[static_cast<size_t>(prop - kGattrib10 + 10)] = r.gstring();
      } else if (prop == kHorseGif) {
        r.gstring();
      } else {
        return false;
      }
  }
  return true;
}

// Whether a 4.x to 6.x own-prop parser has a case for the id (probe
// results: 33, 50, 51, 53, 75 and 76 have none on any of the three).
bool own_case(int prop, Net::OwnProps rules) {
  using Net::OwnProps;
  switch (prop) {
    case kAdditFlags: case kJoinLeaveLevel: case kConnected: case kStatusMsg: case kOsType: case kCodePage:
      return false;
    case 77: case 83: return rules == OwnProps::k6x;
    case kCommunityName: return rules == OwnProps::k5x || rules == OwnProps::k6x;
    default: return prop <= kListCategory;
  }
}

}  // namespace

int apply_props(Net::Reader& r, Player& p, bool other, int last_prop) {
  int applied = 0;
  while (!r.at_end()) {
    int prop = static_cast<int>(r.gchar());
    if (rejected(prop, other, last_prop)) return applied;
    if (!apply_one(prop, r, p)) return applied;  // unknown size: the rest is lost
    if (!r.ok()) return applied;
    ++applied;
  }
  return applied;
}

int apply_own_props(Net::Reader& r, Player& p, Net::OwnProps rules, int last_prop) {
  if (rules == Net::OwnProps::k222) return apply_props(r, p, false, last_prop);
  int applied = 0;
  while (!r.at_end()) {
    int prop = static_cast<int>(r.gchar());
    if (!own_case(prop, rules)) {
      r.gchar();  // no case: the id and one value byte
    } else if (prop == 77) {
      r.gint5();  // read, nothing stored
    } else if (prop == 83) {
      uint64_t v = r.gint5();  // the gralat count prop 3 also sets
      if (r.ok() && v <= kMaxGralats83) p.rupees = static_cast<int>(v);
    } else if (!apply_one(prop, r, p)) {
      return applied;
    }
    if (!r.ok()) return applied;
    ++applied;
  }
  return applied;
}

std::string initial_props(const Player& p, const std::string& os_type) {
  std::string s = gchar(kNickname) + gstring(p.nickname) + gchar(kColors);
  for (int c : p.colors) s += gchar(static_cast<unsigned>(c));
  s += gchar(kLanguage) + gstring(p.language) + gchar(kOsType) + gstring(os_type);
  s += gchar(kX2) + gshort(to_pixels2(p.x)) + gchar(kY2) + gshort(to_pixels2(p.y));
  return s;
}

std::string MoveSender::diff(const Player& p) {
  std::string s;
  if (p.gani != gani_) s += gchar(kGani) + gstring(p.gani);
  if (p.dir != dir_) s += gchar(kSprite) + gchar(static_cast<unsigned>(p.dir));
  if (p.x != x_) s += gchar(kX2) + gshort(to_pixels2(p.x));
  if (p.y != y_) s += gchar(kY2) + gshort(to_pixels2(p.y));
  reset(p);
  return s;
}

}  // namespace Quattro::World
