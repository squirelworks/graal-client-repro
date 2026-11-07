// A line runner for one TorqueScript file. Not a Torque console.
//
// It loads the file, runs a camera-move statement, and logs the call.
// Other lines are either a GuiGraalCtrl stub or a console stub.
// No opcodes, no .dso, no sim set, no schedule.

#ifndef HOST304_SCRIPT_HPP
#define HOST304_SCRIPT_HPP

#include <string>
#include <vector>

struct ScriptResult {
  bool cameraMoved;
  bool levelOpened;
  std::string cameraLine;
  std::vector<std::string> log;
};

// Adventure is already registered. The script may call its methods.
bool runScriptFile(const std::string &path, ScriptResult &out,
                   std::string &error);

#endif
