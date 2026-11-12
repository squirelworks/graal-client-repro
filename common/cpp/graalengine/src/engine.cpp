#include "engine.hpp"

#include "gui_host.hpp"
#include "host.hpp"
#include "session.hpp"

#include <cctype>
#include <cstdlib>
#include <fstream>

namespace graalengine {

namespace {

std::unique_ptr<Engine>& slot() {
  static std::unique_ptr<Engine> e;
  return e;
}

std::vector<std::string> readLines(const std::string& path) {
  std::vector<std::string> out;
  std::ifstream in(path, std::ios::binary);
  if (!in) return out;
  std::string line;
  while (std::getline(in, line)) {
    while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) line.pop_back();
    if (!line.empty()) out.push_back(line);
  }
  return out;
}

}  // namespace

Engine::Engine() = default;
Engine::~Engine() = default;

Engine& engine() {
  auto& e = slot();
  if (!e) e = std::make_unique<Engine>();
  return *e;
}

void resetEngine() { slot().reset(); }

std::string Engine::installDir() const {
  const auto cut = exePath_.find_last_of("/\\");
  if (cut == std::string::npos) return ".";
  return exePath_.substr(0, cut);
}

void Engine::log(const std::string& line) { host::LogGraalMessage(line.c_str()); }

bool Engine::initialize(const char* exePath) {
  ++initCount_;
  if (initCount_ > 1) {
    // A second call only initialises the script environment
    // (torque/5007-engine.md): the machine, if there is none yet.
    if (!machine_) startMachine();
    return true;
  }
  exePath_ = exePath ? exePath : "";
  // The original also checks three signature files under license/ and the
  // exe against them; the rebuild has no signatures to check.
  license_ = readLines(installDir() + "/license/license.graal");
  startMachine();
  log("GraalEngine: started in " + installDir() + (license_.empty() ? ", no licence" : ", licence read"));
  return true;
}


namespace {
// The frame's timer: one 2D pass of the script machine (the clock steps
// 0.05, the launcher's 50 ms frame), then the session's own timer.
std::function<void()> frameTimer(Engine& e, std::function<void()> session) {
  return [&e, session] {
    if (auto* m = e.machine()) m->runScripts();
    if (session) session();
    else if (auto* s = e.session()) s->tick();
  };
}
}  // namespace

void Engine::setTimer(std::function<void()> t) {
  timer_ = std::move(t);
  if (canvas_) canvas_->setTimer(frameTimer(*this, timer_));
}

void Engine::loadGui() {
  if (!machine_) startMachine();
  if (canvas_) {
    // Calling it again, with the canvas there, rebuilds what the GUI
    // builder rebuilds and runs the two move-map scripts again
    // (torque/4208-engine.md).
    if (guiBuilder_) guiBuilder_(*this);
    runStartScript("StartScript_MoveMap2D", false);
    runStartScript("StartScript_MoveMap3D", false);
    return;
  }
  canvas_ = std::make_unique<Canvas>();
  canvas_->setTimer(frameTimer(*this, timer_));
  if (guiBuilder_) guiBuilder_(*this);
  else installScreen();
  loadStartMenus();
}

void Engine::render(bool draw) {
  if (canvas_) canvas_->renderFrame(draw);
}

void Engine::key(int vk, int ch, int mods, bool down) {
  if (vk >= 0 && vk < 256) keys_[vk] = down;
  if (!canvas_) return;
  InputEvent ev;
  ev.kind = down ? InputEvent::KeyDown : InputEvent::KeyUp;
  ev.vk = vk;
  ev.ch = ch;
  ev.mods = mods;
  canvas_->processInputEvent(ev);
}

void Engine::mouse(int x, int y, int action, int button, int clicks, int mods, int wheel) {
  if (!canvas_) return;
  InputEvent ev;
  switch (action) {
    case GRAAL_MOUSE_DOWN: ev.kind = InputEvent::MouseDown; break;
    case GRAAL_MOUSE_UP: ev.kind = InputEvent::MouseUp; break;
    case GRAAL_MOUSE_WHEEL: ev.kind = InputEvent::MouseWheel; break;
    default: ev.kind = InputEvent::MouseMove; break;
  }
  ev.x = x;
  ev.y = y;
  ev.button = button;
  ev.clicks = clicks;
  ev.mods = mods;
  ev.wheel = wheel;
  canvas_->processInputEvent(ev);
}

void Engine::startOffline() {
  offlineRequested_ = true;
  runStartScript("StartScript_GraalGui", true);
  setContentFrom("GUIContainer");
  if (offline_) offline_(*this);
}

void Engine::connect(const std::string& rawName, const std::string& host, int port) {
  // A name whose second character is a space loses those two characters;
  // a `3 ` marker selects the 3D path, which asks the launcher to bring
  // the 3D library in (torque/4208-engine.md, torque/network.md).
  std::string name = rawName;
  bool is3d = false;
  if (name.size() >= 2 && name[1] == ' ') {
    is3d = name[0] == '3';
    name = name.substr(2);
  }
  target_ = {name, host, port, is3d};
  if (is3d) {
    runStartScript("StartScript_GraalGui3D", true);
    host::StartGraal3D();
  } else {
    runStartScript("StartScript_GraalGui", true);
    setContentFrom("GUIContainer");
  }
  if (connect_) {
    connect_(*this, name, host, port, is3d);
    return;
  }
  if (is3d) return;  // the 3D library's session (Track C4)
  Session2D::Login l;
  l.name = name;
  l.host = host;
  l.port = port;
  l.account = account_.account;
  l.password = account_.password;
  l.nickname = account_.nickname;
  l.installDir = installDir();
  session_ = std::make_unique<Session2D>(l);
  if (!session_->start()) log("GraalEngine: could not connect to " + name);
}

void Engine::openServerList() {
  // The Login server is the first entry of the licence (host, port).
  if (license_.size() < 2) return;
  connect("Login", license_[0], std::atoi(license_[1].c_str()));
}

void Engine::prepareShutdown() { offline_ = nullptr; }

void Engine::installScreen() {
  textures_ = std::make_unique<TextureCache>(installDir());
  painter_ = std::make_unique<SlotPainter>(*textures_);
  screen_ = std::make_unique<gs2::gui::Screen>(*machine_);
  screen_->install();
  screen_->onEngineAction = [this](const std::string& cmd, bool down) {
    if (action_) action_(cmd, down);
    else if (session_ && session_->action(cmd, down)) return;
    else if (down) log("GraalEngine: engine action " + cmd);
  };
  // GraalGui's playfield (GuiGraalCtrl) shows the session's world.
  painter_->onEngineControl = [this](const gs2::gui::Control& c, const gs2::gui::Rect& r) {
    if (!session_ || !session_->haveFrame()) return;
    std::string t = c.type();
    for (auto& ch : t) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    if (t != "guigraalctrl") return;
    const graal_texture& f = session_->frame();
    if (f.width == r.w && f.height == r.h)
      host::DrawGraphics(&f, r.x, r.y, 0, 0, f.width, f.height, 0xFFFFFFFFu);
    else
      host::DrawGraphicsStretched(&f, r.x, r.y, r.w, r.h, 0, 0, f.width, f.height, 0xFFFFFFFFu);
  };
  screenControl_ = std::make_shared<ScreenControl>(*screen_, *painter_);
  if (!controlOf_) {
    controlOf_ = [this](const gs2::VarPtr& var) -> std::shared_ptr<Control> {
      auto c = screen_->find(var->name());
      if (!c) return nullptr;
      screen_->setSize(canvas_->screenWidth(), canvas_->screenHeight());
      screen_->setContent(c);
      return screenControl_;
    };
  }
}

void Engine::shutdown() {
  session_.reset();
  canvas_.reset();
  screenControl_.reset();
  screen_.reset();
  painter_.reset();
  textures_.reset();
  machine_.reset();
}

}  // namespace graalengine
