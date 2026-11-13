// Per-build facts the Quattro program's game connection needs.
//
// Each row is one original build, read from Graal_analysis
// protocol/v6x-clients.md (tokens, login line, id sets, ping) and
// protocol/v5v6-lab-play.md (the Login server mode). A fact that is
// inferred there is marked in the row's notes.
#pragma once

#include <bitset>
#include <string>
#include <string_view>
#include <vector>

namespace Quattro::Net {

struct BuildProfile {
  std::string label;       // "6.03r7 Linux"
  std::string token;       // the 8-character version token
  std::string platform;    // first field of the login line's comma list
  int machine_fields = 0;  // fields after the platform; the rebuild sends "" for each
  // Server -> client ids the receive switch handles. Ids 100 and 108 are
  // taken before that switch and are not in this set (see handles_pre_switch).
  std::bitset<256> plo;
  // Client -> server ids the build sends. Sending any other id is refused.
  std::bitset<256> pli;
  bool answers_ping = false;      // PLO 108 sub 0 -> PLI 162
  bool login_lobby_mode = true;   // name starting "login": no characters, HUD
  bool login_draws_tiles = false; // tiles drawn in that mode
  bool hud_6x = false;            // the built-in 6.x HUD (draw/hud.hpp)
  bool title_is_server = false;   // window title: the server name alone
  // After each login: basepackage.gupd (23, or 47 with a cached copy's
  // CRC-32), and bigmap.txt on the Login session once per run.
  bool update_packages = false;
  bool draws_chests = true;       // a chest is drawn (6.03r7: never, only its tiles)
  unsigned login_port = 14900;    // compiled-in login server port
  // A last login field after the machine fields, sent quoted ("" for none):
  // 5.12's Windows version (protocol/v5v6-windows-unpacked.md).
  std::string os_version;
  bool has_os_version = false;
  // 5.12's gen-5 quirks (Cipher::set_packed_round_down,
  // FrameEncoder::set_compress_always).
  bool packed_round_down = false;
  bool compress_always = false;
  // The highest player prop id the build reads (2.22's parsers stop past
  // 80; the lab's 5.12 listed players' community names, prop 82).
  int last_prop = 80;
};

// Every row this program can run as.
const std::vector<BuildProfile>& profiles();
// The row for a label ("6.03r7", "6.03r7 Linux", "6.01r1", case-insensitive).
const BuildProfile* find_profile(std::string_view label);

// Ids that the 6.x reader takes before its switch (6.01r1 and 6.03r7).
bool handles_pre_switch(int id);

// Ids the client sends after PLI 50 with a 3-byte length (93 and 163).
bool needs_raw_prefix(int id);

}  // namespace Quattro::Net
