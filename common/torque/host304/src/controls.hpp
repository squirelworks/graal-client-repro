// Control classes 3.04 registers. GuiGraalCtrl is the level view.
// GuiControlProfile is the profile type, not a visible control.
// Names are the class-rep list. This file does not instance the demo HUDs.

#ifndef HOST304_CONTROLS_HPP
#define HOST304_CONTROLS_HPP

#include <string>
#include <vector>

struct ControlClass {
  const char *name;
  const char *role;
  bool profile;
};

int controlClassCount();
const ControlClass *controlClasses();

// Logs one line per class. Returns false when the table is short.
bool logRegisteredControls(std::vector<std::string> &log, std::string &error);

#endif
