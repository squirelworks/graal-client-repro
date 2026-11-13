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
#include "../files/gmap.hpp"
#include "../net/connection.hpp"
#include "../world/actions.hpp"
#include "../world/player.hpp"
#include "../world/walk.hpp"
#include "gui_host.hpp"
#include "scripts.hpp"

#include <map>

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
  std::string program;  // the player's own 6.x program file, for its StartScript_* shell
  int width = 640;     // window size: see README, "Window size"
  int height = 480;
};

class Program {
 public:
  Program(const Net::BuildProfile& profile, Options opt, Draw::Window& window);

  bool start();
  // Offline mode: no session, the level (or a gmap's part) from the
  // player's folder, walking across the gmap's parts at the edges. `file`
  // is a .graal/.nw level or a .gmap, looked up under the assets folder;
  // `part` is the gmap's start level (empty: the centre cell). False when
  // the file or its start level is not there.
  bool start_offline(const std::string& file, double x, double y, const std::string& part = {});
  bool offline() const { return offline_; }
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
  void set_object_tables(const World::ObjectTables& t) { object_tables_ = t; }
  Draw::Assets& assets() { return *assets_; }
  const std::string& level_name() const { return level_name_; }
  // Pass names of the last frame, in the order they ran.
  const std::vector<std::string>& last_passes() const { return passes_; }
  std::function<void(const std::string&)> log;

 private:
  void on_message(int id, std::string_view body);
  void load_local_level(const std::string& name);
  bool load_offline_level(const std::string& name);
  void read_level_script();
  void pick_tile_sheet();
  void cross_gmap_edge();
  std::string window_title() const;
  Draw::Actor actor_for(int id, const World::Player& p);
  void draw_hud();

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
  bool offline_ = false;
  Files::Gmap gmap_;
  bool have_gmap_ = false;
  std::string offline_dir_;  // the offline file's folder, searched first
  // From the offline level's own script (read_level_script).
  std::vector<std::pair<std::string, std::string>> tiledefs_;  // prefix, image; newest first
  std::map<std::string, std::string> replace_ani_;
  std::map<std::string, Draw::Image> sheets_;  // "" is the default sheet
};

}  // namespace Quattro::Shell
