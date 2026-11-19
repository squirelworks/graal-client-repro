#include "npcs.hpp"

#include "../net/gtypes.hpp"
#include "player.hpp"

namespace Quattro::World {

namespace {

std::string take(Net::Reader& r, unsigned n) {
  std::string s;
  for (unsigned i = 0; i < n && r.ok(); ++i) {
    unsigned b = r.gchar() + 32;  // gchar takes 32 off; put it back for raw bytes
    if (r.ok()) s.push_back(static_cast<char>(b & 0xFF));
  }
  return s;
}

}  // namespace

bool apply_npc_props(ServerNpc& n, std::string_view stream) {
  Net::Reader r(stream);
  while (!r.at_end()) {
    const int id = static_cast<int>(r.gchar());
    if (!r.ok()) return false;
    if (id > kNpcZ2 || (id > kNpcGattrib9 && id < kNpcGattrib10)) return false;
    switch (id) {
      case kNpcImage: n.image = r.gstring(); break;
      case kNpcScript: {
        unsigned len = r.gshort();
        std::string text = take(r, len);
        if (n.gs1_text.empty()) n.gs1_text = std::move(text);  // a second SCRIPT is ignored
        break;
      }
      case kNpcX: n.x = r.gchar() / 2.0; break;
      case kNpcY: n.y = r.gchar() / 2.0; break;
      case kNpcPower: n.power = static_cast<int>(r.gchar()); break;
      case kNpcRupees: n.rupees = static_cast<int>(r.gint3()); break;
      case kNpcArrows: n.arrows = static_cast<int>(r.gchar()); break;
      case kNpcBombs: n.bombs = static_cast<int>(r.gchar()); break;
      case kNpcGlovePower: n.glove_power = static_cast<int>(r.gchar()); break;
      case kNpcBombPower: n.bomb_power = static_cast<int>(r.gchar()); break;
      case kNpcSword: {
        unsigned v = r.gchar();
        if (v >= 30) n.sword = r.gstring();
        else n.sword = v ? "sword" + std::to_string(v) + ".png" : std::string();
        break;
      }
      case kNpcShield: {
        unsigned v = r.gchar();
        if (v >= 10) n.shield = r.gstring();
        else n.shield = v ? "shield" + std::to_string(v) + ".png" : std::string();
        break;
      }
      case kNpcGani: n.gani = r.gstring(); break;
      case kNpcVisFlags: n.visflags = static_cast<int>(r.gchar()); break;
      case kNpcBlockFlags: n.blockflags = static_cast<int>(r.gchar()); break;
      case kNpcMessage: n.message = r.gstring(); break;
      case kNpcHurtDxDy: r.gchar(); r.gchar(); break;
      case kNpcId: r.gint3(); break;
      case kNpcSprite: n.dir = static_cast<int>(r.gchar() % 4); break;
      case kNpcColors:
        for (int& c : n.colors) c = static_cast<int>(r.gchar());
        break;
      case kNpcNickname: n.nickname = r.gstring(); break;
      case kNpcHorseImage: n.horse = r.gstring(); break;
      case kNpcHeadImage: {
        unsigned v = r.gchar();
        n.head = v >= 100 ? take(r, v - 100) : "head" + std::to_string(v) + ".png";
        break;
      }
      case kNpcAlignment: n.alignment = static_cast<int>(r.gchar()); break;
      case kNpcImagePart:
        n.part_x = static_cast<int>(r.gshort());
        n.part_y = static_cast<int>(r.gshort());
        n.part_w = static_cast<int>(r.gchar());
        n.part_h = static_cast<int>(r.gchar());
        n.has_part = true;
        break;
      case kNpcBodyImage: n.body = r.gstring(); break;
      case kNpcGmapLevelX: case kNpcGmapLevelY: r.gchar(); break;
      case kNpcZ: n.z = static_cast<int>(r.gchar()) - 50; break;
      case kNpcClass: n.cls = r.gstring(); break;
      case kNpcX2: n.x = from_pixels2(r.gshort()); break;
      case kNpcY2: n.y = from_pixels2(r.gshort()); break;
      case kNpcZ2: n.z = static_cast<int>(from_pixels2(r.gshort()) * 16); break;
      default:
        if (id >= kNpcSave0 && id <= kNpcSave9) {
          n.save[static_cast<size_t>(id - kNpcSave0)] = static_cast<int>(r.gchar());
        } else if (id >= kNpcGattrib1 && id <= kNpcGattrib5) {
          n.attr[static_cast<size_t>(id - kNpcGattrib1 + 1)] = r.gstring();
        } else if (id >= kNpcGattrib6 && id <= kNpcGattrib9) {
          n.attr[static_cast<size_t>(id - kNpcGattrib6 + 6)] = r.gstring();
        } else if (id >= kNpcGattrib10 && id <= kNpcGattrib30) {
          n.attr[static_cast<size_t>(id - kNpcGattrib10 + 10)] = r.gstring();
        }
        break;
    }
    if (!r.ok()) return false;
  }
  return true;
}

std::string npc_prop_string(int id, std::string_view value) {
  return Net::gchar(static_cast<unsigned>(id)) + Net::gstring(value);
}

std::string npc_prop_char(int id, unsigned value) {
  return Net::gchar(static_cast<unsigned>(id)) + Net::gchar(value);
}

}  // namespace Quattro::World
