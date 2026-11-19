// Server NPCs on the 3.153-5.12 path: PLO_NPCPROPS (3) builds and moves
// them, PLO_NPCBYTECODE (131) gives one its compiled script, and
// PLO_NPCDEL (29), PLO_NPCDEL2 (150) and PLO_HIDENPCS (151) take them away.
//
// Behaviour, from Graal_analysis:
// - 3 is `GINT3 id` then an NPCPROP stream (protocol/packet-layouts.md,
//   protocol/player-props.md "NPCPROP"). Ids below 1000 are level NPCs,
//   1000 and up server-wide ones. A new NPC gets `playerenters`.
// - The 4.x and 5.x NPC parsers handle props 0-47 and 53-77; any other id
//   ends the stream, and the props already read stay (protocol/v5-props.md;
//   4.20r8 gives the same set, protocol/v4x-clients.md "Prop parsers").
// - 131 is `GINT3 id` then the bytecode (protocol/packet-ids.md).
// - 151 removes the active level's NPCs with ids 1 to 999.
// - From 4.x on the server compiles GS1 to the same bytecode, so there is
//   no GS1 text runner on the client (client-internals/gs1-on-5x-hud-and-flags.md).
//   NPCPROP 1 (the GS1 text) is read and kept, not run.
//
// Rebuild readings, not in the notes: VISFLAGS bit 0 is "visible" (the GS1
// flag order), and an NPC with no VISFLAGS yet is visible; an NPC with a
// gani is drawn as a character, otherwise as its image.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

namespace Quattro::World {

enum NpcProp {
  kNpcImage = 0, kNpcScript = 1, kNpcX = 2, kNpcY = 3, kNpcPower = 4, kNpcRupees = 5, kNpcArrows = 6,
  kNpcBombs = 7, kNpcGlovePower = 8, kNpcBombPower = 9, kNpcSword = 10, kNpcShield = 11, kNpcGani = 12,
  kNpcVisFlags = 13, kNpcBlockFlags = 14, kNpcMessage = 15, kNpcHurtDxDy = 16, kNpcId = 17, kNpcSprite = 18,
  kNpcColors = 19, kNpcNickname = 20, kNpcHorseImage = 21, kNpcHeadImage = 22, kNpcSave0 = 23, kNpcSave9 = 32,
  kNpcAlignment = 33, kNpcImagePart = 34, kNpcBodyImage = 35, kNpcGattrib1 = 36, kNpcGattrib5 = 40,
  kNpcGmapLevelX = 41, kNpcGmapLevelY = 42, kNpcZ = 43, kNpcGattrib6 = 44, kNpcGattrib9 = 47,
  kNpcGattrib10 = 53, kNpcGattrib30 = 73, kNpcClass = 74, kNpcX2 = 75, kNpcY2 = 76, kNpcZ2 = 77,
};

struct ServerNpc {
  int id = 0;
  double x = 0, y = 0;  // tiles
  int z = 0;
  std::string image;
  bool has_part = false;
  int part_x = 0, part_y = 0, part_w = 0, part_h = 0;
  std::string gani;
  int dir = 2;
  std::string nickname, head, body, sword, shield, horse, message, cls;
  std::string gs1_text;  // NPCPROP 1, kept only
  std::array<std::string, 31> attr;  // gattrib 1..30
  std::array<int, 5> colors{};
  std::array<int, 10> save{};
  int power = 0, rupees = 0, arrows = 0, bombs = 0, glove_power = 0, bomb_power = 0, alignment = 0;
  int visflags = 1, blockflags = 0;
  bool visible() const { return (visflags & 1) != 0; }
  bool character() const { return !gani.empty(); }
};

// Applies an NPCPROP stream in the 4.x / 5.x parser's shape. False when an
// id outside 0-47 and 53-77 (or a short value) ended it early.
bool apply_npc_props(ServerNpc& npc, std::string_view stream);

// Builds a prop stream (for the fake servers in tests and lab tools).
std::string npc_prop_string(int id, std::string_view value);  // one GSTRING prop
std::string npc_prop_char(int id, unsigned value);

}  // namespace Quattro::World
