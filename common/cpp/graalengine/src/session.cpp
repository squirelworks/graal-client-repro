#include "session.hpp"

#include <deque>

#include "engine.hpp"
#include "host.hpp"
#include "../../quattro/shell/program.hpp"


namespace graalengine {

namespace QD = Quattro::Draw;

namespace {
// The lab's 5.12 status names: before the login, then once logged in.
constexpr const char* kStatusesStart = "Online,Away,DND";
constexpr const char* kStatusesOnline = "Online,Away,DND,Eating,Hiding,No PMs,RPing,Sparring,PKing";
}  // namespace

// The program's window: the frame it presents is kept for the playfield.
// The keys come from the engine's bindings (Program::action), not from here.
class EngineWindow : public QD::Window {
 public:
  void set_title(const std::string& t) override { title_ = t; }
  void present(const Torque::Gui::Image& frame) override { last = frame; }
  QD::Key poll_key() override { return QD::Key::NoKey; }
  bool held(QD::Key) const override { return false; }
  const std::string& title() const override { return title_; }
  // Presses on the playfield, for the program's scripts and leftmouse.
  bool poll_input(QD::InputEvent& e) override {
    if (input.empty()) return false;
    e = input.front();
    input.pop_front();
    return true;
  }
  Torque::Gui::Image last;
  std::deque<QD::InputEvent> input;

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
  // What the 5.12 engine tells its launcher besides drawing (the lab's
  // 5.12 under hooks, 2026-11-13): the player-list rows, the status names,
  // the server's name once the login is accepted, and a warning when the
  // link drops. The 4.x rows keep their earlier calls.
  five_ = !login_.build.empty() && login_.build[0] == '5';
  // A dropped link: the warning box on both rows (the lab's real 4.04r2 and
  // 5.12 both showed it; 4.04r2's text is taken to be 5.12's [inf]). The
  // 4.x engine then goes back to the start menu (Engine::afterSessionTick).
  program_->disconnected = [this](const std::string&) {
    dropped_ = true;
    host::OpenMessageBox("Warning", "You have been disconnected from the game server.", 1);
  };
  // The player-list rows go to the 4.x launcher too: the 4.2.0.8 launcher
  // has the same external player-list slots (torque/4208-launcher.md), and
  // the lab's 4.04r2 showed its player list once in the game. The 4.x
  // login keeps its own OnServerLogin call (tick); the status names and
  // the lister call stay 5.x's.
  program_->list_update = [](const Quattro::Shell::Program::ListRow& r) {
    host::ExternalPlayerlistUpdate(r.id, r.nick.c_str(), r.head.c_str(), r.props.c_str(), r.flags);
  };
  program_->list_delete = [](int id) { host::ExternalPlayerlistDelete(id); };
  if (!five_) return;
  program_->logged_in = [this] {
    host::OnServerLogin(program_->session().server_name().c_str());
    host::OnServerListerConnect();
    host::SetGraalStatusIcons(kStatusesOnline);
  };
}

Session2D::~Session2D() = default;

bool Session2D::start() {
  if (five_) host::SetGraalStatusIcons(kStatusesStart);
  return program_->start();
}

bool Session2D::startOffline(const std::string& file, double x, double y) {
  return program_->start_offline(file, x, y);
}

void Session2D::tick() {
  program_->tick();
  // Each login (the first server, then each warp) goes to the launcher's
  // OnServerLogin with the server's name; the 5.x launcher titles its game
  // window with it (the lab's 5.12 window read "L a b   S e r v e r" after
  // the warp, version-profiles/lab-v5-2026-10-30.md).
  if (const int n = program_->session().logins(); !five_ && n != loginsSeen_) {
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

void Session2D::mouse(int x, int y, int clicks) {
  QD::InputEvent e;
  e.type = QD::InputEvent::MouseDown;
  e.x = x;
  e.y = y;
  e.clicks = clicks;
  window_->input.push_back(e);
}

}  // namespace graalengine
