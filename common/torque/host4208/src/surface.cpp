#include "surface.hpp"

#include <fstream>

namespace {

std::string trim(const std::string &s) {
  std::size_t a = 0;
  while (a < s.size() && (s[a] == ' ' || s[a] == '\t' || s[a] == '\r')) {
    ++a;
  }
  std::size_t b = s.size();
  while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t' || s[b - 1] == '\r')) {
    --b;
  }
  return s.substr(a, b - a);
}

std::string stripSemi(std::string s) {
  s = trim(s);
  if (!s.empty() && s[s.size() - 1] == ';') {
    s.erase(s.size() - 1);
  }
  return trim(s);
}

bool execLine(const std::string &raw, bool &canvas, SurfaceResult &out, std::string &error) {
  const std::string line = stripSemi(raw);
  if (line.empty() || line.compare(0, 2, "//") == 0) {
    return true;
  }

  const std::string neu2 = "new GuiGraalCtrl(";
  const std::string neu3 = "new GuiGraal3DCtrl(";
  if (line.compare(0, neu2.size(), neu2) == 0 || line.compare(0, neu3.size(), neu3) == 0) {
    const char *which =
        line.compare(0, neu3.size(), neu3) == 0 ? "GuiGraal3DCtrl" : "GuiGraalCtrl";
    // The script builder discards these names. The type stays registered.
    out.log.push_back(std::string("discarded new ") + which +
                      " (script does not construct it)");
    return true;
  }

  const std::string setc = "setContentControl(";
  if (line.compare(0, setc.size(), setc) == 0 && line[line.size() - 1] == ')') {
    if (!canvas) {
      error = "setContentControl with no GuiCanvas";
      return false;
    }
    const std::string name = trim(line.substr(setc.size(), line.size() - setc.size() - 1));
    if (name.empty()) {
      error = "setContentControl needs a name";
      return false;
    }
    out.contentLine = "canvas content: " + name;
    out.contentSet = true;
    out.log.push_back(out.contentLine);
    return true;
  }

  out.log.push_back("residual stub: " + line);
  return true;
}

} // namespace

bool runSurfaceFile(const std::string &path, SurfaceResult &out, std::string &error) {
  out.contentSet = false;
  out.contentLine.clear();
  out.log.clear();

  // Boot order from the engine note: the canvas exists before content is set.
  // Point2I and GBitmap are linked. No size and no pixels are recovered here.
  bool canvas = true;
  out.log.push_back(
      "registered residual surface: GuiCanvas, GuiControl, Point2I, GBitmap");
  out.log.push_back("Point2I registered (no size recovered this pass)");
  out.log.push_back("GBitmap registered (this DLL does not draw pixels)");
  out.log.push_back(
      "registered engine types GuiGraalCtrl, GuiGraal3DCtrl "
      "(a script new of either is discarded)");
  out.log.push_back("TorqueScript is not run (no console and no .dso in this engine)");
  out.log.push_back("GuiCanvas created");

  std::ifstream in(path.c_str());
  if (!in) {
    error = "could not open " + path;
    return false;
  }
  std::string line;
  int number = 0;
  while (std::getline(in, line)) {
    ++number;
    if (!execLine(line, canvas, out, error)) {
      error = path + ":" + std::to_string(number) + ": " + error;
      return false;
    }
  }
  if (!out.contentSet) {
    error = "script did not set canvas content";
    return false;
  }
  return true;
}
