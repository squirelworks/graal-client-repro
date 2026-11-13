#include "engine.hpp"

#include "gui_host.hpp"
#include "host.hpp"
#include "session.hpp"
#include "showimg.hpp"
#include "../../quattro/net/profile.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
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

void Engine::log(const std::string& line) {
  // The 5.0 launcher has no LogGraalMessage (torque/5007-launcher.md);
  // GRAALENGINE_LOG sends the lines to stderr instead, for lab runs.
  if (host::hasLogGraalMessage()) host::LogGraalMessage(line.c_str());
  else if (const char* v = std::getenv("GRAALENGINE_LOG"); v && *v) std::fprintf(stderr, "%s\n", line.c_str());
}

bool Engine::setBuild(const std::string& label) {
  const auto* row = Quattro::Net::find_profile(label);
  if (!row) return false;
  build_ = label;
  // The 4.2.0.8 and 5.0.0.7 engines run the same machine with a few
  // opcodes added (client-internals/gs2-vm-from-engines.md).
  profile_ = label.rfind("4.", 0) == 0 ? gs2::Profile::Engine42 : gs2::Profile::Engine50;
  return true;
}

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
    // The show-images: ganis step on, emitters run one frame.
    if (auto* si = e.showImg()) si->tick();
    if (auto* sc = e.screen()) sc->advance(0.05);
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
  // With no account given, the 5.x Windows builds log in as the built-in
  // guest (protocol/v5v6-windows-unpacked.md, "Login message").
  if (l.account.empty() && profile_ != gs2::Profile::Engine42) {
    l.account = "guest";
    l.password = "7Y3bdzjf";
  }
  l.nickname = account_.nickname;
  l.installDir = installDir();
  l.build = build_;
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
  showImg_ = std::make_unique<ShowImgPainter>(installDir());
  painter_->onSprite = [this](const std::string& file, double x, double y, double rot, double sx, double sy,
                              const double* rgba, int mode) { showImg_->sprite(file, x, y, rot, sx, sy, rgba, mode); };
  painter_->onEngineControl = [this](const gs2::gui::Control& c, const gs2::gui::Rect& r) {
    std::string t = c.type();
    for (auto& ch : t) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    if (t == "guishowimgctrl") {
      showImg_->drawControl(c, r);
      return;
    }
    if (!session_ || !session_->haveFrame()) return;
    if (t != "guigraalctrl") return;
    const graal_texture& f = session_->frame();
    if (f.width == r.w && f.height == r.h)
      host::DrawGraphics(&f, r.x, r.y, 0, 0, f.width, f.height, 0xFFFFFFFFu);
    else if (host::hasDrawGraphicsStretched())
      host::DrawGraphicsStretched(&f, r.x, r.y, r.w, r.h, 0, 0, f.width, f.height, 0xFFFFFFFFu);
    else  // the 5.0 launcher has no stretched draw: the frame's top left
      host::DrawGraphics(&f, r.x, r.y, 0, 0, std::min(f.width, r.w), std::min(f.height, r.h), 0xFFFFFFFFu);
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
  showImg_.reset();
  screenControl_.reset();
  screen_.reset();
  painter_.reset();
  textures_.reset();
  machine_.reset();
}

}  // namespace graalengine
