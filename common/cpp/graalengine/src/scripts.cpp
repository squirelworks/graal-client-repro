// The start menus: the GS2 machine, the StartScript_* the player's own
// engine file carries, and the engine commands those scripts call.
//
// Order and lifetime from Graal_analysis torque/4208-engine.md, "The order
// StartScript objects are created": Profiles is run and dropped; the canvas
// comes next; MainMenu (when the setup test passes) and `MainMenuGui2D`
// becomes the content; then OptionsWindow, PlayerProfile, LoadLevelGui,
// QuitDialog, MessageBoxDialog, SelectFileDialog are kept; MoveMap2D and
// MoveMap3D are run and dropped. Each kept one is made only if the
// universe has no variable of that name yet. StartScript_GraalGui comes
// with offline mode and the 2D connect (content `GUIContainer`),
// StartScript_GraalGui3D with the 3D connect.
#include "engine.hpp"
#include "session.hpp"

#include "host.hpp"
#include "startscripts.hpp"

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iterator>

namespace graalengine {

namespace {

std::string readFile(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return {};
  return std::string(std::istreambuf_iterator<char>(in), {});
}

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

}  // namespace

bool Engine::keyHeld(int vk) const { return vk >= 0 && vk < 256 && keys_[vk]; }

void Engine::enableScriptedControls(bool on) {
  scriptedControls_ = on;
  if (machine_) machine_->universe()->childOrCreate("scriptedcontrols")->setNumber(on ? 1 : 0);
}

void Engine::startMachine() {
  machine_ = std::make_unique<gs2::Machine>(profile_);
  machine_->universe()->childOrCreate("scriptedcontrols")->setNumber(scriptedControls_ ? 1 : 0);
  gs2::EngineHost h;
  h.log = [this](const std::string& line) { log(line); };
  h.openUrl = [](const std::string& url) { host::OpenURL(url.c_str()); };
  h.keyDown = [this](int vk) { return keyHeld(vk); };
  // The launcher's window is the screen; the original lists the display
  // modes DirectDraw offers. Until a slot asks for those, the current size.
  h.resolutionList = [](const std::string&) {
    const int w = host::GetScreenWidth() > 0 ? host::GetScreenWidth() : 640;
    const int hh = host::GetScreenHeight() > 0 ? host::GetScreenHeight() : 480;
    return std::vector<std::string>{std::to_string(w) + "x" + std::to_string(hh)};
  };
  addAdventureCommands(h);
  gs2::addEngineCommands(*machine_, std::move(h));
}

void Engine::addAdventureCommands(gs2::EngineHost& h) {
  using gs2::Machine;
  using gs2::Value;
  using gs2::Var;
  auto text = [](Machine& m, std::vector<Value>& a, std::size_t i) {
    return i < a.size() ? m.toString(a[i]) : std::string();
  };
  auto setter = [this, text](std::string Account::*field) {
    return [this, text, field](Machine& m, Var&, std::vector<Value>& a) {
      account_.*field = text(m, a, 0);
      return Value::number(0);
    };
  };
  h.adventure["Adventure_setAccountName"] = setter(&Account::account);
  h.adventure["Adventure_setPassWord"] = setter(&Account::password);
  h.adventure["Adventure_setNickName"] = setter(&Account::nickname);
  // The chat bar's text: the player's chat once a session is up.
  h.adventure["Adventure_setChat"] = [this, text](Machine& m, Var&, std::vector<Value>& a) {
    account_.chat = text(m, a, 0);
    if (session_) session_->say(account_.chat);
    return Value::number(0);
  };
  // The profile, account-field, volume and mute calls: kept by name until
  // the session sends them on.
  for (const char* name : {"Adventure_updatePlayerProfile", "Adventure_updateAccountField",
                           "Adventure_updatePlayerMuted", "Adventure_updateMidiVolume",
                           "Adventure_updateMp3Volume", "Adventure_updateRadioVolume",
                           "Adventure_updateMicroActivationLevel"}) {
    const std::string key = name;
    h.adventure[key] = [this, key, text](Machine& m, Var&, std::vector<Value>& a) {
      std::vector<std::string> args;
      for (std::size_t i = 0; i < a.size(); ++i) args.push_back(text(m, a, i));
      account_.fields[key] = std::move(args);
      return Value::number(0);
    };
  }
  h.adventure["Adventure_openServerList"] = [this](Machine&, Var&, std::vector<Value>&) {
    openServerList();
    return Value::number(0);
  };
  h.adventure["Adventure_startOfflineMode"] = [this](Machine&, Var&, std::vector<Value>&) {
    startOffline();
    return Value::number(0);
  };
  h.adventure["Adventure_openExternalOptions"] = [](Machine&, Var&, std::vector<Value>&) {
    host::OpenExternalOptions();
    return Value::number(0);
  };
  h.adventure["Adventure_selectPath"] = [text](Machine& m, Var&, std::vector<Value>& a) {
    host::ShowSelectPathDialog(text(m, a, 0).c_str());
    return Value::number(0);
  };
  // The 5.x setup dialog's only use is extractFileBase of it compared with
  // "setup", so it names the running program: the exe path the launcher
  // gave graal_engineInitialize (the rebuild's reading).
  h.adventure["Adventure_getInstallationPath"] = [this](Machine&, Var&, std::vector<Value>&) {
    return Value::string(exePath_);
  };
  h.adventure["Adventure_quit"] = [](Machine&, Var&, std::vector<Value>&) {
    host::PrepareShutdownGraal();
    host::ShutdownGraal();
    return Value::number(0);
  };
  // Not registered yet, so a script calling one gets the engines' "not
  // found" error: Adventure_saveGraalOptions, Adventure_installGraal and
  // the Adventure_selectFile* calls of the file dialog.
}

std::string Engine::startScriptFile() const {
  if (const char* env = std::getenv("GRAAL_ENGINE_FILE"); env && *env) return env;
  for (const std::string& p : {installDir() + "/GraalEngine.dll", exePath_}) {
    if (p.empty()) continue;
    std::ifstream in(p, std::ios::binary);
    if (in) return p;
  }
  return {};
}

gs2::VarPtr Engine::runStartScript(const std::string& name, bool keep) {
  auto it = startScripts_.find(lower(name));
  if (it == startScripts_.end() || !machine_) return nullptr;
  gs2::VarPtr var;
  if (keep) {
    if (machine_->universe()->child(name)) return machine_->universe()->child(name);
    var = machine_->newVar(name);
  } else {
    var = std::make_shared<gs2::Var>(name);
  }
  machine_->setScript(var, it->second);
  machine_->runDue();
  return var;
}

void Engine::setContentFrom(const std::string& objectName) {
  if (!canvas_) return;
  std::shared_ptr<Control> c;
  if (controlOf_ && machine_) {
    if (auto var = machine_->universe()->child(objectName)) c = controlOf_(var);
  }
  if (!c) c = std::make_shared<Control>(objectName);
  canvas_->setContentControl(std::move(c));
}

void Engine::loadStartMenus() {
  startScripts_.clear();
  startNames_.clear();
  const std::string file = startScriptFile();
  if (!file.empty()) {
    for (auto& s : gs2::loadStartScripts(readFile(file), profile_)) {
      if (s.name.empty() || !s.script) continue;
      startNames_.push_back(s.name);
      startScripts_[lower(s.name)] = s.script;
    }
  }
  if (startScripts_.empty()) {
    log("GraalEngine: no start scripts" + (file.empty() ? std::string() : " in " + file));
  } else {
    log("GraalEngine: " + std::to_string(startScripts_.size()) + " start scripts from " + file);
  }
  runStartScript("StartScript_Profiles", false);
  // The setup test: the rebuild has no install step, so it always passes.
  runStartScript("StartScript_MainMenu", true);
  if (controlOf_ || !canvas_->content()) setContentFrom("MainMenuGui2D");
  for (const char* n : {"StartScript_OptionsWindow", "StartScript_PlayerProfile", "StartScript_LoadLevelGui",
                        "StartScript_QuitDialog", "StartScript_MessageBoxDialog",
                        "StartScript_SelectFileDialog"}) {
    runStartScript(n, true);
  }
  runStartScript("StartScript_MoveMap2D", false);
  runStartScript("StartScript_MoveMap3D", false);
}

}  // namespace graalengine
