#include "engine.hpp"

#include "host.hpp"

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
    // A second call only resets the script environment
    // (torque/5007-engine.md). The script environment is the GS2 core's.
    return true;
  }
  exePath_ = exePath ? exePath : "";
  // The original also checks three signature files under license/ and the
  // exe against them; the rebuild has no signatures to check.
  license_ = readLines(installDir() + "/license/license.graal");
  log("GraalEngine: started in " + installDir() + (license_.empty() ? ", no licence" : ", licence read"));
  return true;
}

void Engine::setTimer(std::function<void()> t) {
  timer_ = std::move(t);
  if (canvas_) canvas_->setTimer(timer_);
}

void Engine::loadGui() {
  if (canvas_) {
    // Calling it again, with the canvas there, only rebuilds what the
    // GUI builder rebuilds (torque/4208-engine.md).
    if (guiBuilder_) guiBuilder_(*this);
    return;
  }
  canvas_ = std::make_unique<Canvas>();
  canvas_->setTimer(timer_);
  if (guiBuilder_) {
    guiBuilder_(*this);
  } else {
    canvas_->setContentControl(std::make_shared<Control>("MainMenuGui2D"));
  }
}

void Engine::render(bool draw) {
  if (canvas_) canvas_->renderFrame(draw);
}

void Engine::key(int vk, int ch, int mods, bool down) {
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
  if (is3d) host::StartGraal3D();
  if (connect_) connect_(*this, name, host, port, is3d);
}

void Engine::openServerList() {
  // The Login server is the first entry of the licence (host, port).
  if (license_.size() < 2) return;
  connect("Login", license_[0], std::atoi(license_[1].c_str()));
}

void Engine::prepareShutdown() { offline_ = nullptr; }

void Engine::shutdown() { canvas_.reset(); }

}  // namespace graalengine
