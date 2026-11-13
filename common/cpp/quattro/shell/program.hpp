// The Quattro program loop: the session, the world it fills, the world
// passes and the window, one tick every 50 ms (the frame gate the lab saw:
// half a tile per 50 ms walking, protocol/v5v6-lab-play.md).
//
// Server scripts (weapons and classes) run on the GS2 machine through
// ScriptHost. The original's own shell dialogs (StartScript_GraalGui and
// the rest) are scripts compiled into the program; the rebuild starts
// straight into the session until they are loaded from the player's install.
#pragma once

#include "../draw/hud.hpp"
#include "../draw/window.hpp"
#include "../draw/world.hpp"
#include "../net/connection.hpp"
#include "../world/actions.hpp"
#include "../world/player.hpp"
#include "../world/walk.hpp"
#include "gui_host.hpp"
#include "scripts.hpp"

#include <map>
#include <set>
#include <vector>

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
  std::string nickname;  // empty: "unknown", as the lab's 6.03r7 sent
  // The first server's name: "Login" (the lobby) unless the launcher
  // connected to a server by name (the engine library's connectToGraalServer).
  std::string server_name = "Login";
  std::string assets;  // the player's own Graal folder (levels, pics1.png)
  // More folders searched after `assets`, laid out the same way (the
  // engine library's graal-assets/<build>/ and graal-assets/common/).
  std::vector<std::string> asset_roots;
  // Asks the server for images the folders lack (C->S 23) and keeps what
  // it sends in <assets>/levels/images/downloads/. Off: nothing is asked.
  bool download_files = false;
  // The most a download may hold (a tile sheet is about 200 KB); a larger
  // one is dropped and not asked for again.
  size_t max_download = 8u << 20;
  std::string program;  // the player's own 6.x program file, for its StartScript_* shell
  int width = 640;     // window size: see README, "Window size"
  int height = 480;
};

class Program {
 public:
  Program(const Net::BuildProfile& profile, Options opt, Draw::Window& window);

  bool start();
  // One tick: network, keys, draw, present. False when the program should end.
  bool tick();
  // Sets the player's chat and sends it once the props are out (the
  // engine library's chat bar; Adventure_setChat).
  void say(const std::string& text);

  const Draw::WorldState& world() const { return world_; }
  const World::Player& me() const { return me_; }
  const std::map<int, World::Player>& others() const { return others_; }
  Net::Session& session() { return session_; }
  ScriptHost& scripts() { return scripts_; }
  GuiHost& gui() { return *gui_; }
  // Replaces the wall table (tests; arrays.dat from --assets otherwise).
  void set_tile_types(const World::TileTypes& t) { tile_types_ = t; }
  const World::TileTypes& tile_types() const { return tile_types_; }
  void set_object_tables(const World::ObjectTables& t) { object_tables_ = t; }
  Draw::Assets& assets() { return *assets_; }
  const std::string& level_name() const { return level_name_; }
  // Files asked for with C->S 23, lower case.
  const std::set<std::string>& asked() const { return asked_; }
  // Pass names of the last frame, in the order they ran.
  const std::vector<std::string>& last_passes() const { return passes_; }
  std::function<void(const std::string&)> log;

 private:
  void on_message(int id, std::string_view body);
  void load_local_level(const std::string& name);
  std::string window_title() const;
  Draw::Actor actor_for(int id, const World::Player& p);
  void draw_hud();
  std::vector<std::string> roots() const;
  bool load_tile_sheet();
  void want_file(const std::string& name);
  void ask_for_missing();
  void save_download(const std::string& name, const std::string& data);
  bool wanted(const std::string& name) const;  // asked for, and a safe name

  const Net::BuildProfile& profile_;
  Options opt_;
  Draw::Window& window_;
  Net::Session session_;
  Draw::WorldState world_;
  World::Player me_;
  std::map<int, World::Player> others_;
  World::MoveSender mover_;
  World::Walker walker_;
  World::TileTypes tile_types_;
  World::ObjectTables object_tables_;
  World::ItemKeys item_keys_;
  bool props_sent_ = false;
  ScriptHost scripts_;
  std::unique_ptr<GuiHost> gui_;
  std::unique_ptr<CanvasPainter> painter_;
  std::string cache_server_;
  Draw::WorldRenderer renderer_;
  std::unique_ptr<Draw::Assets> assets_;
  std::unique_ptr<Draw::Hud> hud_;
  int frame_ = 0;
  std::map<int, std::pair<std::string, int>> gani_start_;  // id (-1 for me) -> gani, first tick
  Draw::Canvas canvas_;
  std::string level_name_;
  std::vector<std::string> passes_;
  bool quit_ = false;
  std::set<std::string> asked_;                // files asked for (C->S 23), lower case
  std::set<std::string> refused_;              // asked for, but dropped as too large
  std::map<std::string, std::string> large_;   // large files being received
};

}  // namespace Quattro::Shell
