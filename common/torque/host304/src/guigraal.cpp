#include "guigraal.hpp"

#include <sstream>

namespace {

struct Play {
  bool open;
  bool awake;
  bool visible;
  bool gameView;
  bool chatFocus;
};

Play gPlay = {false, false, false, false, false};

void stubLog(std::vector<std::string> &log, const char *name, int argc) {
  std::ostringstream line;
  line << "GuiGraalCtrl." << name << " called argc=" << argc;
  log.push_back(line.str());
}

// provisional: read the make/break argument and enter the shared game move
void stub_moveUp(int argc, std::vector<std::string> &log) { stubLog(log, "moveUp", argc); }
// provisional: read the make/break argument and enter the shared game move
void stub_moveLeft(int argc, std::vector<std::string> &log) { stubLog(log, "moveLeft", argc); }
// provisional: read the make/break argument and enter the shared game move
void stub_moveDown(int argc, std::vector<std::string> &log) { stubLog(log, "moveDown", argc); }
// provisional: read the make/break argument and enter the shared game move
void stub_moveRight(int argc, std::vector<std::string> &log) { stubLog(log, "moveRight", argc); }
// provisional: read the make/break argument and enter the same game function as move
void stub_doA(int argc, std::vector<std::string> &log) { stubLog(log, "doA", argc); }
// provisional: read the make/break argument and enter the same game function as move
void stub_doS(int argc, std::vector<std::string> &log) { stubLog(log, "doS", argc); }
// provisional: read the make/break argument and enter the same game function as move
void stub_doD(int argc, std::vector<std::string> &log) { stubLog(log, "doD", argc); }
// provisional: read the make/break argument and enter the same game function as move
void stub_doQ(int argc, std::vector<std::string> &log) { stubLog(log, "doQ", argc); }
// provisional: read the make/break argument and enter the same game function as move
void stub_doP(int argc, std::vector<std::string> &log) { stubLog(log, "doP", argc); }
// provisional: read the make/break argument and enter the same game function as move
void stub_doM(int argc, std::vector<std::string> &log) { stubLog(log, "doM", argc); }
// provisional: read the make/break argument and enter the microphone game function
void stub_doMicro(int argc, std::vector<std::string> &log) { stubLog(log, "doMicro", argc); }
// provisional: hand the text to the game view, then run ChatBar.setText("")
void stub_setChat(int argc, std::vector<std::string> &log) {
  stubLog(log, "setChat", argc);
  log.push_back("ChatBar.setText(\"\")");
}
// provisional: take the password argument; the body was not read
void stub_setPassWord(int argc, std::vector<std::string> &log) {
  stubLog(log, "setPassWord", argc);
}
// provisional: the server-list GUI calls connect and category methods instead
void stub_openServerList(int argc, std::vector<std::string> &log) {
  stubLog(log, "openServerList", argc);
}
// provisional: select the server the list passed in
void stub_selectServer(int argc, std::vector<std::string> &log) {
  stubLog(log, "selectServer", argc);
}
// provisional: select server category 0, 1, 2, or 3
void stub_selectServerCategory(int argc, std::vector<std::string> &log) {
  stubLog(log, "selectServerCategory", argc);
}
// provisional: enter offline mode from the start button's switchToOfflineMode
void stub_startOfflineMode(int argc, std::vector<std::string> &log) {
  stubLog(log, "startOfflineMode", argc);
}
// provisional: connect from the server list alt command
void stub_connectToSelectedServer(int argc, std::vector<std::string> &log) {
  stubLog(log, "connectToSelectedServer", argc);
}
// provisional: connect using the direct-name field
void stub_serverDirectConnect(int argc, std::vector<std::string> &log) {
  stubLog(log, "serverDirectConnect", argc);
}
// provisional: send from the private-message GUI
void stub_privateMessageSend(int argc, std::vector<std::string> &log) {
  stubLog(log, "privateMessageSend", argc);
}
// provisional: open the player the player-list double-click named
void stub_playerListOpenPlayer(int argc, std::vector<std::string> &log) {
  stubLog(log, "playerListOpenPlayer", argc);
}
// provisional: open the profile for the player-list selection
void stub_playerListProfile(int argc, std::vector<std::string> &log) {
  stubLog(log, "playerListProfile", argc);
}
// provisional: fill the load-level dialog when it opens
void stub_updateLoadLevelFields(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateLoadLevelFields", argc);
}
// provisional: load the level from the five-argument dialog call
void stub_loadLevel(int argc, std::vector<std::string> &log) { stubLog(log, "loadLevel", argc); }
// provisional: write the player profile from the twelve-argument call
void stub_updatePlayerProfile(int argc, std::vector<std::string> &log) {
  stubLog(log, "updatePlayerProfile", argc);
}
// provisional: update the mute flag; the body was not read
void stub_updatePlayerMuted(int argc, std::vector<std::string> &log) {
  stubLog(log, "updatePlayerMuted", argc);
}
// provisional: apply the midi volume pref
void stub_updateMidiVolume(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateMidiVolume", argc);
}
// provisional: apply the mp3 volume pref
void stub_updateMp3Volume(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateMp3Volume", argc);
}
// provisional: apply the radio volume pref
void stub_updateRadioVolume(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateRadioVolume", argc);
}
// provisional: apply the microphone activation pref
void stub_updateMicroActivationLevel(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateMicroActivationLevel", argc);
}
// provisional: apply the options dialog
void stub_updateGraalOptions(int argc, std::vector<std::string> &log) {
  stubLog(log, "updateGraalOptions", argc);
}

// provisional: drop the game-view object this control created, then stock cleanup
void virt_destructor(std::vector<std::string> &log) {
  gPlay.gameView = false;
  log.push_back("GuiGraalCtrl destructor: game-view dropped");
}

// provisional: on stock wake success, print Graal activated! and build the game view
void virt_wake(std::vector<std::string> &log) {
  gPlay.awake = true;
  gPlay.visible = true;
  gPlay.gameView = true;
  log.push_back("Graal activated!");
  log.push_back("GuiGraalCtrl wake: game-view object built");
}

// provisional: release the object wake stored, then run stock sleep
void virt_sleep(std::vector<std::string> &log) {
  gPlay.awake = false;
  log.push_back("GuiGraalCtrl sleep: wake object released");
}

// provisional: walk the scene list, disable texture 2D, then render child controls
void virt_paint(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl paint: scene walk");
  log.push_back("GuiGraalCtrl paint: texture 2D disabled");
  log.push_back("GuiGraalCtrl paint: child controls");
}

// provisional: no tile blit was separated on the level-view paint
void gap_tiles(std::vector<std::string> &log) {
  log.push_back("stub tiles: no tile blit on the level-view paint");
}

// provisional: showimg and gani stay unconnected to this paint
void gap_showimg(std::vector<std::string> &log) {
  log.push_back("stub showimg: not tied to the level-view paint");
}

// provisional: playerhearts is a property string, not a control on this view
void gap_hearts(std::vector<std::string> &log) {
  log.push_back("stub hearts: playerhearts is not a HUD control");
}

// provisional: call the game-view function wake uses, then the shared render helper
void virt_prep(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl prep: game-view function, then shared render");
}

// provisional: forward the mouse event only when the fields are 1 and 0x102
void virt_mouseFiltered(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl mouse filtered: fields 1 and 0x102, doublemouse sink");
}

// provisional: forward mouse kind 0 into the sink that knows double and doublemouse
void virt_mouse0(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl mouse kind 0");
}

// provisional: forward mouse kind 1 into the sink that knows double and doublemouse
void virt_mouse1(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl mouse kind 1");
}

// provisional: forward mouse kind 2 into the sink that knows double and doublemouse
void virt_mouse2(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl mouse kind 2");
}

// provisional: if awake and visible, forward the event with flag 0 and consume it
void virt_event0(std::vector<std::string> &log) {
  if (gPlay.awake && gPlay.visible) {
    log.push_back("GuiGraalCtrl event slot flag 0: consumed");
  }
}

// provisional: if awake and visible, forward the event with flag 1 and consume it
void virt_event1(std::vector<std::string> &log) {
  if (gPlay.awake && gPlay.visible) {
    log.push_back("GuiGraalCtrl event slot flag 1: consumed");
  }
}

// provisional: event word 0x1500 runs only when two player fields are 1 and 2
void gap_event1500(std::vector<std::string> &log) {
  log.push_back("stub event 0x1500: player fields are not 1 and 2");
}

// provisional: search ChatBar from this control and accept an unsettled parent
void gap_chatParent(std::vector<std::string> &log) {
  log.push_back("ChatBar lookup from Adventure: found (parent unsettled)");
}

// provisional: run the command string after setting $ThisControl, else fire onAction
void virt_action(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl action: onAction");
}

// provisional: no Graal scroll override; chat history stays on the text edit
void virt_scroll(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl scroll: no override");
}

// provisional: ask the game view, then the stock key handler when it did not take the event
void virt_keySecond(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl second key slot: stock handler if the game view skips it");
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

struct VirtFn {
  const char *name;
  void (*fn)(std::vector<std::string> &);
};

const VirtFn kVirtuals[] = {
    {"destructor", virt_destructor},
    {"wake", virt_wake},
    {"sleep", virt_sleep},
    {"paint", virt_paint},
    {"tiles", gap_tiles},
    {"showimg", gap_showimg},
    {"hearts", gap_hearts},
    {"prep", virt_prep},
    {"mouseFiltered", virt_mouseFiltered},
    {"mouse0", virt_mouse0},
    {"mouse1", virt_mouse1},
    {"mouse2", virt_mouse2},
    {"event0", virt_event0},
    {"event1", virt_event1},
    {"event1500", gap_event1500},
    {"chatParent", gap_chatParent},
    {"action", virt_action},
    {"scroll", virt_scroll},
    {"keySecond", virt_keySecond},
};

void callVirt(const char *name, std::vector<std::string> &log) {
  const int n = static_cast<int>(sizeof(kVirtuals) / sizeof(kVirtuals[0]));
  for (int i = 0; i < n; ++i) {
    if (std::string(kVirtuals[i].name) == name) {
      kVirtuals[i].fn(log);
      return;
    }
  }
}

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

bool levelViewOpen() { return gPlay.open && gPlay.gameView; }

bool openLevelView(std::vector<std::string> &log, std::string &error) {
  if (gPlay.open) {
    error = "level view is already open";
    return false;
  }
  log.push_back("level view opened: Adventure (GuiGraalCtrl)");
  log.push_back("AdventureGui GuiControl extent 640 480");
  log.push_back("ChatBar GuiTextEditCtrl");
  callVirt("wake", log);
  callVirt("chatParent", log);
  log.push_back("moveMap pushed");
  callVirt("prep", log);
  callVirt("paint", log);
  callVirt("tiles", log);
  callVirt("showimg", log);
  callVirt("hearts", log);
  callVirt("mouseFiltered", log);
  callVirt("mouse0", log);
  callVirt("mouse1", log);
  callVirt("mouse2", log);
  callVirt("event0", log);
  callVirt("event1", log);
  callVirt("event1500", log);
  callVirt("action", log);
  callVirt("scroll", log);
  callVirt("keySecond", log);
  gPlay.open = true;
  // Keep the destructor and sleep stubs linked and runnable.
  if (kVirtuals[0].name == 0 || kVirtuals[2].name == 0) {
    error = "virtual table is missing destructor or sleep";
    return false;
  }
  return true;
}

void onHardcodedKey(int keyByte, int modifiers, std::vector<std::string> &log) {
  if (!gPlay.gameView) {
    log.push_back("hardcoded key ignored: level view has no game view");
    return;
  }
  // Key byte 2, modifier mask 0x30 clear: chat focus. Not a bind-file key.
  if (keyByte == 2 && (modifiers & 0x30) == 0) {
    gPlay.chatFocus = !gPlay.chatFocus;
    log.push_back(gPlay.chatFocus ? "hardcoded key byte 2: ChatBar focus on"
                                  : "hardcoded key byte 2: ChatBar focus off");
    return;
  }
  // Ctrl or Alt (bits 0x0C) plus a letter-range key, chat focus clear.
  if (gPlay.gameView && !gPlay.chatFocus && (modifiers & 0x0C) != 0 && keyByte >= 0x21 &&
      keyByte <= 0x3A) {
    log.push_back("hardcoded emoticon: consumed");
    return;
  }
  // Modifier mask 0x30 together with key byte 0x19. The key name is unknown.
  if ((modifiers & 0x30) != 0 && keyByte == 0x19) {
    log.push_back("hardcoded key byte 0x19 modifier 0x30: consumed");
    return;
  }
  callVirt("keySecond", log);
  log.push_back("key byte left the hardcoded path for the action map");
}
