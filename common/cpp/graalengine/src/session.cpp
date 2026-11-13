#include "session.hpp"

#include "engine.hpp"
#include "host.hpp"
#include "../../quattro/shell/program.hpp"


namespace graalengine {

namespace QD = Quattro::Draw;

// The program's window: the frame it presents is kept for the playfield.
// The keys come from the engine's bindings (Program::action), not from here.
class EngineWindow : public QD::Window {
 public:
  void set_title(const std::string& t) override { title_ = t; }
  void present(const Torque::Gui::Image& frame) override { last = frame; }
  QD::Key poll_key() override { return QD::Key::NoKey; }
  bool held(QD::Key) const override { return false; }
  const std::string& title() const override { return title_; }
  Torque::Gui::Image last;

 private:
  std::string title_;
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
  // As the launchers' own files (GAssetDirs): the install first, then
  // graal-assets/<version>/ and graal-assets/common/ next to it.
  {
    std::string label = login_.build.substr(0, login_.build.find(' '));
    opt.asset_roots = {login_.installDir + "/graal-assets/" + label, login_.installDir + "/graal-assets/common"};
  }
  // A real install starts with few images and fetches the rest from the
  // server (C->S 23), as the lab's 5.12 did.
  opt.download_files = true;
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
  // Each login (the first server, then each warp) goes to the launcher's
  // OnServerLogin with the server's name; the 5.x launcher titles its game
  // window with it (the lab's 5.12 window read "L a b   S e r v e r" after
  // the warp, version-profiles/lab-v5-2026-10-30.md).
  if (const int n = program_->session().logins(); n != loginsSeen_) {
    loginsSeen_ = n;
    host::OnServerLogin(program_->session().server_name().c_str());
  }
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

bool Session2D::action(const std::string& cmd, bool down) { return program_->action(cmd, down); }

void Session2D::say(const std::string& text) { program_->say(text); }

}  // namespace graalengine
