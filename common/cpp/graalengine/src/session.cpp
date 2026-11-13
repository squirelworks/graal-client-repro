#include "session.hpp"

#include "engine.hpp"
#include "host.hpp"
#include "../../quattro/shell/program.hpp"

#include <set>

namespace graalengine {

namespace QD = Quattro::Draw;

// The program's window: the frame it presents is kept for the playfield,
// and the held arrows come from the engine's key bindings.
class EngineWindow : public QD::Window {
 public:
  void set_title(const std::string& t) override { title_ = t; }
  void present(const Torque::Gui::Image& frame) override { last = frame; }
  QD::Key poll_key() override { return QD::Key::NoKey; }
  bool held(QD::Key k) const override { return held_.count(k) != 0; }
  const std::string& title() const override { return title_; }
  void hold(QD::Key k, bool down) {
    if (down) held_.insert(k);
    else held_.erase(k);
  }
  Torque::Gui::Image last;

 private:
  std::string title_;
  std::set<QD::Key> held_;
};

Session2D::Session2D(Login login) : login_(std::move(login)), window_(std::make_unique<EngineWindow>()) {
  const auto* profile = Quattro::Net::find_profile(login_.build);
  if (!profile) profile = Quattro::Net::find_profile("4.04r2");
  Quattro::Shell::Options opt;
  opt.build = login_.build;
  opt.host = login_.host;
  opt.port = static_cast<uint16_t>(login_.port);
  opt.account = login_.account;
  opt.password = login_.password;
  opt.nickname = login_.nickname;
  opt.server_name = login_.name.empty() ? std::string("Login") : login_.name;
  opt.assets = login_.installDir;
  opt.width = host::GetScreenWidth() > 0 ? host::GetScreenWidth() : 640;
  opt.height = host::GetScreenHeight() > 0 ? host::GetScreenHeight() : 480;
  program_ = std::make_unique<Quattro::Shell::Program>(*profile, opt, *window_);
  program_->log = [this](const std::string& s) {
    log_.push_back(s);
    engine().log("GraalEngine: " + s);
  };
  frame_.name = "GraalControl";
}

Session2D::~Session2D() = default;

bool Session2D::start() { return program_->start(); }

bool Session2D::startOffline(const std::string& file, double x, double y) {
  return program_->start_offline(file, x, y);
}

void Session2D::tick() {
  program_->tick();
  const auto& img = window_->last;
  if (img.empty()) return;
  pixels_.resize(img.pixels.size());
  for (std::size_t i = 0; i < img.pixels.size(); ++i) {
    const auto& c = img.pixels[i];
    pixels_[i] = 0xFF000000u | (uint32_t(c.r) << 16) | (uint32_t(c.g) << 8) | c.b;
  }
  frame_.width = img.width;
  frame_.height = img.height;
  frame_.pixels = pixels_.data();
}

bool Session2D::action(const std::string& cmd, bool down) {
  QD::Key k = QD::Key::NoKey;
  if (cmd == "moveUp2D") k = QD::Key::Up;
  else if (cmd == "moveDown2D") k = QD::Key::Down;
  else if (cmd == "moveLeft2D") k = QD::Key::Left;
  else if (cmd == "moveRight2D") k = QD::Key::Right;
  if (k == QD::Key::NoKey) return false;
  window_->hold(k, down);
  return true;
}

void Session2D::say(const std::string& text) { program_->say(text); }

}  // namespace graalengine
