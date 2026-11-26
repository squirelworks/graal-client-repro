#include "host.hpp"

#include <chrono>
#include <cstdio>

namespace Frank {

const char* host_build_label() {
#ifdef _WIN32
  return "6.03r7 Windows";
#else
  return "6.03r7 Linux";
#endif
}

std::string strip_marker(const std::string& raw, bool& is3d) {
  is3d = false;
  if (raw.size() >= 2 && raw[1] == ' ') {
    is3d = raw[0] == '3';
    return raw.substr(2);
  }
  return raw;
}

namespace {
double seconds_now() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}
}  // namespace

void ViewWindow::present(const Torque::Gui::Image& frame) {
  if (!enabled || !link || link->loginStep() < 6 || frame.empty()) {
    world_link_ = nullptr;
    inner_.present(frame);
    return;
  }
  // The 6.x program counts its timers and walking in 50 ms ticks, and this
  // is called once a tick. In the lab (2026-11-26, a 2-CPU VM) the software
  // renderer took 90 to 180 ms a frame, and every GS2 timer and walk ran 2
  // to 3.6 times slow. So the 3D frame takes at most about half the time:
  // after a frame that took t, the next waits t, and the ticks between show
  // the last 3D frame under a live 6.x inset.
  const double now = seconds_now();
  const bool stale = world_link_ != link || world_.width != frame.width || world_.height != frame.height;
  if (stale || now >= next_world_) {
    world_ = Torque::Gui::Image(frame.width, frame.height);
    // The 5.12 renderer; black until the server names a Camera, as the 5.12.
    draw_world3d(world_, *link, world3d, now, &last);
    world_link_ = link;
    ++worlds_drawn;
    const double end = seconds_now();
    next_world_ = end + (end - now);
  }
  out_ = world_;
  draw_inset(out_, frame, 4);
  inner_.present(out_);
}

Host::Host(Quattro::Shell::Options opt, Quattro::Draw::Window& window)
    : profile_(Quattro::Net::find_profile(host_build_label())),
      opt_(std::move(opt)),
      view_(window),
      link_(callbacks()) {
  opt_.build = host_build_label();
  // 3D files: levels3d/ beside the program and under each asset root.
  view_.world3d.roots.push_back("levels3d");
  for (const auto& r : opt_.asset_roots) view_.world3d.roots.push_back(r + "/levels3d");
  // The player's draw distance, from a 5.12-style game_config.txt beside
  // the program or in an asset root (T3D-075: 1000 when none sets it).
  std::vector<std::string> configs{"game_config.txt"};
  for (const auto& r : opt_.asset_roots) configs.push_back(r + "/game_config.txt");
  const float visible = load_visible_distance(configs);
  if (visible != 1000.0f)  // the 5.12 default
    say("Graal3D: draw distance " + std::to_string(static_cast<int>(visible)));
}

Link3D::Callbacks Host::callbacks() {
  Link3D::Callbacks cb;
  cb.log = [this](const std::string& s) { say(s); };
  cb.login_step = [this](int step) {
    step_ = step;
    say("Graal3D: login step " + std::to_string(step));
    // The 5.12 engine raises onGraal3DLoginStep on the universe; the 6.x
    // GraalGui has no 3D content to switch to, so the view takes over.
    if (program_) program_->scripts().queue_all("onGraal3DLoginStep", {gs2::Value::number(step)});
  };
  cb.error = [this](const std::string& why) {
    say("Graal3D: " + why);
    // The two links live and die together (torque/udp-session.md §1).
    mode3d_ = false;
    view_.link = nullptr;
    failed_ = true;
  };
  cb.text = [this](const graal3d::BigText& t) {
    if (program_) program_->server_text(t.s1, t.s2, t.s3, t.data);
  };
  return cb;
}

Host::~Host() { close(); }

void Host::close() {
  link_.close();
  view_.link = nullptr;
  mode3d_ = false;
  program_.reset();
}

void Host::make_program(const Quattro::Shell::Options& opt) {
  program_ = std::make_unique<Quattro::Shell::Program>(*profile_, opt, view_);
  program_->log = [this](const std::string& s) { say(s); };
  // A Login-server 178 warp to a `3 ` server leaves this session for the
  // 3D path, as the real 5.12 entered 3D (torque/lab-2026-11-12-udp-trace.md).
  program_->session().take_warp = [this](const Quattro::Net::ServerWarp& w) {
    if (w.name.size() < 2 || w.name[0] != '3' || w.name[1] != ' ') return false;
    warp_pending_ = true;
    warp_ = w;
    return true;
  };
  if (mode3d_) {
    // In 3D mode the scripts' server triggers go over the 3D link as event
    // lines (torque/udp-session.md §7), not as C->S 38.
    program_->scripts().set_event_line([this](const std::string& line) { link_.event_lines(line); });
  }
}

bool Host::connect(const std::string& raw_name, const std::string& host, uint16_t port) {
  bool is3d = false;
  server_ = strip_marker(raw_name, is3d);
  link_.close();
  mode3d_ = false;
  step_ = 0;
  view_.link = nullptr;
  if (is3d) {
    if (port == 0xFFFF) {
      say("Graal3D: no port above " + std::to_string(port));
      return false;
    }
    graal3d::LinkLogin l;
    l.account = opt_.account;
    l.nickname = opt_.nickname.empty() ? "unknown" : opt_.nickname;
    l.password = opt_.password;
    l.protocol = graal3d::protocolForBuild("5.12");
    l.connectSequence = connect_sequence ? connect_sequence
                                         : ((Link3D::now_ms() * 2654435761u) & 0x7FFFFFFEu) | 2u;
    failed_ = false;
    if (!link_.open(host, static_cast<uint16_t>(port + 1), l)) return false;
    mode3d_ = true;
    view_.link = view3d ? link_.link() : nullptr;
    say("Graal3D: " + server_ + " on " + host + ":" + std::to_string(port + 1) + " (UDP)");
  }
  Quattro::Shell::Options o = opt_;
  o.server_name = server_;
  o.host = host;
  o.port = port;
  make_program(o);
  return program_->start();
}

bool Host::start() { return connect(opt_.server_name, opt_.host, opt_.port); }

bool Host::start_offline(const std::string& level, double x, double y) {
  make_program(opt_);
  return program_->start_offline(level, x, y);
}

// In 5.12 a 3D client script's `player` is its own GameObject, and
// `player.position` reads where it is (Graal_analysis lab #458). The 6.x
// program's `player` is the 2D player, so the control object's position is
// copied onto it each tick ("x y z", Torque metres) for weapons the 3D
// world sends. Read only: a script setting it moves nothing yet.
void Host::mirror_control_position() {
  const graal3d::Link* l = link_.link();
  if (!program_ || !mode3d_ || !l || step_ < 5 || l->controlGhost() < 0) return;
  const graal3d::Vec3 p = l->controlPosition();
  char text[96];
  std::snprintf(text, sizeof text, "%g %g %g", p.x, p.y, p.z);
  program_->scripts().player()->childOrCreate("position")->setString(text);
}

bool Host::tick() {
  if (!program_) return false;
  mirror_control_position();
  const bool go = program_->tick();
  link_.pump();
  view_.link = mode3d_ && view3d ? link_.link() : nullptr;
  if (failed_) {
    failed_ = false;
    program_.reset();
    return false;
  }
  if (warp_pending_) {
    warp_pending_ = false;
    const auto w = warp_;
    return connect(w.name, w.host, w.port);
  }
  return go;
}

}  // namespace Frank
