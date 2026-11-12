// Finding and naming the engines' built-in shell scripts.
//
// The names are the StartScript_* names the 4.04r2 and 5.12 engines carry.
// A stream is matched to a name by a function only that script defines,
// checked against both engines' streams. Which order the engine attaches
// them in is not read; file order is used.

#include "startscripts.hpp"

#include <zlib.h>

#include <cctype>
#include <cstring>

namespace gs2 {

namespace {

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

std::string inflateAt(const unsigned char* p, std::size_t n) {
  z_stream z;
  std::memset(&z, 0, sizeof z);
  if (inflateInit(&z) != Z_OK) return {};
  z.next_in = const_cast<unsigned char*>(p);
  z.avail_in = static_cast<uInt>(n > 0x7fffffff ? 0x7fffffff : n);
  std::string out;
  unsigned char buf[65536];
  int rc = Z_OK;
  while (rc == Z_OK && out.size() < (16u << 20)) {
    z.next_out = buf;
    z.avail_out = sizeof buf;
    rc = inflate(&z, Z_NO_FLUSH);
    out.append(reinterpret_cast<char*>(buf), sizeof buf - z.avail_out);
  }
  inflateEnd(&z);
  return rc == Z_STREAM_END ? out : std::string();
}

struct Rule {
  const char* name;
  const char* function;  // defined only by that script
};

const Rule kRules[] = {
    {"StartScript_Profiles", "addProfiles"},
    {"StartScript_MainMenu", "switchToServerList"},
    {"StartScript_GraalGui", "GraalControl.onWake"},
    {"StartScript_GraalGui3D", "GraalControl3D.onWake"},
    {"StartScript_OptionsWindow", "OptionsDlg2D_applyGraphics"},
    {"StartScript_PlayerProfile", "PlayerProfileSend"},
    {"StartScript_LoadLevelGui", "onOpenPlayerPositionWindow"},
    {"StartScript_LoadingGui3D", "onGraal3DLoginStep"},
    {"StartScript_QuitDialog", "QuitDialog_YesButton.onAction"},
    {"StartScript_MessageBoxDialog", "MessageBoxDialog_Button.onAction"},
    {"StartScript_SetupDialog", "SetupDialog_InstallButton.onAction"},
    {"StartScript_SelectFileDialog", "FileSelector_CancelButton.onAction"},
};

bool hasString(const Script& s, const std::string& want) {
  for (const auto& t : s.strings)
    if (t == want) return true;
  return false;
}

}  // namespace

std::vector<std::string> findEmbeddedScripts(const std::string& image) {
  std::vector<std::string> out;
  const auto* d = reinterpret_cast<const unsigned char*>(image.data());
  static const char head[8] = {0, 0, 0, 1, 0, 0, 0, 4};
  for (std::size_t i = 0; i + 2 < image.size(); ++i) {
    if (d[i] != 0x78 || (d[i + 1] != 0x01 && d[i + 1] != 0x5e && d[i + 1] != 0x9c && d[i + 1] != 0xda)) continue;
    std::string s = inflateAt(d + i, image.size() - i);
    if (s.size() >= 16 && std::memcmp(s.data(), head, 8) == 0) out.push_back(std::move(s));
  }
  return out;
}

std::string identifyStartScript(const Script& s) {
  for (const auto& r : kRules)
    if (s.findFunction(r.function)) return r.name;
  // The two key maps define no function of their own; each builds one
  // ActionMap, and the 2D one names it moveMap2D.
  bool onlyCreated = !s.functions.empty();
  for (const auto& f : s.functions) onlyCreated = onlyCreated && lower(f.name) == "oncreated";
  if (onlyCreated && hasString(s, "ActionMap")) {
    if (hasString(s, "moveMap2D")) return "StartScript_MoveMap2D";
    if (hasString(s, "moveMap")) return "StartScript_MoveMap3D";
  }
  return {};
}

std::vector<StartScript> loadStartScripts(const std::string& image, Profile profile) {
  std::vector<StartScript> out;
  for (const auto& bytes : findEmbeddedScripts(image)) {
    auto r = load(bytes, profile);
    if (!r.ok()) continue;
    out.push_back({identifyStartScript(*r.script), r.script});
  }
  return out;
}

void attachStartScripts(Machine& m, const std::vector<StartScript>& scripts) {
  for (const auto& s : scripts)
    if (!s.name.empty()) m.setScript(m.newVar(s.name), s.script);
}

}  // namespace gs2
