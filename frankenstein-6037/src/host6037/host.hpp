// The Frankenstein 6.037 host: the 6.03r7 Quattro program with the 5.12
// Graal3D link folded in.
//
// The 2D side is common/cpp/quattro's Shell::Program on the 6.03r7 wire
// row, the same program Graal603w hands its game to. What the 6.03r7
// client never did, and 5.12 did, is the `3 ` server: a server whose list
// name starts with `3 `, picked from the list or reached by a Login-server
// 178 warp, loses the marker and is entered on two links at once. The
// Torque link goes to the listed port + 1 over UDP and the TCP login
// follows on the listed port, as the 5.12 engine library does
// (common/cpp/graalengine Engine::connect, graal3d/torque-engine-4x.md).
// The two links live and die together.
#pragma once

#include "../../../common/cpp/quattro/shell/program.hpp"
#include "../graal3d5120/view3d.hpp"
#include "../net/udp/link3d.hpp"

#include <functional>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace Frank {

// The 6.03r7 row this build sends: the Windows token on Windows, the
// Linux one elsewhere (there is no Mac 6.03r7).
const char* host_build_label();

// The name a 3D file is asked for by (lower case): an image without its
// extension, "" for a name the 5.12 never asks for (.cs, .ter).
std::string request_name_3d(const std::string& lower_name);

// Splits a list name: "3 Lab" -> ("Lab", true). A name whose second
// character is a space loses its first two characters either way.
std::string strip_marker(const std::string& raw, bool& is3d);

// Counts the 3D frames the view draws: the frame rate over the last
// second (shown on screen and logged), and every frame's draw time for a
// summary at the end of a run.
class FrameCounter {
 public:
  // A frame drawn at `now` (seconds) that took `ms` to draw.
  void add(double now, double ms);
  // Frames a second over the last whole second, and the mean draw time.
  double fps() const { return fps_; }
  double mean_ms() const { return mean_ms_; }
  int frames() const { return int(times_.size()); }
  // "<frames> 3D frames in <s> s: <fps> fps, draw mean <ms> ms, p50 <ms>, p95 <ms>".
  std::string summary() const;
  // True once a second: the line to log.
  bool due_log(double now, std::string& line, const char* renderer);

 private:
  std::vector<double> times_;  // every frame's draw time, ms
  double first_ = -1, last_ = -1;
  double window_start_ = -1;
  int window_frames_ = 0;
  double window_ms_ = 0;
  double fps_ = 0, mean_ms_ = 0;
  double next_log_ = 0;
};

// Draws the 3D view over the program's frame while the link is up, with
// the 6.x frame as an inset.
//
// The 6.x program presents a frame each 50 ms tick. The 3D frame is drawn
// on its own clock between ticks (refresh(), called by the main loop), so
// it is not held to the tick rate: up to max_fps a second with OpenGL. The
// software renderer, which can take longer than a tick, keeps its earlier
// rule: after a frame that took t, the next waits t (the 2026-11-26 lab).
class ViewWindow : public Quattro::Draw::Window {
 public:
  explicit ViewWindow(Quattro::Draw::Window& inner) : inner_(inner) {}
  void set_title(const std::string& t) override { inner_.set_title(t); }
  void present(const Torque::Gui::Image& frame) override;
  Quattro::Draw::Key poll_key() override { return inner_.poll_key(); }
  bool held(Quattro::Draw::Key k) const override { return inner_.held(k); }
  const std::string& title() const override { return inner_.title(); }
  bool poll_input(Quattro::Draw::InputEvent& e) override { return inner_.poll_input(e); }

  // Draws and presents a new 3D frame over the last 6.x frame when one is
  // due. True when it did.
  bool refresh();
  // When the next 3D frame is due (steady-clock seconds); infinity while
  // the 3D view is not shown.
  double next_frame_at() const;
  bool showing3d() const;

  // Set while the 3D world should be shown; null for the plain 6.x frame.
  const graal3d::Link* link = nullptr;
  bool enabled = true;
  View3DStats last;
  World3D world3d;  // the renderer and its state (resource folders in world3d.roots)
  int worlds_drawn = 0;  // 3D frames drawn (the inset is redrawn on every frame)
  int max_fps = 60;      // 0: as fast as the renderer goes
  bool show_fps = true;  // the counter in the top-left corner
  FrameCounter counter;
  std::function<void(const std::string&)> log;
  // The program's GS2 screen layer, drawn over the whole 3D frame (null: none).
  const Torque::Gui::Image* overlay = nullptr;

 private:
  void compose(bool fresh2d);
  const char* renderer_name() const { return world3d.renderer ? world3d.renderer->name() : "software"; }

  Quattro::Draw::Window& inner_;
  Torque::Gui::Image out_;
  Torque::Gui::Image last2d_;  // the 6.x frame of the last tick
  // The last 3D frame, and when the next may be drawn.
  Torque::Gui::Image world_;
  const graal3d::Link* world_link_ = nullptr;
  double next_world_ = 0;
};

class Host {
 public:
  Host(Quattro::Shell::Options opt, Quattro::Draw::Window& window);
  ~Host();

  // Connects to opt.server_name on opt.host:opt.port (a `3 ` name enters 3D).
  bool start();
  bool start_offline(const std::string& level, double x, double y);
  // One tick of the program and the link. False when the run should end.
  bool tick();
  // Ends both links: the 3D disconnect (0x26) goes out, the program goes.
  void close();

  Quattro::Shell::Program& program() { return *program_; }
  const Link3D& link3d() const { return link_; }
  bool mode3d() const { return mode3d_; }
  int login_step() const { return step_; }
  const std::string& server() const { return server_; }
  ViewWindow& view() { return view_; }
  // Tests fix the connect sequence the recorded 5.12 session used.
  uint32_t connect_sequence = 0;
  bool view3d = true;

  std::function<void(const std::string&)> log;

 private:
  Link3D::Callbacks callbacks();
  bool connect(const std::string& raw_name, const std::string& host, uint16_t port);
  void make_program(const Quattro::Shell::Options& opt);
  void say(const std::string& s) {
    if (log) log(s);
  }
  void mirror_control_position();
  void walk_in_3d();
  void ask_for_3d_files();
  void save_3d_file(const std::string& name, const std::string& data);
  void publish_3d_state();

  const Quattro::Net::BuildProfile* profile_;
  Quattro::Shell::Options opt_;
  ViewWindow view_;
  std::unique_ptr<Quattro::Shell::Program> program_;
  Link3D link_;
  bool mode3d_ = false;
  int step_ = 0;
  std::string server_;
  bool warp_pending_ = false;
  Quattro::Net::ServerWarp warp_;
  bool failed_ = false;
  // player.position as last written, to see a script set it.
  std::string position_written_;
  // The 2D player where the last tick left it, for the walk in 3D.
  bool walk_known_ = false;
  std::string walk_level_;
  double walk_x_ = 0, walk_y_ = 0;
  // Step-6 files: the folder they are saved in (a renderer root), and the
  // names asked for this session.
  std::string files3d_dir_;
  std::set<std::string> asked3d_;
  // timevar3: the server time last seen and the local clock then.
  bool timevar3_known_ = false;
  uint32_t timevar3_server_ = 0, timevar3_local_ = 0;
  std::shared_ptr<class GameObject3D> camera_var_;
};

}  // namespace Frank
