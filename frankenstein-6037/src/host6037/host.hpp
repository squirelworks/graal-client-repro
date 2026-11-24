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
#include <string>

namespace Frank {

// The 6.03r7 row this build sends: the Windows token on Windows, the
// Linux one elsewhere (there is no Mac 6.03r7).
const char* host_build_label();

// Splits a list name: "3 Lab" -> ("Lab", true). A name whose second
// character is a space loses its first two characters either way.
std::string strip_marker(const std::string& raw, bool& is3d);

// Draws the 3D view over the program's frame while the link is up, with
// the 6.x frame as an inset.
class ViewWindow : public Quattro::Draw::Window {
 public:
  explicit ViewWindow(Quattro::Draw::Window& inner) : inner_(inner) {}
  void set_title(const std::string& t) override { inner_.set_title(t); }
  void present(const Torque::Gui::Image& frame) override;
  Quattro::Draw::Key poll_key() override { return inner_.poll_key(); }
  bool held(Quattro::Draw::Key k) const override { return inner_.held(k); }
  const std::string& title() const override { return inner_.title(); }
  bool poll_input(Quattro::Draw::InputEvent& e) override { return inner_.poll_input(e); }

  // Set while the 3D world should be shown; null for the plain 6.x frame.
  const graal3d::Link* link = nullptr;
  bool enabled = true;
  View3DStats last;

 private:
  Quattro::Draw::Window& inner_;
  Torque::Gui::Image out_;
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
};

}  // namespace Frank
