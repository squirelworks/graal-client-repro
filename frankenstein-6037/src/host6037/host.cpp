#include "host.hpp"

#include "../graal3d5120/gs2_3d.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <limits>

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

void FrameCounter::add(double now, double ms) {
  times_.push_back(ms);
  if (first_ < 0) first_ = now;
  last_ = now;
  if (window_start_ < 0) {
    // The first frame opens the window; the frames after it are counted.
    window_start_ = now;
    mean_ms_ = ms;
    return;
  }
  ++window_frames_;
  window_ms_ += ms;
  if (now - window_start_ >= 1.0) {
    fps_ = window_frames_ / (now - window_start_);
    mean_ms_ = window_ms_ / window_frames_;
    window_start_ = now;
    window_frames_ = 0;
    window_ms_ = 0;
  }
}

double FrameCounter::p95_ms() const {
  if (times_.empty()) return 0;
  std::vector<double> t = times_;
  std::sort(t.begin(), t.end());
  return t[std::min(t.size() - 1, size_t(0.95 * double(t.size() - 1) + 0.5))];
}

std::string FrameCounter::summary() const {
  if (times_.empty()) return "no 3D frames drawn";
  std::vector<double> t = times_;
  std::sort(t.begin(), t.end());
  double sum = 0;
  for (double v : t) sum += v;
  const double span = last_ - first_;
  auto pct = [&t](double p) { return t[std::min(t.size() - 1, size_t(p * double(t.size() - 1) + 0.5))]; };
  char line[200];
  std::snprintf(line, sizeof line, "%d 3D frames in %.1f s: %.1f fps, draw mean %.2f ms, p50 %.2f ms, p95 %.2f ms",
                int(t.size()), span, span > 0 ? double(t.size() - 1) / span : 0.0, sum / double(t.size()), pct(0.5),
                pct(0.95));
  return line;
}

bool FrameCounter::due_log(double now, std::string& line, const char* renderer) {
  if (fps_ <= 0 || now < next_log_) return false;
  const bool first = next_log_ == 0;
  next_log_ = now + 5.0;
  if (first) return false;  // the first second is still warming up
  char buf[120];
  std::snprintf(buf, sizeof buf, "Graal3D: %.1f fps, 3D frame %.2f ms (%s)", fps_, mean_ms_, renderer);
  line = buf;
  return true;
}

bool ViewWindow::showing3d() const { return enabled && link && link->loginStep() >= 6 && !last2d_.empty(); }

double ViewWindow::next_frame_at() const {
  return showing3d() ? next_world_ : std::numeric_limits<double>::infinity();
}

void ViewWindow::present(const Torque::Gui::Image& frame) {
  if (!enabled || !link || link->loginStep() < 6 || frame.empty()) {
    world_link_ = nullptr;
    last2d_ = Torque::Gui::Image();
    inner_.present(frame);
    return;
  }
  last2d_ = frame;
  compose(true);
}

bool ViewWindow::refresh() {
  if (!showing3d() || seconds_now() < next_world_) return false;
  compose(false);
  return true;
}

void ViewWindow::compose(bool) {
  const Torque::Gui::Image& frame = last2d_;
  const double now = seconds_now();
  const bool stale = world_link_ != link || world_.width != frame.width || world_.height != frame.height;
  if (stale || now >= next_world_) {
    if (world_.width != frame.width || world_.height != frame.height)
      world_ = Torque::Gui::Image(frame.width, frame.height);
    // The 5.12 renderer; black until the server names a Camera, as the 5.12.
    const bool drawn = draw_world3d(world_, *link, world3d, now, &last);
    world_link_ = link;
    ++worlds_drawn;
    const double end = seconds_now();
    const double took = end - now;
    if (drawn) counter.add(end, took * 1000.0);
    if (std::string line; log && counter.due_log(end, line, renderer_name())) log(line);
    if (world3d.renderer && std::string(world3d.renderer->name()) != "software") {
      // The GPU: as often as max_fps allows.
      next_world_ = max_fps > 0 ? std::max(end, now + 1.0 / max_fps) : end;
    } else {
      // The software rasteriser takes at most about half the time
      // (after a frame that took t, the next waits t).
      next_world_ = end + took;
      if (max_fps > 0) next_world_ = std::max(next_world_, now + 1.0 / max_fps);
    }
  }
  out_ = world_;
  draw_inset(out_, frame, 4);
  if (overlay && overlay->width == out_.width && overlay->height == out_.height) {
    for (int y = 0; y < out_.height; ++y)
      for (int x = 0; x < out_.width; ++x) {
        const Torque::Gui::Color c = overlay->at(x, y);
        if (c.a == 0) continue;
        Torque::Gui::Color& d = out_.at(x, y);
        if (c.a == 255) {
          d = c;
          continue;
        }
        auto mix = [&](int a, int b) { return static_cast<uint8_t>((a * c.a + b * (255 - c.a)) / 255); };
        d = {mix(c.r, d.r), mix(c.g, d.g), mix(c.b, d.b), 255};
      }
  }
  // seihai3d chat_3d: the chat lines bottom right, over the scene (the
  // 5.12 shows no chat in 3D; this is the extension's own).
  for (size_t i = 0; i < chat_lines.size(); ++i) {
    const int y = out_.height - 14 * int(chat_lines.size() - i) - 6;
    draw_text(out_, out_.width / 4 + 12, y, chat_lines[i], Torque::Gui::Color{255, 255, 255, 255}, true);
  }
  if (show_fps && counter.frames() > 0) {
    char text[96];
    std::snprintf(text, sizeof text, "%.1f fps  %.1f ms  %s", counter.fps(), counter.mean_ms(), renderer_name());
    draw_text(out_, 6, 4, text, Torque::Gui::Color{255, 255, 0, 255}, false);
  }
  inner_.present(out_);
}

Host::Host(Quattro::Shell::Options opt, Quattro::Draw::Window& window)
    : profile_(Quattro::Net::find_profile(host_build_label())),
      opt_(std::move(opt)),
      view_(window),
      link_(callbacks()) {
  opt_.build = host_build_label();
  // What the server sends at step 6 is kept in the install's levels3d/
  // (--assets), as a 5.x install keeps it; beside the program without one.
  // It is the first root, so a fresh download wins over an older copy in
  // another root (conformance C028).
  files3d_dir_ = opt_.assets.empty() ? std::string("levels3d") : opt_.assets + "/levels3d";
  view_.world3d.roots.push_back(files3d_dir_);
  // Then levels3d/ beside the program and under each asset root.
  std::vector<std::string> more{"levels3d"};
  for (const auto& r : opt_.asset_roots) more.push_back(r + "/levels3d");
  for (const auto& r : more)
    if (std::find(view_.world3d.roots.begin(), view_.world3d.roots.end(), r) == view_.world3d.roots.end())
      view_.world3d.roots.push_back(r);
  // The player's draw distance, from a 5.12-style game_config.txt in the
  // install, beside the program or in an asset root (T3D-075: 1000 when
  // none sets it).
  std::vector<std::string> configs;
  if (!opt_.assets.empty()) configs.push_back(opt_.assets + "/game_config.txt");
  configs.push_back("game_config.txt");
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
    // The two links live and die together (torque/udp-session.md §1): the
    // session ends, and the program stays up, as the 5.12 dropped to its
    // login when the server stopped (conformance C015, T3D-108).
    mode3d_ = false;
    view_.link = nullptr;
    failed_ = true;
  };
  cb.text = [this](const graal3d::BigText& t) {
    if (program_) program_->server_text(t.s1, t.s2, t.s3, t.data);
  };
  cb.chat3d = [this](const std::string& account, const std::string& text) {
    std::string line = account + ": " + text;
    if (line.size() > 120) line.resize(120);
    for (char& c : line)
      if (static_cast<unsigned char>(c) < 32) c = ' ';
    auto& lines = view_.chat_lines;
    lines.push_back(line);
    if (lines.size() > ViewWindow::kChatLines) lines.erase(lines.begin());
    say("Graal3D chat: " + line);
  };
  return cb;
}

Host::~Host() { close(); }

void Host::close() {
  link_.close();
  view_.link = nullptr;
  view_.overlay = nullptr;
  mode3d_ = false;
  program_.reset();
}

void Host::make_program(const Quattro::Shell::Options& opt) {
  view_.overlay = nullptr;
  program_ = std::make_unique<Quattro::Shell::Program>(*profile_, opt, view_);
  view_.overlay = &program_->screen_overlay();
  program_->log = [this](const std::string& s) { say(s); };
  // In 3D, a file the 2D side did not ask for is a 3D file: the shapes
  // and textures asked for below, and what the server pushes (terrain).
  program_->claims_file = [this](const std::string&) { return mode3d_; };
  program_->take_file = [this](const std::string& name, const std::string& data) { save_3d_file(name, data); };
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
    // The 5.12's GS2 3D classes (GameObject, Camera) and their members.
    install_gs2_3d(program_->scripts().machine());
    camera_var_.reset();
    timevar3_known_ = false;
  }
  // The GS2 show-images (every layer, in window pixels) also come as an
  // overlay of its own, drawn over the whole 3D view as the 5.12 drew GS2
  // GUIs over its scene (T3D-058, conformance C010).
  program_->set_screen_overlay(mode3d_ && view3d);
}

bool Host::connect(const std::string& raw_name, const std::string& host, uint16_t port) {
  bool is3d = false;
  server_ = strip_marker(raw_name, is3d);
  link_.close();
  mode3d_ = false;
  step_ = 0;
  view_.link = nullptr;
  asked3d_.clear();
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
    // seihai3d v1: frame_stats and chat_3d, the bits this client acts on.
    l.seihai3dHello = seihai3d;
    l.seihai3dCaps = graal3d::seihai3d::kFrameStats | graal3d::seihai3d::kChat3d;
    view_.chat_lines.clear();
    next_stats_ms_ = 0;
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
  graal3d::Link* l = link_.link();
  if (!program_ || !mode3d_ || !l || step_ < 5 || l->controlGhost() < 0) return;
  auto pos = program_->scripts().player()->childOrCreate("position");
  // A script that set player.position since the last tick moves the
  // object there, as a 5.12 script setting it did (lab #458).
  const std::string now = pos->string();
  if (!position_written_.empty() && now != position_written_) {
    float x = 0, y = 0, z = 0;
    if (std::sscanf(now.c_str(), "%f %f %f", &x, &y, &z) == 3 && std::isfinite(x) && std::isfinite(y) &&
        std::isfinite(z))
      link_.move_control({x, y, z});
  }
  const graal3d::Vec3 p = l->controlPosition();
  char text[96];
  std::snprintf(text, sizeof text, "%g %g %g", p.x, p.y, p.z);
  position_written_ = text;
  pos->setString(text);
}

// The arrow keys walk the 6.x player; in 3D the own object takes the same
// steps, a tile a metre, the 2D y down being the Torque -y (the Seihai
// gserver's 2D players in 3D: x, -y). Only a step taken with an arrow key
// held moves it: a warp or a server move of the 2D player does not.
void Host::walk_in_3d() {
  if (!program_) return;
  const auto& me = program_->me();
  const bool walking = view_.held(Quattro::Draw::Key::Up) || view_.held(Quattro::Draw::Key::Down) ||
                       view_.held(Quattro::Draw::Key::Left) || view_.held(Quattro::Draw::Key::Right);
  const double dx = me.x - walk_x_, dy = me.y - walk_y_;
  if (walk_known_ && walking && me.level == walk_level_ && (dx != 0 || dy != 0) && std::fabs(dx) < 4 &&
      std::fabs(dy) < 4 && mode3d_ && step_ >= 5 && link_.link()) {
    graal3d::Vec3 p = link_.link()->controlPosition();
    p.x += static_cast<float>(dx);
    p.y -= static_cast<float>(dy);
    link_.move_control(p);
  }
  walk_known_ = true;
  walk_level_ = me.level;
  walk_x_ = me.x;
  walk_y_ = me.y;
}

// Step 6 waits for the shapes and textures the world names (5.12 asks by
// lower-case name over TCP). Each shape the world names is asked for once
// a session even when a copy is cached, as the 5.12 asked again on a
// second visit and drew the server's newer copy (conformance C028); a
// texture only when no root has it.
//
// What goes on the wire follows the 5.12 (T3D-033, conformance C004, C006,
// C007): an image is asked for by its bare name, any image extension
// dropped (it stores the download under that name, which the resolver
// finds); a `.cs` or `.ter` shape is never asked for, as no 5.12 takes
// server TorqueScript or a `.ter` file.
std::string request_name_3d(const std::string& lower_name) {
  const size_t dot = lower_name.rfind('.');
  if (dot == std::string::npos || lower_name.find('/', dot) != std::string::npos) return lower_name;
  const std::string ext = lower_name.substr(dot);
  if (ext == ".cs" || ext == ".ter") return {};
  for (const char* e : {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tga", ".dds", ".jp2", ".mng"})
    if (ext == e) return lower_name.substr(0, dot);
  return lower_name;
}

void Host::ask_for_3d_files() {
  if (!program_ || !mode3d_ || step_ < 6 || !view3d) return;
  auto ask = [this](const std::string& name) {
    const std::string wire = request_name_3d(name);
    if (!wire.empty() && asked3d_.insert(wire).second) program_->ask_file(wire);
  };
  for (const auto& name : view_.world3d.resources.shapesNamed()) ask(name);
  for (const auto& name : view_.world3d.resources.missing()) ask(name);
}

void Host::save_3d_file(const std::string& name, const std::string& data) {
  std::error_code ec;
  std::filesystem::create_directories(files3d_dir_, ec);
  std::ofstream out(std::filesystem::path(files3d_dir_) / name, std::ios::binary | std::ios::trunc);
  out.write(data.data(), static_cast<std::streamsize>(data.size()));
  if (!out) {
    say("Graal3D: could not save " + name);
    return;
  }
  out.close();
  view_.world3d.resources.forget(name);
  view_.world3d.resources.rescan();
  say("Graal3D: got " + name + " (" + std::to_string(data.size()) + " bytes)");
}

// What a 5.12 weapon3d reads of the 3D world each tick: `timevar3`, the
// server's Graal3D clock in seconds running on between its updates (T3D-024),
// and `player.camera`, the view's Camera with its live pose (T3D-140,
// T3D-163: G3DCamera_<account>, read only).
void Host::publish_3d_state() {
  graal3d::Link* l = link_.link();
  if (!program_ || !mode3d_ || !l || step_ < 5) return;
  auto& m = program_->scripts().machine();
  const uint32_t local = Link3D::now_ms();
  if (!timevar3_known_ || l->serverTime() != timevar3_server_) {
    timevar3_known_ = true;
    timevar3_server_ = l->serverTime();
    timevar3_local_ = local;
  }
  const double tv3 = timevar3_server_ / 1000.0 + static_cast<double>(local - timevar3_local_) / 1000.0;
  m.universe()->childOrCreate("timevar3")->setNumber(tv3);

  // seihai3d frame_stats: about every 5 s once agreed.
  if (l->extHas(graal3d::seihai3d::kFrameStats) && view_.counter.frames() > 0 && local >= next_stats_ms_) {
    if (next_stats_ms_ != 0)
      l->sendFrameStats(view_.counter.fps(), view_.counter.p95_ms(), static_cast<int>(l->ghosts().size()),
                        view_.counter.mean_ms());
    next_stats_ms_ = local + 5000;
  }

  const auto cam = l->ghosts().find(l->cameraGhost());
  if (cam == l->ghosts().end() || cam->second.className != "Camera") return;
  if (!camera_var_) {
    camera_var_ = std::make_shared<GameObject3D>("G3DCamera_" + opt_.account, "Camera");
    camera_var_->mirror = true;
  }
  const graal3d::GameObjectState& o = cam->second.camera.object;
  camera_var_->pose.p = {o.position.x, o.position.y, o.position.z};
  g3d_set_wire_rotation(camera_var_->pose, {o.axis.x, o.axis.y, o.axis.z}, o.angle);
  camera_var_->publish();
  program_->scripts().player()->childOrCreate("camera")->setObject(camera_var_);
}

bool Host::tick() {
  if (!program_) return false;
  mirror_control_position();
  publish_3d_state();
  const bool go = program_->tick();
  walk_in_3d();
  ask_for_3d_files();
  link_.pump();
  view_.link = mode3d_ && view3d ? link_.link() : nullptr;
  if (failed_) {
    // The 3D session is over; the program keeps running (its own TCP
    // drop shows as the 6.x does), and the window stays up until closed.
    failed_ = false;
    link_.close();
    say("Graal3D: disconnected from the game server");
  }
  if (warp_pending_) {
    warp_pending_ = false;
    const auto w = warp_;
    return connect(w.name, w.host, w.port);
  }
  return go;
}

}  // namespace Frank
