// Server scripts in the Quattro program: weapons and classes delivered by
// 140 and 197, the GRESCR01 cache, and the GS2 machine (common/cpp/gs2,
// the 6.00 opcode profile) they run on.
//
// Behaviour, from Graal_analysis:
// - 140 (protocol/linux-603-network-gs2.md): a 2-byte GSHORT H, the
//   descriptor (H bytes), then the body. The descriptor is a comma list:
//   type (weapon or class), name, cache flag, then the two GINT5 words of the
//   DES key (protocol/v5x-clients.md). The body is compiled GS2.
// - With cache flag 1 the body is written to
//   weblevels/<host>/weapons|classes/<name>.code as GRESCR01
//   (formats/gwebl001-cache.md).
// - 197 (formats/linux-6x-class-cache.md, gs2-official-bytecode-6113.md):
//   the whole body is the metadata list "type,name,1,key,crc", with the key
//   two GINT5 words and the CRC one GINT5, over the stored body. A cache hit
//   loads the copy; otherwise the client asks again: 158 for a weapon, 161
//   for a class.
// - 33 adds a weapon by name; 34 deletes it (gs2lib names).
// - 190 raises onServerListerConnect on the Login server
//   (client-internals/engine-600r2.md, "Network").
// - 48 (PLO_TRIGGERACTION, protocol/packet-ids.md; the GServer-v2 writer
//   is GSHORT player, GINT3 NPC, GCHAR x, GCHAR y, then the CSV
//   "action,params"): `clientside,<weapon>,<params>` queues
//   onActionClientSide on that weapon with the params after the weapon's
//   name (npc-library/gs2-weapon-corpus-2026-11-14.md, step 1). Any other
//   action queues onAction<action> on every weapon (a reading: GS2 calls
//   triggered actions that way, but no 6.x client was read for it).
// - Weapon scripts send to the server with `triggerserver(kind, weapon,
//   params...)` and `triggeraction(x, y, action, params...)`: both are
//   C->S 38 (GINT3 0, GCHAR x * 2, GCHAR y * 2, then the CSV), the first
//   as "serverside,<weapon>,<params>", which GServer-v2 turns into the
//   weapon's onActionServerSide [srv]. That triggerserver sends exactly
//   this is read from the scripts and the server, not from a client.
//
// How the descriptor's key words sit after the third comma (directly, or
// each after its own comma) is not spelled out in the notes. This reader
// takes the bytes after the third comma, drops commas between them, and
// reads two GINT5 values (and, for 197, a third).
#pragma once

#include "../../gs2/gs2.hpp"
#include "../cache/grescr.hpp"

#include <functional>
#include <map>
#include <optional>
#include <string>
#include <string_view>

namespace Quattro::Shell {

struct ScriptDescriptor {
  std::string type;  // "weapon" or "class"
  std::string name;
  int cache_flag = 0;
  std::optional<Cache::ScriptKey> key;
  uint32_t crc = 0;  // 197 only
};

// Splits a 140 payload into its descriptor and body.
bool parse_script_packet(std::string_view payload, ScriptDescriptor& d, std::string& body);
// Parses a 197 body.
bool parse_load_script(std::string_view payload, ScriptDescriptor& d);
// The CSV the trigger actions use: a field is quoted when it holds a comma,
// a quote, a backslash or a byte past 126, with quotes and backslashes
// doubled inside (Seihai's gserver `toCSV` / `fromCSV`).
std::string to_csv(const std::vector<std::string>& fields);
std::vector<std::string> from_csv(std::string_view text);
// Builds those payloads (for the fake servers in tests and lab tools).
std::string make_script_packet(const ScriptDescriptor& d, std::string_view body);
std::string make_load_script(const ScriptDescriptor& d);

class ScriptHost {
 public:
  // `send` queues an outgoing message (id, body) on the connection.
  using SendFn = std::function<bool(int id, std::string_view body)>;

  ScriptHost();

  void set_send(SendFn fn) { send_ = std::move(fn); }
  // The cache folder for this server: <assets>/weblevels/<host>. Empty: no
  // disk cache (every 197 then asks again).
  void set_cache_dir(std::string dir) { cache_dir_ = std::move(dir); }

  // Handles 33, 34, 140, 190 and 197. False for other ids.
  bool on_message(int id, std::string_view body);
  // One script pass (the 50 ms tick).
  void tick() { machine_.runScripts(); }

  gs2::Machine& machine() { return machine_; }
  gs2::VarPtr weapon(const std::string& name) const;
  // 194 (PLO_RESETCLIENT, was CLEARWEAPONS): every weapon goes.
  void clear_weapons() { weapons_.clear(); }
  // The trigger actions as C->S 38 bodies (also for tests).
  static std::string trigger_body(double x, double y, const std::string& csv);
  // Raises onWeaponFired on the named weapon; false when it has no script.
  bool fire(const std::string& name);
  // A key went down (Torque key name, typed character): onKeyPressed
  // (keycode, key text) on every weapon with a script.
  void key_pressed(const std::string& key, int ch);
  // The keycode a GS2 script sees for a key name: the Windows virtual-key
  // code (letters and digits as upper-case ASCII, arrows 37 to 40). A
  // reading; the 6.x key table is not copied out in the notes.
  static int keycode(const std::string& key, int ch);
  // Queues an event on every weapon that has a script (onPlayerChats,
  // onKeyPressed, onPlayerEnters, ...).
  void queue_all(const std::string& event, std::vector<gs2::Value> args = {});
  // The weapon whose object this is, by name ("" when it is none).
  std::string weapon_name(const gs2::Var* v) const;
  // Drops a weapon (194, 34, or its script's destroy()).
  void remove_weapon(const std::string& name);
  // Every weapon object, in name order.
  std::vector<gs2::VarPtr> weapon_objects() const;
  // The `player` the scripts see (the program fills its fields each tick).
  gs2::VarPtr player() const { return player_; }
  const std::map<std::string, std::string>& classes() const { return classes_; }
  const std::vector<std::string>& log() const { return log_; }
  std::function<void(const std::string&)> on_log;

 private:
  void note(const std::string& s);
  void load(const ScriptDescriptor& d, const std::string& body);
  std::string cache_path(const ScriptDescriptor& d) const;

  gs2::Machine machine_;
  SendFn send_;
  std::string cache_dir_;
  gs2::VarPtr player_;
  std::map<std::string, gs2::VarPtr> weapons_;  // lower-cased names
  std::map<std::string, std::string> classes_;  // name -> bytecode
  std::vector<std::string> log_;
};

}  // namespace Quattro::Shell
