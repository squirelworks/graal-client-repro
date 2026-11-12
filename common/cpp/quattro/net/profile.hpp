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
  unsigned login_port = 14900;    // compiled-in login server port
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
