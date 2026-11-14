#pragma once

// The 2D game behind GuiGraalCtrl, as the control sees it. The real one is
// the 3.04 Pascal game (graal-3.04-G3D03014/src/Game304Lib.lpr) loaded by
// PascalGame304; the tests use a fake. One call per g304_* function.

#include <cstdint>
#include <functional>
#include <string>

namespace Torque {

struct ListServerEntry {
  // The listserver's fields in its order: name, language, description, url,
  // version, players, host, port.
  std::string fields[8];
};

class Game304 {
 public:
  enum State : int { connected = 1, logged_in = 2, board_loaded = 4, playing_offline = 8 };
  enum ListPoll : int { list_none = -2, list_failed = -1, list_waiting = 0, list_done = 1 };

  virtual ~Game304() = default;
  // Each game log line as it is made.
  std::function<void(const std::string&)> on_log;

  virtual std::string error() = 0;
  virtual void set_nickname(const std::string& nick) = 0;

  virtual bool list_open(const std::string& account, const std::string& password) = 0;
  virtual int list_poll() = 0;
  virtual std::string list_status() = 0;
  virtual int list_count() = 0;
  virtual ListServerEntry list_entry(int index) = 0;

  virtual bool connect(const std::string& host, int port, const std::string& account,
                       const std::string& password) = 0;
  virtual bool offline(const std::string& level, double x, double y) = 0;
  virtual std::string offline_path() = 0;   // the install's offline start, or ""

  virtual void key(int dir, bool down) = 0;   // 0 up, 1 left, 2 down, 3 right
  // The game keys of doA, doS, doD, doQ: 0 A (lift, throw, open), 1 S
  // (sword, spin, throw), 2 D (the selected weapon), 3 Q (the item list).
  virtual void action(int which, bool down) = 0;
  virtual void say(const std::string& text) = 0;
  virtual void to_all(const std::string& text) = 0;

  // One 50 ms frame. False when an online link dropped (error() says why).
  virtual bool tick(bool draw) = 0;
  virtual int state() = 0;
  // The last frame, 0xAARRGGBB, rows top down; null before any game.
  virtual const std::uint32_t* frame(int& width, int& height) = 0;
  // "level x y dir" for the local player.
  virtual std::string player() = 0;
};

} // namespace Torque
