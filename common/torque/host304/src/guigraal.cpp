#include "guigraal.hpp"

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
