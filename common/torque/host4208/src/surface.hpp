// Residual Torque surface of the 4.2.0.8 engine DLL.
//
// torque/4208-engine.md: GuiCanvas, GuiControl and Point2I are present.
// The 4.2.0.8 engine manifest also links GBitmap and the GuiGraal names.
// There is no console, no SimObject and no TorqueScript. A script new of
// GuiGraalCtrl or GuiGraal3DCtrl is discarded; both names stay engine types.
// setContentControl is how a script object becomes the screen.
// MainMenuGui2D is the content installed when setup passes.
//
// This runner is not a Torque console. It does not execute TorqueScript.

#ifndef HOST4208_SURFACE_HPP
#define HOST4208_SURFACE_HPP

#include <string>
#include <vector>

struct SurfaceResult {
  bool contentSet;
  std::string contentLine;
  std::vector<std::string> log;
};

bool runSurfaceFile(const std::string &path, SurfaceResult &out, std::string &error);

#endif
