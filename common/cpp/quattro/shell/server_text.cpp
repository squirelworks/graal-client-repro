// Graal text messages from the Graal3D server: in 3D mode the 3D server,
// not the TCP gserver, delivers the client's weapons, flags and script
// events (Graal_analysis graal3d/torque-engine-4x.md "Graal text",
// torque/udp-session.md §7).
//
// With a weapon name the text goes to that weapon as
// onReceiveText(type, option, data). Otherwise the type selects:
//   set / unset      the player flag in the data
//   events           lines: `s <flag>` sets a flag; `t <kind>,<name>,<action>,<params>`
//                    raises onAction<action> on weapon or GUI <name>
//                    (kind weapon or gui) or on that NPC (npc); kind rc is
//                    onRCChat; kind torque is ignored
//   addweapon        weapon <option>; the data's GINT5 is not used
//   weaponscript     bytecode for weapon <option>
//   deleteweapon     weapon <option> goes
//   addnpc           bytecode for the client-side object named <option>
//   setmaterials     the terrain material list (logged; no terrain yet)
//   rpg              onRPGMessage(data) on every weapon
// The field order inside a `t` line is the rebuild's reading of the note's
// `t <target>,<kind>,<action>,<params>`, matched to the client's own
// `t weapon,<name>,<params>`.
#include "program.hpp"

#include <sstream>

namespace Quattro::Shell {

void Program::server_text(const std::string& weapon, const std::string& type, const std::string& option,
                          const std::string& data) {
  auto note = [this](const std::string& s) {
    if (log) log("Graal3D text: " + s);
  };
  if (!weapon.empty()) {
    gs2::VarPtr w = scripts_.weapon(weapon);
    if (w && scripts_.machine().hasScript(w))
      scripts_.machine().queueEvent(w, "ReceiveText", {gs2::Value::string(type), gs2::Value::string(option),
                                                       gs2::Value::string(data)});
    else
      note("text for " + weapon + ", which has no script");
    return;
  }
  if (type == "set") {
    scripts_.set_flag(data);
  } else if (type == "unset") {
    scripts_.unset_flag(data);
  } else if (type == "events") {
    std::istringstream in(data);
    std::string line;
    while (std::getline(in, line)) {
      if (!line.empty() && line.back() == '\r') line.pop_back();
      if (line.size() < 2 || line[1] != ' ') continue;
      const std::string rest = line.substr(2);
      if (line[0] == 's') {
        scripts_.set_flag(rest);
      } else if (line[0] == 't') {
        std::vector<std::string> f = from_csv(rest);
        if (f.empty()) continue;
        const std::string& kind = f[0];
        std::vector<gs2::Value> params;
        for (size_t i = 3; i < f.size(); ++i) params.push_back(gs2::Value::string(f[i]));
        if (kind == "rc") {
          std::vector<gs2::Value> args;
          for (size_t i = 1; i < f.size(); ++i) args.push_back(gs2::Value::string(f[i]));
          scripts_.queue_all("RCChat", std::move(args));
        } else if (kind == "torque" || f.size() < 3) {
          continue;
        } else if (kind == "npc") {
          gs2::VarPtr o = scripts_.object(f[1]);
          if (o && scripts_.machine().hasScript(o)) scripts_.machine().queueEvent(o, "Action" + f[2], params);
        } else {  // weapon, gui
          gs2::VarPtr w = scripts_.weapon(f[1]);
          if (w && scripts_.machine().hasScript(w)) scripts_.machine().queueEvent(w, "Action" + f[2], params);
        }
      }
    }
  } else if (type == "addweapon") {
    weapons_.add(option, {});
    scripts_.add_weapon(option);
  } else if (type == "weaponscript") {
    weapons_.add(option, {});
    scripts_.set_weapon_script(option, data);
  } else if (type == "deleteweapon") {
    weapons_.remove(option);
    scripts_.remove_weapon(option);
  } else if (type == "addnpc") {
    scripts_.set_object_script(option, data);
  } else if (type == "rpg") {
    scripts_.queue_all("RPGMessage", {gs2::Value::string(data)});
  } else {
    note(type + " (" + std::to_string(data.size()) + " bytes) not used");
  }
}

}  // namespace Quattro::Shell
