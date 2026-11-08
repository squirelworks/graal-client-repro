#include "controls.hpp"

#include <sstream>

namespace {

struct ControlClass {
  const char *name;
  const char *role;
  bool profile;
};

const ControlClass kControls[] = {
    {"GuiCanvas", "root canvas", false},
    {"GuiControl", "base control", false},
    {"GuiGraalCtrl", "2D level view", false},
    {"GuiTextEditCtrl", "text field", false},
    {"GuiTextCtrl", "label", false},
    {"GuiMLTextCtrl", "markup text", false},
    {"GuiMLTextEditCtrl", "markup edit", false},
    {"GuiButtonCtrl", "button", false},
    {"GuiButtonBaseCtrl", "button base", false},
    {"GuiBitmapButtonCtrl", "bitmap button", false},
    {"GuiCheckBoxCtrl", "check", false},
    {"GuiRadioCtrl", "radio", false},
    {"GuiWindowCtrl", "window", false},
    {"GuiTabCtrl", "tab", false},
    {"GuiFrameSetCtrl", "frame set", false},
    {"GuiScrollCtrl", "scroll", false},
    {"GuiTextListCtrl", "text list", false},
    {"GuiTreeViewCtrl", "tree", false},
    {"GuiPopUpMenuCtrl", "popup menu", false},
    {"GuiPopUpEditCtrl", "popup edit", false},
    {"GuiContextMenuCtrl", "context menu", false},
    {"GuiMenuCtrl", "menu", false},
    {"GuiBitmapCtrl", "bitmap", false},
    {"GuiBitmapBorderCtrl", "bitmap border", false},
    {"GuiStretchCtrl", "stretch image", false},
    {"GuiProgressCtrl", "progress", false},
    {"GuiSliderCtrl", "slider", false},
    {"GuiArrayCtrl", "array", false},
    {"GuiShowImgCtrl", "show-img display", false},
    {"GuiDrawingPanel", "script drawing surface", false},
    {"GuiFlash", "flash movie", false},
    {"GuiBrowserCtrl", "embedded browser", false},
    {"GuiPMCtrl", "private-message view", false},
    {"GuiPMEditCtrl", "private-message edit", false},
    {"GuiPMHistoryCtrl", "private-message history", false},
    {"GuiCursor", "cursor", false},
    {"GuiControlProfile", "profile type", true},
    {"GuiGraal3DCtrl", "3D level control", false},
    {"GuiTSCtrl", "Torque shape view", false},
    {"GuiMapOverviewCtrl", "map overview", false},
    {"GuiPlayerView", "player preview", false},
    {"GuiShapeNameHud", "Torque name HUD", false},
    {"GuiInputCtrl", "Torque input", false},
    {"GuiGroup", "Torque group", false},
    {"GuiDataGroup", "Torque data group", false},
};

const char *kCallbacks[] = {
    "graal_setDraw2DTile",
    "graal_setClear2DTile",
    "graal_setDraw3DTile",
    "graal_setClear3DTile",
    "graal_setStartTilesDrawing",
    "graal_setDrawTilesOnScreen",
    "graal_setEndTilesDrawing",
    "graal_setScrollTilesBuffer",
    "graal_setDrawText",
    "graal_setDrawShadowedText",
    "graal_setCreateDrawingPanel",
    "graal_setOpenExternalPlayerlist",
    "graal_setOpenExternalOptions",
    "graal_setOpenExternalPM",
    "graal_setOpenExternalProfile",
    "graal_setOpenExternalLogWindow",
    "graal_setOpenMessageBox",
    "graal_setOpenURL",
    "graal_setStartGraal3D",
    "graal_setGetVirtualKeyCode",
    "graal_setGetGraalActionKeyText",
    "graal_setSetGraalStatusIcons",
};

// provisional: look up ChatBar and leave its parent unsettled
void gapChatParent(std::vector<std::string> &log) {
  log.push_back("stub chat parent: ChatBar lookup, parent unsettled");
}

// provisional: keep GUIContainer3D as a name without a recovered tree
void gap3DLayout(std::vector<std::string> &log) {
  log.push_back("stub 3D layout: GUIContainer3D name only");
}

// provisional: leave the chat bar without a recovered rectangle
void gapChatGeometry(std::vector<std::string> &log) {
  log.push_back("stub chat geometry: no rectangle in a GUI resource");
}

// provisional: leave hearts as property strings on graal_setSetGraalStatusIcons
void gapHearts(std::vector<std::string> &log) {
  log.push_back("stub hearts: no HUD control");
}

// provisional: leave showimg and gani unconnected to paintGraphics
void gapShowimg(std::vector<std::string> &log) {
  log.push_back("stub showimg: GuiShowImgCtrl is not tied to paintGraphics");
}

// provisional: call renderGraal from the level paint without naming each callee
void gapRenderGraal(std::vector<std::string> &log) {
  log.push_back("GuiGraalCtrl paint: renderGraal, then child controls");
}

// provisional: leave the two extra mouse slots unnamed
void gapMousePair(std::vector<std::string> &log) {
  log.push_back("stub mouse slots: right-button versus drag is open");
}

// provisional: keep both the Delphi options form and the scripted options window
void gapOptionsUi(std::vector<std::string> &log) {
  log.push_back("stub options: TOptions and StartScript_OptionsWindow both exist");
}

} // namespace

bool logEngineControls(std::vector<std::string> &log, std::string &error) {
  const int n = static_cast<int>(sizeof(kControls) / sizeof(kControls[0]));
  if (n != 45) {
    error = "engine control table is not 45 classes";
    return false;
  }
  bool sawLevel = false;
  bool sawProfile = false;
  for (int i = 0; i < n; ++i) {
    if (kControls[i].profile) {
      log.push_back(std::string("registered profile ") + kControls[i].name);
      sawProfile = true;
    } else {
      log.push_back(std::string("registered control ") + kControls[i].name + " (" +
                    kControls[i].role + ")");
    }
    if (std::string(kControls[i].name) == "GuiGraalCtrl") {
      sawLevel = true;
    }
  }
  if (!sawLevel || !sawProfile) {
    error = "GuiGraalCtrl or GuiControlProfile missing";
    return false;
  }
  log.push_back("registered game object TAdventure");
  const int callbacks = static_cast<int>(sizeof(kCallbacks) / sizeof(kCallbacks[0]));
  for (int i = 0; i < callbacks; ++i) {
    log.push_back(std::string("registered host callback ") + kCallbacks[i]);
  }
  return true;
}

void logLevelGaps(std::vector<std::string> &log) {
  gapRenderGraal(log);
  gapChatParent(log);
  gapChatGeometry(log);
  gap3DLayout(log);
  gapHearts(log);
  gapShowimg(log);
  gapMousePair(log);
  gapOptionsUi(log);
}

void onEngineKey(int keyByte, int modifiers, std::vector<std::string> &log) {
  std::ostringstream line;
  if (keyByte == 0x1B) {
    log.push_back("hardcoded key byte 0x1B: escape");
    return;
  }
  if (keyByte == 0x1A || keyByte == 0x1C) {
    line << "hardcoded key byte 0x" << std::hex << keyByte << ": consumed, name unknown";
    log.push_back(line.str());
    return;
  }
  if ((modifiers & 0x0C) != 0 && keyByte >= 0x21 && keyByte <= 0x3A) {
    log.push_back("hardcoded emoticon band: consumed");
    return;
  }
  if (keyByte == 0x32 || keyByte == 0x15 || keyByte == 0x03) {
    line << "hardcoded key byte 0x" << std::hex << keyByte << ": consumed, name unknown";
    log.push_back(line.str());
    return;
  }
  if (keyByte == 0x20) {
    log.push_back("hardcoded key byte 0x20");
    return;
  }
  log.push_back("key byte left the hardcoded path for the keyset");
}

bool addKeysetAction(const std::string &name, std::vector<std::string> &log,
                     std::string &error) {
  if (name.empty()) {
    error = "keyset action needs a name";
    return false;
  }
  log.push_back("script-bound action " + name);
  return true;
}
