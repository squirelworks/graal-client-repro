// Engine controls from the 4.2.0.8 2D engine and the 3D plugin.
// TAdventure is the game object, not a control.
// Script-bound action names are installed by the line script.
// Hardcoded key bytes are onEngineKey.

#ifndef HOST4208_CONTROLS_HPP
#define HOST4208_CONTROLS_HPP

#include <string>
#include <vector>

bool logEngineControls(std::vector<std::string> &log, std::string &error);
void logLevelGaps(std::vector<std::string> &log);
void onEngineKey(int keyByte, int modifiers, std::vector<std::string> &log);
bool addKeysetAction(const std::string &name, std::vector<std::string> &log,
                     std::string &error);

#endif
