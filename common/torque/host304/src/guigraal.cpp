#include "guigraal.hpp"

#include <sstream>

namespace {

void stubLog(std::vector<std::string> &log, const char *name, int argc) {
  std::ostringstream line;
  line << "GuiGraalCtrl." << name << " called argc=" << argc;
  log.push_back(line.str());
}

// provisional: body not yet known
void stub_moveUp(int argc, std::vector<std::string> &log) { stubLog(log, "moveUp", argc); }
// provisional: body not yet known
void stub_moveLeft(int argc, std::vector<std::string> &log) { stubLog(log, "moveLeft", argc); }
// provisional: body not yet known
void stub_moveDown(int argc, std::vector<std::string> &log) { stubLog(log, "moveDown", argc); }
// provisional: body not yet known
void stub_moveRight(int argc, std::vector<std::string> &log) { stubLog(log, "moveRight", argc); }
// provisional: body not yet known
void stub_doA(int argc, std::vector<std::string> &log) { stubLog(log, "doA", argc); }
// provisional: body not yet known
void stub_doS(int argc, std::vector<std::string> &log) { stubLog(log, "doS", argc); }
// provisional: body not yet known
void stub_doD(int argc, std::vector<std::string> &log) { stubLog(log, "doD", argc); }
// provisional: body not yet known
void stub_doQ(int argc, std::vector<std::string> &log) { stubLog(log, "doQ", argc); }
// provisional: body not yet known
void stub_doP(int argc, std::vector<std::string> &log) { stubLog(log, "doP", argc); }
// provisional: body not yet known
void stub_doM(int argc, std::vector<std::string> &log) { stubLog(log, "doM", argc); }
// provisional: body not yet known
void stub_doMicro(int argc, std::vector<std::string> &log) { stubLog(log, "doMicro", argc); }
// provisional: body not yet known
void stub_setChat(int argc, std::vector<std::string> &log) { stubLog(log, "setChat", argc); }
// provisional: body not yet known
void stub_setPassWord(int argc, std::vector<std::string> &log) { stubLog(log, "setPassWord", argc); }
// provisional: body not yet known
void stub_openServerList(int argc, std::vector<std::string> &log) {
  stubLog(log, "openServerList", argc);
}
// provisional: body not yet known
void stub_selectServer(int argc, std::vector<std::string> &log) { stubLog(log, "selectServer", argc); }
// provisional: body not yet known
void stub_selectServerCategory(int argc, std::vector<std::string> &log) {
  stubLog(log, "selectServerCategory", argc);
}
// provisional: body not yet known
void stub_startOfflineMode(int argc, std::vector<std::string> &log) {
  stubLog(log, "startOfflineMode", argc);
}
// provisional: body not yet known
void stub_connectToSelectedServer(int argc, std::vector<std::string> &log) {
  stubLog(log, "connectToSelectedServer", argc);
}
// provisional: body not yet known
void stub_serverDirectConnect(int argc, std::vector<std::string> &log) {
  stubLog(log, "serverDirectConnect", argc);
}
// provisional: body not yet known
void stub_privateMessageSend(int argc, std::vector<std::string> &log) {
  stubLog(log, "privateMessageSend", argc);
}
// provisional: body not yet known
void stub_playerListOpenPlayer(int argc, std::vector<std::string> &log) {
  stubLog(log, "playerListOpenPlayer", argc);
}
// provisional: body not yet known
void stub_playerListProfile(int argc, std::vector<std::string> &log) {
  stubLog(log, "playerListProfile", argc);
}
// provisional: body not yet known
void stub_updateLoadLevelFields(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateLoadLevelFields", argc);
}
// provisional: body not yet known
void stub_loadLevel(int argc, std::vector<std::string> &log) { stubLog(log, "loadLevel", argc); }
// provisional: body not yet known
void stub_updatePlayerProfile(int argc, std::vector<std::string> &log) {
  stubLog(log, "updatePlayerProfile", argc);
}
// provisional: body not yet known
void stub_updatePlayerMuted(int argc, std::vector<std::string> &log) {
  stubLog(log, "updatePlayerMuted", argc);
}
// provisional: body not yet known
void stub_updateMidiVolume(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateMidiVolume", argc);
}
// provisional: body not yet known
void stub_updateMp3Volume(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateMp3Volume", argc);
}
// provisional: body not yet known
void stub_updateRadioVolume(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateRadioVolume", argc);
}
// provisional: body not yet known
void stub_updateMicroActivationLevel(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateMicroActivationLevel", argc);
}
// provisional: body not yet known
void stub_updateGraalOptions(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateGraalOptions", argc);
}

struct StubFn {
  const char *name;
  void (*fn)(int, std::vector<std::string> &);
};

const StubFn kStubs[] = {
    {"moveUp", stub_moveUp},
    {"moveLeft", stub_moveLeft},
    {"moveDown", stub_moveDown},
    {"moveRight", stub_moveRight},
    {"doA", stub_doA},
    {"doS", stub_doS},
    {"doD", stub_doD},
    {"doQ", stub_doQ},
    {"doP", stub_doP},
    {"doM", stub_doM},
    {"doMicro", stub_doMicro},
    {"setChat", stub_setChat},
    {"setPassWord", stub_setPassWord},
    {"openServerList", stub_openServerList},
    {"selectServer", stub_selectServer},
    {"selectServerCategory", stub_selectServerCategory},
    {"startOfflineMode", stub_startOfflineMode},
    {"connectToSelectedServer", stub_connectToSelectedServer},
    {"serverDirectConnect", stub_serverDirectConnect},
    {"privateMessageSend", stub_privateMessageSend},
    {"playerListOpenPlayer", stub_playerListOpenPlayer},
    {"playerListProfile", stub_playerListProfile},
    {"updateLoadLevelFields", stub_updateLoadLevelFields},
    {"loadLevel", stub_loadLevel},
    {"updatePlayerProfile", stub_updatePlayerProfile},
    {"updatePlayerMuted", stub_updatePlayerMuted},
    {"updateMidiVolume", stub_updateMidiVolume},
    {"updateMp3Volume", stub_updateMp3Volume},
    {"updateRadioVolume", stub_updateRadioVolume},
    {"updateMicroActivationLevel", stub_updateMicroActivationLevel},
    {"updateGraalOptions", stub_updateGraalOptions},
};

} // namespace

void runGuiStub(const std::string &name, int argc, std::vector<std::string> &log) {
  const int n = static_cast<int>(sizeof(kStubs) / sizeof(kStubs[0]));
  for (int i = 0; i < n; ++i) {
    if (name == kStubs[i].name) {
      kStubs[i].fn(argc, log);
      return;
    }
  }
  stubLog(log, name.c_str(), argc);
}

namespace {

const GuiMethod kMethods[] = {
    {"moveUp", 3, 3},
    {"moveLeft", 3, 3},
    {"moveDown", 3, 3},
    {"moveRight", 3, 3},
    {"doA", 3, 3},
    {"doS", 3, 3},
    {"doD", 3, 3},
    {"doQ", 3, 3},
    {"doP", 3, 3},
    {"doM", 3, 3},
    {"doMicro", 3, 3},
    {"setChat", 3, 3},
    {"setPassWord", 3, 3},
    {"openServerList", 2, 2},
    {"selectServer", 3, 3},
    {"selectServerCategory", 3, 3},
    {"startOfflineMode", 2, 2},
    {"connectToSelectedServer", 2, 2},
    {"serverDirectConnect", 3, 3},
    {"privateMessageSend", 2, 2},
    {"playerListOpenPlayer", 3, 3},
    {"playerListProfile", 3, 3},
    {"updateLoadLevelFields", 2, 2},
    {"loadLevel", 5, 5},
    {"updatePlayerProfile", 12, 12},
    {"updatePlayerMuted", 3, 3},
    {"updateMidiVolume", 2, 2},
    {"updateMp3Volume", 2, 2},
    {"updateRadioVolume", 2, 2},
    {"updateMicroActivationLevel", 2, 2},
    {"updateGraalOptions", 2, 2},
};

} // namespace

int guiMethodCount() {
  return static_cast<int>(sizeof(kMethods) / sizeof(kMethods[0]));
}

const GuiMethod *guiMethods() { return kMethods; }

const GuiMethod *findGuiMethod(const std::string &name) {
  const int n = guiMethodCount();
  for (int i = 0; i < n; ++i) {
    if (name == kMethods[i].name) {
      return &kMethods[i];
    }
  }
  return 0;
}

int guiScriptArgs(const GuiMethod &method) {
  if (method.minCount != method.maxCount) {
    return -1;
  }
  return method.minCount - 2;
}
