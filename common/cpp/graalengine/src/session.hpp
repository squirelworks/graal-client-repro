// The 2D session of the engine library: what connectToGraalServer starts
// when no session code was set with Engine::setConnector.
//
// 4.04r2, 5.00r7 and 5.12 are gen 5 on the wire, as the Quattro program
// (common/cpp/quattro) is, so the session is that program's: its
// connection (the launcher's build row), level, walking and world passes. The world is drawn
// into the GS2 screen where GraalGui puts its GuiGraalCtrl (GraalControl);
// the arrows come from the MoveMap2D bindings (moveUp2D ...), and the chat
// bar's Adventure_setChat is the player's chat.
#pragma once

#include "graalengine.h"

#include <memory>
#include <string>
#include <vector>

namespace Quattro::Shell {
class Program;
}

namespace graalengine {

class EngineWindow;

class Session2D {
 public:
  struct Login {
    std::string name, host;
    int port = 0;
    std::string account, password, nickname;
    std::string installDir;
    std::string build = "4.04r2";  // the wire row (Engine::setBuild)
  };
  explicit Session2D(Login login);
  ~Session2D();

  // Connects to the first server and logs in. False when the socket failed.
  bool start();
  // Offline mode: no connection; the level or gmap from the install
  // (Quattro::Shell::Program::start_offline). False when it is not there.
  bool startOffline(const std::string& file, double x, double y);
  // One frame: network, walking, the world drawn into the frame.
  void tick();
  // A key binding with no script function, on press and release. True when
  // the session takes it (the four moves).
  bool action(const std::string& cmd, bool down);
  void say(const std::string& text);

  // The last world frame as ARGB, for DrawGraphics.
  const graal_texture& frame() const { return frame_; }
  bool haveFrame() const { return frame_.width > 0; }

  Quattro::Shell::Program& program() { return *program_; }
  const std::vector<std::string>& log() const { return log_; }

 private:
  Login login_;
  std::unique_ptr<EngineWindow> window_;
  std::unique_ptr<Quattro::Shell::Program> program_;
  std::vector<uint32_t> pixels_;
  graal_texture frame_{};
  std::vector<std::string> log_;
  int loginsSeen_ = 0;
};

}  // namespace graalengine
