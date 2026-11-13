// The engine library's session state, for code linked into the library
// (the GS2 core and its controls) to reach the canvas and the launcher.
#pragma once

#include "canvas.hpp"
#include "gui.hpp"
#include "engine_commands.hpp"
#include "gs2.hpp"

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace graalengine {

class TextureCache;
class SlotPainter;
class Session2D;
class ShowImgPainter;

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

  // Runs when loadGraalGui first creates the canvas, before the start
  // scripts: the GS2 controls (Track B4) register their object factory and
  // GUI commands on machine() here. It may also set the content itself.
  using GuiBuilder = std::function<void(Engine&)>;
  void setGuiBuilder(GuiBuilder b) { guiBuilder_ = std::move(b); }

  // The control a script object draws as, for setContentControl from a
  // script object (`MainMenuGui2D`, `GUIContainer`). Null when the object
  // has no control; then the canvas gets an empty control of that name.
  using ControlResolver = std::function<std::shared_ptr<Control>(const gs2::VarPtr&)>;
  void setControlResolver(ControlResolver r) { controlOf_ = std::move(r); }

  // The GS2 screen (common/cpp/gs2/gui.hpp) the menus build, drawn through
  // the slots. Made by loadGraalGui unless a GUI builder was set; null
  // before that.
  gs2::gui::Screen* screen() { return screen_.get(); }
  // Key bindings that name no script function (moveUp2D, doA, ...), on
  // press and release. Until the session takes them they are logged.
  void setEngineActionHandler(std::function<void(const std::string&, bool)> f) { action_ = std::move(f); }

  // The GS2 machine the start menus and server scripts run on. Made by
  // graal_engineInitialize; Engine42 unless setProfile chose another first.
  gs2::Machine* machine() { return machine_.get(); }
  void setProfile(gs2::Profile p) { profile_ = p; }

  // The build the launcher is ("4.04r2", "5.00r7", "5.12"; the rebuild's
  // graalengine_setBuild, called before graal_engineInitialize). It picks
  // the session's wire row (common/cpp/quattro/net/profile.cpp) and the GS2
  // profile: 4.2 for 4.x, 5.0 for 5.x. False for a build with no row.
  bool setBuild(const std::string& label);
  const std::string& build() const { return build_; }

  // The file the start scripts are read from: GRAAL_ENGINE_FILE, else the
  // install's own GraalEngine.dll, else the launcher's exe (the player's
  // own copy; nothing from it is kept). Empty when none has scripts.
  std::string startScriptFile() const;
  // The start scripts found there, by name, after loadGraalGui.
  const std::vector<std::string>& startScriptNames() const { return startNames_; }

  // What the menus told the engine through the Adventure_* calls.
  struct Account {
    std::string account, password, nickname, chat;
    std::map<std::string, std::vector<std::string>> fields;  // the update* calls, by name
  };
  const Account& account() const { return account_; }
  // The login the session sends: the account from the menus, or on the 5.x
  // builds the built-in guest when none was given.
  Account loginAccount() const;

  // The 3D path (Track C4). A `3 ` server connected while the 3D library
  // has filled ConnectTo3DServer: 3D mode, the Torque link to port + 1,
  // and the TCP session as for a 2D server.
  bool graal3DMode() const { return mode3d_; }
  // The 3D link failed: log, leave 3D mode, drop the TCP session.
  void graal3DConnectionError(const std::string& reason);
  // onGraal3DLoginStep(step) on the universe; step 6 makes the 3D GUI the
  // content.
  void graal3DLoginStep(int step);
  int graal3DStep() const { return step3d_; }

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
  // enableGraalScriptedControls: also the scripts' `scriptedcontrols`
  // variable, which GraalGui's playfield reads on wake to push the
  // MoveMap2D key bindings.
  void enableScriptedControls(bool on);
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
  // The 2D session connectToGraalServer started when no connector was set
  // (src/session.hpp); null before that.
  Session2D* session() { return session_.get(); }
  // The show-images' ganis and particles (src/showimg.hpp); null before
  // the GS2 screen is made.
  ShowImgPainter* showImg() { return showImg_.get(); }
  int initializeCount() const { return initCount_; }

  // Writes one line through the LogGraalMessage slot.
  void log(const std::string& line);

  // Key state from invokeGraalKeyboardEvent, for the `keydown` command.
  bool keyHeld(int vk) const;

  Engine();
  ~Engine();

 private:
  void startMachine();
  void addAdventureCommands(gs2::EngineHost& h);
  gs2::VarPtr runStartScript(const std::string& name, bool keep);
  void setContentFrom(const std::string& objectName);
  void loadStartMenus();
  void installScreen();

  std::string exePath_;
  std::vector<std::string> license_;
  std::unique_ptr<Canvas> canvas_;
  GuiBuilder guiBuilder_;
  OfflineStarter offline_;
  Connector connect_;
  std::function<void()> timer_;
  Target target_;
  bool offlineRequested_ = false;
  bool mode3d_ = false;
  int step3d_ = 0;
  bool scriptedControls_ = true;
  int initCount_ = 0;
  gs2::Profile profile_ = gs2::Profile::Engine42;
  std::string build_ = "4.04r2";
  std::unique_ptr<gs2::Machine> machine_;
  ControlResolver controlOf_;
  std::map<std::string, std::shared_ptr<const gs2::Script>> startScripts_;
  std::vector<std::string> startNames_;
  Account account_;
  bool keys_[256] = {};
  std::unique_ptr<TextureCache> textures_;
  std::unique_ptr<SlotPainter> painter_;
  std::unique_ptr<gs2::gui::Screen> screen_;
  std::shared_ptr<Control> screenControl_;
  std::function<void(const std::string&, bool)> action_;
  std::unique_ptr<Session2D> session_;
  std::unique_ptr<ShowImgPainter> showImg_;
};

// The library's one engine.
Engine& engine();

// Drops the engine and builds a fresh one (tests; shutdownGraalEngine).
void resetEngine();

}  // namespace graalengine
