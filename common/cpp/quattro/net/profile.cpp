#include "profile.hpp"

#include <cctype>
#include <initializer_list>
#include <utility>

namespace Quattro::Net {

namespace {

using Range = std::pair<int, int>;

std::bitset<256> ids(std::initializer_list<Range> ranges) {
  std::bitset<256> set;
  for (auto [lo, hi] : ranges)
    for (int i = lo; i <= hi; ++i) set.set(static_cast<size_t>(i));
  return set;
}

// protocol/v6x-clients.md, "Server -> client ids (6.01, 6.03)": the 6.03r7
// switch, 92 ids.
std::bitset<256> plo_603() {
  return ids({{0, 25},   {27, 40},  {42, 43},  {45, 49},  {67, 69},  {74, 74},  {82, 82},
              {84, 84},  {101, 102}, {104, 107}, {109, 109}, {111, 111}, {131, 131}, {134, 134},
              {140, 140}, {150, 151}, {153, 156}, {166, 166}, {168, 168}, {170, 170}, {172, 174},
              {176, 176}, {178, 180}, {182, 183}, {185, 187}, {189, 191}, {194, 195}, {197, 198}});
}

// protocol/v6x-clients.md, "Client -> server ids (6.01, 6.03)".
std::bitset<256> pli_603() {
  return ids({{0, 20},  {22, 24}, {26, 30}, {32, 38},  {41, 41},   {44, 48},
              {50, 50}, {79, 79}, {92, 93}, {96, 98},  {130, 130}, {152, 152},
              {154, 162}});
}

std::vector<BuildProfile> make() {
  std::vector<BuildProfile> rows;

  BuildProfile r603;
  r603.label = "6.03r7 Linux";
  r603.token = "G3D0511C";
  r603.platform = "linux";
  r603.machine_fields = 4;
  r603.plo = plo_603();
  r603.pli = pli_603();
  r603.answers_ping = true;
  r603.hud_6x = true;  // the 6.03r7 HUD lab (draw/hud.hpp)
  r603.title_is_server = true;  // the 6.03r7 frames lab: "HUD Lab 603"
  rows.push_back(r603);

  // 6.01r1: the 6.03r7 receive set without 111, the send set without 160.
  BuildProfile r601 = r603;
  r601.label = "6.01r1 Linux";
  r601.token = "G3D0108A";
  r601.plo.reset(111);
  r601.pli.reset(160);
  rows.push_back(r601);

  // 4.04r2 (Windows, the GraalEngine.dll session, used by
  // common/cpp/graalengine). From Graal_analysis protocol/v4x-clients.md
  // and version-profiles/4.04-4.20.toml, as graal-4.04r2-G3D17026's
  // Protocol404 carries them: the same gen-5 cipher and login line ("win"
  // and three empty machine fields), no ping answer (108 is not in its
  // switch), never 39. Its first server is a game server named Login that
  // hands the player on with 178, as the 6.x lobby does. The send set is
  // the ids that rebuild sends (the notes give no full list).
  BuildProfile r404;
  r404.label = "4.04r2 Windows";
  r404.token = "G3D17026";
  r404.platform = "win";
  r404.machine_fields = 3;
  r404.plo = ids({{0, 25},    {27, 43},   {45, 49},   {67, 69},   {74, 75},   {82, 82},
                  {84, 84},   {100, 102}, {104, 106}, {131, 134}, {150, 151}, {153, 156},
                  {165, 166}, {168, 176}, {178, 187}, {189, 191}, {193, 195}});
  r404.pli = ids({{0, 6},   {18, 19}, {23, 24}, {28, 28}, {30, 31}, {34, 35},
                  {37, 38}, {44, 44}, {46, 46}, {157, 157}});
  r404.answers_ping = false;
  // The stock 4.04r2 GraalEngine.dll steps the cipher as 5.12 does:
  // len >> 2 for zlib and bzip2 bodies (at most 4), (len + 3) >> 2 for raw
  // ones (at most 12), both ways (read for seihai-core #41).
  r404.packed_round_down = true;
  rows.push_back(r404);

  // 5.00r7 and 5.12 (Windows, the GraalEngine.dll session, used by
  // common/cpp/graalengine). Graal_analysis protocol/v5x-clients.md,
  // protocol/v5v6-windows-unpacked.md and version-profiles/5.00-6.03.toml:
  // the 4.04r2 receive switch less 100 and with 41, 105-107, 140, 170,
  // 182, 183, 190, 191, 193-195 and 197 (100 ids, the same for both); the
  // same Login server and 178 hand-on; no ping answer, never 39.
  BuildProfile r500 = r404;
  r500.label = "5.00r7 Windows";
  r500.token = "G3D22067";
  r500.machine_fields = 3;  // win,<md5>,"",<md5> in the lab; "" each here
  r500.packed_round_down = false;  // 5.00r7 rounds up both ways
  // In Login mode the level, chests and image NPCs are drawn; characters
  // and the HUD are not (protocol/v5v6-lab-play.md, "The Login server mode").
  r500.login_draws_tiles = true;
  r500.plo = ids({{0, 25},    {27, 43},   {45, 49},   {67, 69},   {74, 75},   {82, 82},
                  {84, 84},   {101, 102}, {104, 107}, {131, 134}, {140, 140}, {150, 151},
                  {153, 156}, {165, 166}, {168, 176}, {178, 187}, {189, 191}, {193, 195},
                  {197, 197}});
  // The send wrappers' constant ids and those seen on the wire (a floor;
  // 5.00-6.03.toml).
  r500.pli = ids({{1, 2},   {4, 19},  {21, 24}, {26, 26},  {28, 29},   {32, 38},
                  {41, 41}, {44, 44}, {47, 47}, {50, 50},  {79, 81},   {92, 93},
                  {96, 98}, {130, 130}, {152, 152}, {154, 159}, {161, 161}});
  rows.push_back(r500);

  // 5.12: 5.00r7's sets (its receive switch is identical; its send code was
  // not read, and every id the lab saw it send is in 5.00r7's set).
  // Different: the token, a fifth login field (the quoted Windows
  // version, "6.2 9200 " on Windows 8 and later), every body below the
  // bzip2 size zlib-compressed, and packed bodies stepped len / 4 rounded
  // down (protocol/v5v6-lab-play.md).
  BuildProfile r512 = r500;
  r512.label = "5.12 Windows";
  r512.token = "G3D14097";
  r512.has_os_version = true;
  r512.os_version = "6.2 9200 ";
  r512.packed_round_down = true;
  r512.compress_always = true;
  rows.push_back(r512);

  return rows;
}

std::string lower(std::string_view s) {
  std::string out(s);
  for (char& c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return out;
}

}  // namespace

const std::vector<BuildProfile>& profiles() {
  static const std::vector<BuildProfile> rows = make();
  return rows;
}

const BuildProfile* find_profile(std::string_view label) {
  std::string want = lower(label);
  for (const auto& row : profiles()) {
    std::string full = lower(row.label);
    if (full == want) return &row;
    // The bare version ("6.03r7") picks the row whose label starts with it.
    if (full.compare(0, want.size(), want) == 0 && full.size() > want.size() && full[want.size()] == ' ')
      return &row;
  }
  return nullptr;
}

bool handles_pre_switch(int id) { return id == 100 || id == 108; }

bool needs_raw_prefix(int id) { return id == 93 || id == 163; }

}  // namespace Quattro::Net
