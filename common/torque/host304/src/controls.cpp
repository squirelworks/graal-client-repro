#include "controls.hpp"

namespace {

// Order follows the 3.04 class-rep list. The Graal UI instances the
// classes through GuiInputCtrl. The rest are stock and still registered.
const ControlClass kControls[] = {
    {"GuiGraalCtrl", "Graal level view", false},
    {"GuiControl", "stock parent", false},
    {"GuiTextCtrl", "stock label", false},
    {"GuiTextEditCtrl", "chat bar and account fields", false},
    {"GuiMLTextCtrl", "server-list account blurb", false},
    {"GuiMLTextEditCtrl", "multi-line edit", false},
    {"GuiButtonCtrl", "menu and server-list buttons", false},
    {"GuiCheckBoxCtrl", "options check", false},
    {"GuiRadioCtrl", "options radio", false},
    {"GuiSliderCtrl", "options volume slider", false},
    {"GuiPopUpMenuCtrl", "language box", false},
    {"GuiScrollCtrl", "server list and player list scroll", false},
    {"GuiTextListCtrl", "server list and player list", false},
    {"GuiBitmapCtrl", "player-list fill", false},
    {"GuiBitmapBorderCtrl", "player-list frame", false},
    {"GuiChunkedBitmapCtrl", "start screen and server-list background", false},
    {"GuiWindowCtrl", "window", false},
    {"GuiProgressCtrl", "progress", false},
    {"GuiInputCtrl", "Torque input sink", false},
    {"GuiCanvas", "stock root canvas", false},
    {"GuiCursor", "stock cursor", false},
    {"GuiConsole", "stock console", false},
    {"GuiConsoleEditCtrl", "stock console edit", false},
    {"GuiConsoleTextCtrl", "stock console text", false},
    {"GuiMenuBar", "stock menu bar", false},
    {"GuiEditCtrl", "stock GUI editor", false},
    {"GuiArrayCtrl", "stock array", false},
    {"GuiInspector", "stock inspector", false},
    {"GuiFilterCtrl", "stock filter", false},
    {"GuiNoMouseCtrl", "stock no-mouse", false},
    {"GuiFrameSetCtrl", "stock frame set", false},
    {"GuiTreeViewCtrl", "stock tree", false},
    {"GuiBackgroundCtrl", "stock background", false},
    {"GuiBubbleTextCtrl", "stock chat bubble", false},
    {"GuiButtonBaseCtrl", "stock button base", false},
    {"GuiMouseEventCtrl", "stock mouse event", false},
    {"GuiBorderButtonCtrl", "stock border button", false},
    {"GuiControlListPopUp", "stock list popup", false},
    {"GuiMessageVectorCtrl", "stock message vector", false},
    {"GuiTextEditSliderCtrl", "stock text-edit slider", false},
    {"GuiAviBitmapCtrl", "compiled in, not in the Graal UI", false},
    {"GuiClockHud", "Torque demo HUD, not in the Graal UI", false},
    {"GuiCrossHairHud", "Torque demo HUD, not in the Graal UI", false},
    {"GuiHealthBarHud", "Torque demo HUD, not in the Graal UI", false},
    {"GuiShapeNameHud", "Torque demo HUD, not in the Graal UI", false},
    {"GuiTSCtrl", "Torque scene view, not in the Graal UI", false},
    {"GuiTerrPreviewCtrl", "Torque terrain preview, not in the Graal UI", false},
    {"GuiControlProfile", "profile type", true},
};

} // namespace

int controlClassCount() {
  return static_cast<int>(sizeof(kControls) / sizeof(kControls[0]));
}

const ControlClass *controlClasses() { return kControls; }

bool logRegisteredControls(std::vector<std::string> &log, std::string &error) {
  const int n = controlClassCount();
  if (n != 48) {
    error = "control table is not 47 classes plus GuiControlProfile";
    return false;
  }
  bool sawLevel = false;
  bool sawProfile = false;
  for (int i = 0; i < n; ++i) {
    const ControlClass &c = kControls[i];
    if (c.profile) {
      log.push_back(std::string("registered profile ") + c.name);
      sawProfile = true;
    } else {
      log.push_back(std::string("registered control ") + c.name + " (" + c.role + ")");
    }
    if (std::string(c.name) == "GuiGraalCtrl") {
      sawLevel = true;
    }
  }
  if (!sawLevel || !sawProfile) {
    error = "GuiGraalCtrl or GuiControlProfile missing from the control table";
    return false;
  }
  return true;
}
