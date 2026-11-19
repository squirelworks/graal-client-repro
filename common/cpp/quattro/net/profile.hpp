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

// How a build reads its own prop stream (PLO_PLAYERPROPS, 9). From real
// clients probed with injected packets (Graal_analysis
// protocol/probe-targets-2026-11-18.md, protocol/probe-results.tsv).
enum class OwnProps {
  // 2.22's parser: an id it has no case for ends the message.
  k222,
  // 4.20r8: ids 33, 50, 51, 53, 75 to 77, 82, 83 and past 83 have no case
  // and are skipped with one value byte; the message goes on.
  k4x,
  // 5.24r4: as 4.20r8, but 82 (community name) is a length-prefixed string.
  k5x,
  // 6.03r7: as 5.24r4, plus 77 (five bytes, nothing stored) and 83 (the
  // gralat count in five bytes, applied only up to 999,999,999).
  k6x,
};

struct BuildProfile {
  std::string label;       // "6.03r7 Linux"
  std::string token;       // the 8-character version token
  std::string platform;    // first field of the login line's comma list
  // The machine fields after the platform, each with its leading comma. The
  // original hashes its machine; the rebuild reads no machine values and
  // sends fixed made-up ones of the same shape (kFakeWinFields,
  // kFakeLinuxFields).
  std::string machine_fields;
  // Server -> client ids the receive switch handles. Ids 100 and 108 are
  // taken before that switch and are not in this set (see handles_pre_switch).
  std::bitset<256> plo;
  // Client -> server ids the build sends. Sending any other id is refused.
  std::bitset<256> pli;
  bool answers_ping = false;      // PLO 108 sub 0 -> PLI 162
  bool login_lobby_mode = true;   // name starting "login": no characters, HUD
  bool login_draws_tiles = false; // tiles drawn in that mode
  bool hud_6x = false;            // the built-in 6.x HUD (draw/hud.hpp)
  int hud_4x5x = 0;               // 4 or 5: the 4.04r2 or 5.12 HUD (draw/hud.hpp); 0 none
  bool title_is_server = false;   // window title: the server name alone
  // After each login: basepackage.gupd (23, or 47 with a cached copy's
  // CRC-32), and bigmap.txt on the Login session once per run.
  bool update_packages = false;
  bool cold_gani_requests = false; // measured cold-cache pair only for 4.04r2
  int carry_sprite_after = 4, carry_still_after = 6; // legacy rebuild timing unless measured
  bool escape_menu = false; // measured only for Linux 6.03r7 without a scripted GUI
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
  // Compiled scripts on the 3.153-5.12 path: 132 (weapon bytecode, cached
  // as weblevels/weapons/<name>.code), 133 (class bytecode) and 193 (the
  // weapon's CRC: load the cached copy or ask with 158). 5.24 on uses 197.
  bool v4_scripts = false;
  // The GS2 opcode set the client's machine runs: 42 (4.2 engine), 50 (5.0)
  // or 600 (6.00) (client-internals/gs2-vm-from-engines.md).
  int gs2_engine = 600;
  // The highest player prop id the build reads (2.22's parsers stop past
  // 80; the lab's 5.12 listed players' community names, prop 82).
  int last_prop = 80;
  // The own-prop rules (OwnProps). Other players' props (8) keep the 2.22
  // table up to last_prop.
  OwnProps own_props = OwnProps::k222;
};

// Made-up machine fields, the shape the originals send. Windows: the MD5
// hex of "SquirrelOS product id SQRL7-ACORN-OAK42-NUTS1", of "SquirrelNIC
// MAC AC:04:2D:5E:ED:01" and of "SquirrelBIOS C: volume serial ACE5-5EED".
// Linux: the MD5 hex of "SquirrelNIC eth0 MAC AC:04:2D:5E:ED:02" and of
// "SquirrelFS /etc inode 424242", an empty field, and a SquirrelOS kernel
// release, two spaces and version (the original's uname layout).
extern const char kFakeWinFields[];
extern const char kFakeLinuxFields[];

// Every row this program can run as.
const std::vector<BuildProfile>& profiles();
// The row for a label ("6.03r7", "6.03r7 Linux", "6.01r1", case-insensitive).
const BuildProfile* find_profile(std::string_view label);

// Ids that the 6.x reader takes before its switch (6.01r1 and 6.03r7).
bool handles_pre_switch(int id);

// Ids the client sends after PLI 50 with a 3-byte length (93 and 163).
bool needs_raw_prefix(int id);

}  // namespace Quattro::Net
