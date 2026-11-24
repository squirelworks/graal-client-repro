#include "host.hpp"

#include <chrono>

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

void ViewWindow::present(const Torque::Gui::Image& frame) {
  if (!enabled || !link || link->loginStep() < 6 || frame.empty()) {
    inner_.present(frame);
    return;
  }
  out_ = Torque::Gui::Image(frame.width, frame.height);
  last = draw_view3d(out_, link->ghosts(), link->controlGhost(), link->controlPosition());
  draw_inset(out_, frame, 4);
  inner_.present(out_);
}

Host::Host(Quattro::Shell::Options opt, Quattro::Draw::Window& window)
    : profile_(Quattro::Net::find_profile(host_build_label())),
      opt_(std::move(opt)),
      view_(window),
      link_(callbacks()) {
  opt_.build = host_build_label();
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

bool Host::tick() {
  if (!program_) return false;
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
