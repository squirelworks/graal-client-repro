// Input split for the 3.04 level view.
//
// Script-bound keys are strings the TorqueScript file installs on
// moveMap or GlobalActionMap. This header does not list them.
// Hardcoded key bytes live on GuiGraalCtrl (guigraal.hpp).

#ifndef HOST304_INPUT_HPP
#define HOST304_INPUT_HPP

#include <string>
#include <vector>

bool addScriptBind(const std::string &map, const std::string &key,
                   const std::string &command, std::vector<std::string> &log,
                   std::string &error);

bool fireScriptBind(const std::string &map, const std::string &key,
                    std::vector<std::string> &log, std::string &error);

int scriptBindCount(const std::string &map);

#endif
