#include "surface.hpp"

#include "controls.hpp"

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

// provisional: open the named level on TServerLevel
void stubOpenLevel(SurfaceResult &out, const std::string &name) {
  out.levelOpened = true;
  out.log.push_back("level opened: TServerLevel " + name);
  out.log.push_back("TServerLevel.openLevel called " + name);
  out.log.push_back("GuiGraalCtrl is the level view");
  logLevelGaps(out.log);
}

// provisional: record the tile and leave the blit to graal_setDraw2DTile
void stubPlaceTile(SurfaceResult &out, const std::string &x, const std::string &y,
                   const std::string &tile) {
  out.tilePlaced = true;
  out.tileLine = "tile placed " + x + " " + y + " " + tile;
  out.log.push_back("TServerLevel.placeTile called " + x + " " + y + " " + tile);
  out.log.push_back(out.tileLine);
  out.log.push_back("stub graal_setDraw2DTile: blit from paintGraphics was not followed");
}

// provisional: log a residual line the runner does not execute
void stubOther(SurfaceResult &out, const std::string &line) {
  out.log.push_back("residual stub: " + line);
}

std::string unquote(std::string s) {
  s = trim(s);
  if (s.size() >= 2 && s[0] == '"' && s[s.size() - 1] == '"') {
    return s.substr(1, s.size() - 2);
  }
  return s;
}

bool execLine(const std::string &raw, bool &canvas, bool &level, SurfaceResult &out,
              std::string &error) {
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

  const std::string neuLevel = "new TServerLevel(";
  if (line.compare(0, neuLevel.size(), neuLevel) == 0 && line[line.size() - 1] == ')') {
    const std::string name =
        trim(line.substr(neuLevel.size(), line.size() - neuLevel.size() - 1));
    if (name.empty()) {
      error = "new TServerLevel needs a name";
      return false;
    }
    level = true;
    out.log.push_back("new TServerLevel " + name);
    return true;
  }

  const std::size_t dot = line.find('.');
  const std::size_t paren = line.find('(');
  if (dot != std::string::npos && paren != std::string::npos && dot < paren &&
      line[line.size() - 1] == ')') {
    const std::string obj = trim(line.substr(0, dot));
    const std::string method = trim(line.substr(dot + 1, paren - dot - 1));
    const std::string inside = line.substr(paren + 1, line.size() - paren - 2);
    if (!level && (method == "openLevel" || method == "placeTile")) {
      error = "level call with no TServerLevel";
      return false;
    }
    if (obj == "keyset" && method == "bind") {
      const std::string name = unquote(inside);
      return addKeysetAction(name, out.log, error);
    }
    if (method == "openLevel") {
      const std::string name = unquote(inside);
      if (name.empty()) {
        error = "openLevel needs a name";
        return false;
      }
      stubOpenLevel(out, name);
      return true;
    }
    if (method == "placeTile") {
      std::string x, y, tile, rest = inside;
      const std::size_t c1 = rest.find(',');
      const std::size_t c2 = c1 == std::string::npos ? std::string::npos : rest.find(',', c1 + 1);
      if (c1 == std::string::npos || c2 == std::string::npos) {
        error = "placeTile needs three arguments";
        return false;
      }
      x = unquote(rest.substr(0, c1));
      y = unquote(rest.substr(c1 + 1, c2 - c1 - 1));
      tile = unquote(rest.substr(c2 + 1));
      stubPlaceTile(out, x, y, tile);
      return true;
    }
    stubOther(out, line);
    return true;
  }

  stubOther(out, line);
  return true;
}

} // namespace

bool runSurfaceFile(const std::string &path, SurfaceResult &out, std::string &error) {
  out.contentSet = false;
  out.contentLine.clear();
  out.levelOpened = false;
  out.tilePlaced = false;
  out.tileLine.clear();
  out.log.clear();

  // Boot order from the engine note: the canvas exists before content is set.
  // Point2I and GBitmap are linked. No size and no pixels are recovered here.
  bool canvas = true;
  bool level = false;
  out.log.push_back(
      "registered residual surface: GuiCanvas, GuiControl, Point2I, GBitmap");
  out.log.push_back("Point2I registered (no size recovered this pass)");
  out.log.push_back("GBitmap registered (this DLL does not draw pixels)");
  out.log.push_back(
      "registered engine types GuiGraalCtrl, GuiGraal3DCtrl "
      "(a script new of either is discarded)");
  out.log.push_back(
      "script runner is provisional (this engine has no Torque console and no .dso)");
  out.log.push_back("GuiCanvas created");
  if (!logEngineControls(out.log, error)) {
    return false;
  }

  std::ifstream in(path.c_str());
  if (!in) {
    error = "could not open " + path;
    return false;
  }
  std::string line;
  int number = 0;
  while (std::getline(in, line)) {
    ++number;
    if (!execLine(line, canvas, level, out, error)) {
      error = path + ":" + std::to_string(number) + ": " + error;
      return false;
    }
  }
  if (!out.levelOpened || !out.tilePlaced) {
    error = "script did not open a level and place a tile";
    return false;
  }
  return true;
}
