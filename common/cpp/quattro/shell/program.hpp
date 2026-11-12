// The Quattro program loop: the session, the world it fills, the world
// passes and the window, one tick every 50 ms (the frame gate the lab saw:
// half a tile per 50 ms walking, protocol/v5v6-lab-play.md).
//
// This is the shell before the GS2 machine is hosted. The original's shell
// dialogs (StartScript_GraalGui and the rest) and the Login server's GUI are
// scripts; until common/cpp/gs2 is wired in, the program starts straight
// into the session and draws only the world.
#pragma once

#include "../draw/window.hpp"
#include "../draw/world.hpp"
#include "../net/connection.hpp"

#include <functional>
#include <memory>
#include <string>

namespace Quattro::Shell {

struct Options {
  std::string build = "6.03r7";
  std::string host;
  uint16_t port = 0;
  std::string account;
  std::string password;
  std::string language = "English";
  std::string assets;  // the player's own Graal folder (levels, pics1.png)
  int width = 640;     // window size: see README, "Window size"
  int height = 480;
};

class Program {
 public:
  Program(const Net::BuildProfile& profile, Options opt, Draw::Window& window);

  bool start();
  // One tick: network, keys, draw, present. False when the program should end.
  bool tick();

  const Draw::WorldState& world() const { return world_; }
  Net::Session& session() { return session_; }
  const std::string& level_name() const { return level_name_; }
  // Pass names of the last frame, in the order they ran.
  const std::vector<std::string>& last_passes() const { return passes_; }
  std::function<void(const std::string&)> log;

 private:
  void on_message(int id, std::string_view body);
  void load_local_level(const std::string& name);
  std::string window_title() const;

  const Net::BuildProfile& profile_;
  Options opt_;
  Draw::Window& window_;
  Net::Session session_;
  Draw::WorldState world_;
  Draw::WorldRenderer renderer_;
  Draw::Canvas canvas_;
  std::string level_name_;
  std::vector<std::string> passes_;
  bool quit_ = false;
};

}  // namespace Quattro::Shell
