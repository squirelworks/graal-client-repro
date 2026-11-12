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
  std::map<std::string, gs2::VarPtr> weapons_;  // lower-cased names
  std::map<std::string, std::string> classes_;  // name -> bytecode
  std::vector<std::string> log_;
};

}  // namespace Quattro::Shell
