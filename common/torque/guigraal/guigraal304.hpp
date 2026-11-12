#pragma once

// GuiGraalCtrl for the 3.04 rebuild (Graal_analysis torque/rebuild-plan-3.04.md
// stage 4): the console class that hosts the 2D game. The shipped
// GraalGui.gui creates it as Adventure inside AdventureGui; the shipped
// scripts reach the game only through its 31 methods (torque/engine-304.md).

#include <memory>
#include <string>
#include <vector>

#include "../console/engine/engine.hpp"
#include "game304.hpp"

namespace Torque {

class GuiGraal304 {
 public:
  // Registers the 31 methods on engine's GuiGraalCtrl namespace. The engine
  // must outlive this object; the methods call into it.
  GuiGraal304(Engine& engine, std::unique_ptr<Game304> game);
  GuiGraal304(const GuiGraal304&) = delete;
  GuiGraal304& operator=(const GuiGraal304&) = delete;

  // One 50 ms frame: the server list and the game. The host calls it with
  // the engine's advance; draw = false skips drawing the game.
  void tick(bool draw = true);

  Game304& game() { return *game_; }
  bool activated() const { return activated_; }
  bool playing() const { return playing_; }
  int category() const { return category_; }
  const std::vector<ListServerEntry>& servers() const { return servers_; }

  // The 31 method names in registration order (engine-304.md).
  static const std::vector<std::string>& method_names();

 private:
  void register_methods();
  void echo(const std::string& line);
  void trace_not_yet(const Args& a);
  void set_content(const std::string& control);
  void message_box(const std::string& title, const std::string& text);
  void check_activated();
  void fill_list();
  void select_server(const std::string& id);
  void connect_to(const std::string& host, int port);
  void list_dropped(const std::string& why);
  void game_dropped(const std::string& why);
  std::string pref(const std::string& name) const;

  Engine& engine_;
  std::unique_ptr<Game304> game_;
  std::string password_;
  std::vector<ListServerEntry> servers_;
  int category_ = 2;          // Classic (rebuild policy, README)
  bool listing_ = false;
  bool playing_ = false;
  bool activated_ = false;
};

// The tab a listed name belongs to, from its two-character prefix: 0 Gold
// ("P "), 1 3D ("3 "), 2 Classic (no prefix), 3 Hosted ("H "), -1 hidden ("U ").
int server_category_304(const std::string& name);
// The name without its category prefix (when the second character is a space).
std::string server_name_304(const std::string& name);

} // namespace Torque
