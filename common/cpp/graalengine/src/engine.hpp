// The engine library's session state, for code linked into the library
// (the GS2 core and its controls) to reach the canvas and the launcher.
#pragma once

#include "canvas.hpp"

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace graalengine {

class Engine {
 public:
  // What graal_engineInitialize recorded.
  const std::string& exePath() const { return exePath_; }
  // The install folder: the folder the launcher runs from.
  std::string installDir() const;
  // license/license.graal as lines (host, port, further hosts), empty
  // when the install has none (torque/5007-engine.md).
  const std::vector<std::string>& licenseLines() const { return license_; }

  // Null until loadGraalGui.
  Canvas* canvas() { return canvas_.get(); }

  // What builds the start menus when loadGraalGui first creates the
  // canvas. Until the GS2 core (Track B3) installs one, the canvas gets an
  // empty `MainMenuGui2D` content control.
  using GuiBuilder = std::function<void(Engine&)>;
  void setGuiBuilder(GuiBuilder b) { guiBuilder_ = std::move(b); }

  // What runs on startOfflineMode and connectToGraalServer. Until the
  // session code is linked in these only record the request.
  using OfflineStarter = std::function<void(Engine&)>;
  using Connector = std::function<void(Engine&, const std::string& name, const std::string& host,
                                       int port, bool is3d)>;
  void setOfflineStarter(OfflineStarter f) { offline_ = std::move(f); }
  void setConnector(Connector f) { connect_ = std::move(f); }

  // Runs before each frame's drawing (TAdventure::timer's place).
  void setTimer(std::function<void()> t);

  // Entry points (the C exports forward here).
  bool initialize(const char* exePath);
  void loadGui();
  void render(bool draw);
  void key(int vk, int ch, int mods, bool down);
  void mouse(int x, int y, int action, int button, int clicks, int mods, int wheel);
  void startOffline();
  void connect(const std::string& name, const std::string& host, int port);
  void openServerList();
  void enableScriptedControls(bool on) { scriptedControls_ = on; }
  bool scriptedControls() const { return scriptedControls_; }
  void prepareShutdown();
  void shutdown();

  // The last connect request, for tests and the status line.
  struct Target {
    std::string name, host;
    int port = 0;
    bool is3d = false;
  };
  const Target& lastTarget() const { return target_; }
  bool offlineRequested() const { return offlineRequested_; }
  int initializeCount() const { return initCount_; }

  // Writes one line through the LogGraalMessage slot.
  void log(const std::string& line);

 private:
  std::string exePath_;
  std::vector<std::string> license_;
  std::unique_ptr<Canvas> canvas_;
  GuiBuilder guiBuilder_;
  OfflineStarter offline_;
  Connector connect_;
  std::function<void()> timer_;
  Target target_;
  bool offlineRequested_ = false;
  bool scriptedControls_ = true;
  int initCount_ = 0;
};

// The library's one engine.
Engine& engine();

// Drops the engine and builds a fresh one (tests; shutdownGraalEngine).
void resetEngine();

}  // namespace graalengine
