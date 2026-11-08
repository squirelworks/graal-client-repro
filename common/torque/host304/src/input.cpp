#include "input.hpp"

#include "guigraal.hpp"

#include <map>
#include <utility>

namespace {

struct Bind {
  std::string command;
};

std::map<std::pair<std::string, std::string>, Bind> gBinds;

// provisional: push optionsDlg from the F3 bind
void cmdBringUpOptions(std::vector<std::string> &log) {
  log.push_back("script command bringUpOptions: push optionsDlg");
}

// provisional: open the load-level dialog; which key calls it is not settled
void cmdShowLoadLevel(std::vector<std::string> &log) {
  log.push_back("script command showLoadLevel: key unsettled");
}

// provisional: open the player list from the F7 bind
void cmdShowPlayerList(std::vector<std::string> &log) {
  log.push_back("script command showPlayerList");
}

// provisional: put ServerListGui on the canvas from the F8 bind
void cmdShowServerList(std::vector<std::string> &log) {
  log.push_back("script command showServerList: Canvas.setContent(ServerListGui)");
}

// provisional: open the quit dialog from the escape bind
void cmdEscapeFromGame(std::vector<std::string> &log) {
  log.push_back("script command escapeFromGame: quit dialog");
}

// provisional: open context help from GlobalActionMap
void cmdContextHelp(std::vector<std::string> &log) {
  log.push_back("script command contextHelp");
}

// provisional: toggle the stock console from GlobalActionMap
void cmdToggleConsole(std::vector<std::string> &log) {
  log.push_back("script command ToggleConsole");
}

// provisional: toggle fullscreen from the GlobalActionMap alt-enter bind
void cmdToggleFullScreen(std::vector<std::string> &log) {
  log.push_back("script command toggleFullScreen");
}

struct ScriptCmd {
  const char *name;
  void (*fn)(std::vector<std::string> &);
};

const ScriptCmd kScriptCmds[] = {
    {"bringUpOptions", cmdBringUpOptions},
    {"showLoadLevel", cmdShowLoadLevel},
    {"showPlayerList", cmdShowPlayerList},
    {"showServerList", cmdShowServerList},
    {"escapeFromGame", cmdEscapeFromGame},
    {"contextHelp", cmdContextHelp},
    {"ToggleConsole", cmdToggleConsole},
    {"toggleFullScreen", cmdToggleFullScreen},
};

void runScriptCommand(const std::string &command, std::vector<std::string> &log) {
  if (findGuiMethod(command) != 0) {
    log.push_back("script-bound command " + command);
    runGuiStub(command, 1, log);
    return;
  }
  const int n = static_cast<int>(sizeof(kScriptCmds) / sizeof(kScriptCmds[0]));
  for (int i = 0; i < n; ++i) {
    if (command == kScriptCmds[i].name) {
      kScriptCmds[i].fn(log);
      return;
    }
  }
  log.push_back("script command stub: " + command);
}

} // namespace

bool addScriptBind(const std::string &map, const std::string &key,
                   const std::string &command, std::vector<std::string> &log,
                   std::string &error) {
  if (map.empty() || key.empty() || command.empty()) {
    error = "a script bind needs a map, a key and a command";
    return false;
  }
  gBinds[std::make_pair(map, key)] = Bind{command};
  log.push_back("script bind: " + map + " " + key + " -> " + command);
  return true;
}

bool fireScriptBind(const std::string &map, const std::string &key,
                    std::vector<std::string> &log, std::string &error) {
  const std::map<std::pair<std::string, std::string>, Bind>::iterator it =
      gBinds.find(std::make_pair(map, key));
  if (it == gBinds.end()) {
    error = "no script bind for " + map + " " + key;
    return false;
  }
  log.push_back("script bind fired: " + map + " " + key + " -> " + it->second.command);
  runScriptCommand(it->second.command, log);
  return true;
}

int scriptBindCount(const std::string &map) {
  int n = 0;
  for (std::map<std::pair<std::string, std::string>, Bind>::const_iterator it = gBinds.begin();
       it != gBinds.end(); ++it) {
    if (it->first.first == map) {
      ++n;
    }
  }
  return n;
}
