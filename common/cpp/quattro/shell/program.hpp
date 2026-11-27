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
#include "../world/effects.hpp"
#include "../world/floor_items.hpp"
#include "../world/player.hpp"
#include "../world/walk.hpp"
#include "../world/weapons.hpp"
#include "../world/health.hpp"
#include "../world/item_list.hpp"
#include "../world/npcs.hpp"
#include "gui_host.hpp"
#include "scripts.hpp"
#include "weapon_api.hpp"

#include <filesystem>
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
  // The Seihai secure login (SEI00001; not in any original client). Off is
  // the original login byte for byte. quattro-play sets it from the
  // player's setting (GRAAL_SECURE_LOGIN, secure_login.txt) or
  // --secure-login; server_key (base64), when set, is the only key trusted.
  Net::Sec::Mode secure = Net::Sec::Mode::Off;
  std::string server_key;
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
  // A key binding by its command, on press and release (the engine
  // library's MoveMap2D: moveUp2D ... and doA, doS, doS2, doD, doQ). Held
  // next to the window's own keys. False for a command it does not take.
  bool action(std::string_view command, bool down);

  const Draw::WorldState& world() const { return world_; }
  World::Player& me() { return me_; }
  const World::Player& me() const { return me_; }
  const std::map<int, World::Player>& others() const { return others_; }
  Net::Session& session() { return session_; }
  ScriptHost& scripts() { return scripts_; }
  // A Graal text message from the Graal3D server (shell/server_text.cpp).
  void server_text(const std::string& weapon, const std::string& type, const std::string& option,
                   const std::string& data);
  GuiHost& gui() { return *gui_; }
  // Replaces the wall table (tests; arrays.dat from --assets otherwise).
  void set_tile_types(const World::TileTypes& t) { tile_types_ = t; }
  const World::TileTypes& tile_types() const { return tile_types_; }
  void set_object_tables(const World::ObjectTables& t) { object_tables_ = t; }
  const World::Effects& effects() const { return effects_; }
  const World::FloorItems& floor_items() const { return floor_items_; }
  // The weapon list (33, 34, 43, 194) and the bombs, blasts and shots in the level.
  const World::WeaponList& weapons() const { return weapons_; }
  const std::map<int, World::ServerNpc>& npcs() const { return npcs_; }
  gs2::VarPtr npc_script(int id) const {
    auto it = npc_vars_.find(id);
    return it == npc_vars_.end() ? nullptr : it->second;
  }
  const World::Combat& combat() const { return combat_; }
  const World::Health& health() const { return health_; }
  // The Q item list window (2.05's layout) is open.
  bool item_list_open() const { return item_list_open_; }
  std::vector<World::ItemCell> item_cells() const;
  // Uses the selected weapon, as D does: a server weapon with a script gets
  // onWeaponFired; a built-in one lays its bomb or fires its shot.
  void fire_weapon();
  // What the weapon scripts set (shell/weapon_api.cpp).
  const ShowImages& show_images() const { return show_images_; }
  // A host that draws a view of its own over the frame (the Frankenstein
  // 6.037's 3D view) asks for the screen layer (show-images on layer 4 and
  // up) a second time, alone on a transparent image of the frame's size.
  void set_screen_overlay(bool on) { screen_overlay_on_ = on; }
  const Torque::Gui::Image& screen_overlay() const { return screen_overlay_; }
  const std::string& sign_text() const { return sign_text_; }  // say2's box; empty when closed
  double freeze_left() const { return freeze_left_; }
  bool def_movement() const { return def_movement_; }
  bool weapons_enabled() const { return weapons_enabled_; }
  // enableselectweapons / disableselectweapons: Q/Tab may open the item list.
  bool select_weapons_enabled() const { return select_weapons_enabled_; }
  // noplayerkilling: false turns off player-vs-player damage in this level.
  bool player_killing() const { return player_killing_; }
  // showstats bits (default 0x1FF): which HUD parts draw.
  int show_stats() const { return show_stats_; }
  // seteffect(r,g,b,a): global day/night tint (0..1 each; default 1,1,1,1).
  const double* screen_effect() const { return screen_effect_; }
  const std::string& shoot_params() const { return shoot_params_; }
  Draw::Assets& assets() { return *assets_; }
  const std::string& level_name() const { return level_name_; }
  // 6.03r7's PLO 111: the body as sent, kept byte for byte; with an
  // assets folder it also replaces <assets>/creationtime.dat
  // (Graal_analysis protocol/v6x-clients.md).
  const std::string& creation_time() const { return creation_time_; }
  // PLO 198: one GINT5 the server sets; nothing reads it back.
  uint64_t server_value_198() const { return value_198_; }
  // PLO 109: a file the server redirects to a URL (GINT5 time, name,
  // URL). Kept only: the HTTP fetch is not rebuilt.
  struct FileRedirect {
    uint64_t time = 0;
    std::string url;
  };
  const std::map<std::string, FileRedirect>& file_redirects() const { return file_redirects_; }
  // Files asked for with C->S 23, lower case.
  const std::set<std::string>& asked() const { return asked_; }
  // Where this server's basepackage.gupd is kept under the assets folder
  // ("updatepackages/basepackage.gupd" for the Login server).
  static std::string package_dir(const std::string& server);
  // Pass names of the last frame, in the order they ran.
  const std::vector<std::string>& last_passes() const { return passes_; }
  std::function<void(const std::string&)> log;
  // Files a host takes for itself (Frankenstein 6.037's 3D shapes and
  // textures), outside the 2D asset bookkeeping: ask_file() asks with
  // PLI_WANTFILE; a file the 2D side did not ask for and claims_file()
  // says yes to goes to take_file() (size-capped like downloads) instead
  // of being dropped. Unset: as before.
  void ask_file(const std::string& name);
  std::function<bool(const std::string& name)> claims_file;
  std::function<void(const std::string& name, const std::string& data)> take_file;

  // The player list a 5.x engine reports to its launcher (the lab's 5.12,
  // 2026-11-13): one row per player the server names, across levels,
  // sent again whenever a shown field changes, and deleted when the
  // player leaves. The client's own row has flag kListSelf.
  struct ListRow {
    int id = 0;
    std::string nick, head, props;  // props: "account=..,level=..,communityname=..,attr[1]=.."
    int flags = 0;
    bool operator==(const ListRow& o) const {
      return id == o.id && nick == o.nick && head == o.head && props == o.props && flags == o.flags;
    }
  };
  static constexpr int kListSelf = 0x4000, kListServer = 0x2000;
  std::function<void(const ListRow&)> list_update;
  std::function<void(int id)> list_delete;
  // The server accepted a login (its first PLO_PLAYERPROPS after each
  // connect): the 5.12 launcher hears OnServerLogin only then.
  std::function<void()> logged_in;
  // The link to a server dropped (not a warp the program followed).
  std::function<void(const std::string& why)> disconnected;
  const std::map<int, ListRow>& player_list() const { return listed_; }
  int link_warps_sent() const { return link_warps_sent_; }  // LEVELWARPs asked for by walking onto a link

 private:
  void on_message(int id, std::string_view body);
  void load_local_level(const std::string& name);
  bool load_offline_level(const std::string& name);
  void read_level_script();
  void pick_tile_sheet();
  void cross_gmap_edge();
  // PLI_ENTERLEVEL (46, `c 1`) on each level entry, before the first props
  // of the new level, for the builds that send it.
  void send_enter_level();
  // PLO_LOADGANI (195): header lines for a named gani (Graal_analysis
  // protocol/probe-targets-2026-11-18.md, "PLO_LOADGANI (195)").
  void load_gani(std::string_view body);
  // A finished, non-looping gani of the player's own falls back to its
  // SETBACKTO, which goes to the server as prop 10.
  void gani_fall_back(World::Player& p);
  std::string window_title() const;
  Draw::Actor actor_for(int id, const World::Player& p);
  // A list 24 sprite's rect on sprites.png; width 0 when there is none.
  Draw::Rect sprite_cell(int sprite) const;
  void draw_hud();
  // Own-project Ctrl+Enter composer; native shortcuts/Unicode are not inferred.
  bool chat_available();
  bool chat_controls_held() const;
  bool chat_input(const Draw::InputEvent& e, bool enter_pressed);
  void cancel_chat_input();
  void draw_chat_input();
  std::vector<std::string> roots() const;
  bool load_tile_sheet();
  void want_file(const std::string& name);
  void ask_update_packages();
  std::string package_path(const std::string& server) const;
  void ask_for_missing();
  void save_download(const std::string& name, const std::string& data);
  bool wanted(const std::string& name) const;  // asked for, and a safe name
  void list_player(int id, const World::Player& p, int flags);
  void unlist(int id);
  void unlist_all();
  void send_packets(const std::vector<World::Packet>& out);
  void send_counts();  // props 4 and 5 when the arrow or bomb count changed
  void register_weapon_commands();
  // shell/weapon_api.cpp: the GS2 weapon commands and events.
  void register_script_commands();
  // Server NPCs (3, 131, 29, 150, 151) on the 3.153-5.12 path (shell/npcs.cpp).
  bool on_npc_message(int id, std::string_view body);
  void register_npc_commands();
  void npc_to_script(int id);     // the NPC's props onto its script object
  void npcs_from_scripts();       // what the scripts changed back onto the NPCs
  void npc_touches();             // playertouchsme as the player walks into one
  void npcs_to_world();           // the visible ones into world_.npcs
  void clear_level_npcs();        // ids below 1000 (a new level)
  void drop_npc(int id);
  int npc_of(const gs2::Var* v) const;  // the NPC whose script object this is, or 0
  void script_input(const Draw::InputEvent& e);  // onKeyPressed, onMouseDown, the say2 box
  void script_tick();                            // freeze time, hidden player, focus
  bool held_index(int i) const;                  // keydown(i): up,left,down,right,S,A,D,M,tab,Q,P
  void draw_show_images(bool screen_layer);
  // GuiShowImgCtrl: ani (playerlook / actor) or plain `image`, plus offsets.
  // Graal_analysis client-internals/showimg-particles-and-gs2-format.md.
  void draw_showimg_ctrl(const gs2::gui::Control& c, const gs2::gui::Rect& r);
  void draw_sign();
  void on_destroy(const gs2::VarPtr& v);
  void player_changed(int old_power);            // onPlayerHurt, onPlayerDies
  void sync_player_in();   // the script's `player` from me_
  void sync_player_out();  // what a script changed back into me_
  // Copy World::Player fields onto a GS2 object (findplayer for others).
  static void fill_player_object(const gs2::VarPtr& pl, const World::Player& p,
                                 const std::string& account_fallback = {});
  void combat_effects();   // bombs, blasts and shots as effect sprites
  void item_list_input(const Draw::InputEvent& e);
  void draw_item_list();

  const Net::BuildProfile& profile_;
  Options opt_;
  Draw::Window& window_;
  Net::Session session_;
  Draw::WorldState world_;
  World::Player me_;
  std::map<int, World::Player> others_;
  std::map<int, World::Player> everyone_;  // every player the server named, across levels
  std::map<int, ListRow> listed_;          // what the launcher was last told
  int self_list_id_ = 1;
  World::MoveSender mover_;
  World::Walker walker_;
  World::TileTypes tile_types_;
  World::ObjectTables object_tables_;
  World::ItemKeys item_keys_;
  unsigned action_held_ = 0;     // bindings held by action(), one bit per binding
  unsigned action_pressed_ = 0;  // bindings pressed since the last tick, kept for one tick
  unsigned action_moves_ = 0, action_items_ = 0;  // what they hold: walk keys, World::ItemKey bits
  bool action_d_ = false, action_q_ = false;      // doD, doQ held
  World::Effects effects_;
  World::FloorItems floor_items_;
  World::WeaponList weapons_;
  World::Combat combat_;
  World::Health health_;
  double entry_x_ = 30, entry_y_ = 30;  // where the level was entered
  bool item_list_open_ = false;
  bool weapon_keys_[2] = {false, false};  // D, and Q/Tab, last tick (with a weapon shown)
  int sent_arrows_ = -1, sent_bombs_ = -1;
  struct {
    double x = 0, y = 0;
    int dir = 0, bombs = 0, arrows = 0, z = 0;
    std::string chat, ani;
    double freeze = 0;
  } script_seen_;
  ShowImages show_images_;
  bool screen_overlay_on_ = false;
  Torque::Gui::Image screen_overlay_;
  std::string sign_text_;
  double freeze_left_ = 0;  // seconds the player stays frozen
  double hide_left_ = 0;    // hideplayer
  bool def_movement_ = true, weapons_enabled_ = true, select_weapons_enabled_ = true;
  bool player_killing_ = true;  // noplayerkilling clears this for the level
  int show_stats_ = 0x1FF;  // Adventure default: all HUD parts
  // seteffect: day/night multiply on the level (below the HUD).
  double screen_effect_[4] = {1, 1, 1, 1};
  std::string shoot_params_;
  std::set<int> keys_down_;  // virtual-key codes held (from the window's input events)
  bool chat_active_ = false, chat_release_pending_ = false;
  bool chat_blocks_tick_ = false;
  bool chat_enter_held_ = false, chat_escape_held_ = false;
  std::set<int> chat_owned_keys_;  // consumed keydowns remain owned until their keyups
  std::string chat_draft_;  // printable ASCII, at most the 223-byte GSTRING limit
  bool props_sent_ = false;
  bool enter_level_pending_ = false;
  // 5.24 on: the own chat clears itself 3 s after it was set (lab: 2.97
  // to 2.99 s after the server set it, prop 12 sent empty).
  std::string own_chat_seen_;
  int own_chat_since_ = 0;
  void clear_own_chat();
  bool link_warp_pending_ = false;  // a LEVELWARP is out; no second until the server answers
  int link_warps_sent_ = 0;
  std::string link_dest_;  // the pending warp's level and arrival
  double link_x_ = 0, link_y_ = 0;
  // Walked by (dx, dy): onto a level link, ask for it (online) or load it (offline).
  void follow_link(double dx, double dy);
  std::set<std::string> ganis_loaded_;  // lower-case gani names shown this run
  std::string creation_time_;
  uint64_t value_198_ = 0;
  std::map<std::string, FileRedirect> file_redirects_;
  ScriptHost scripts_;
  std::map<int, World::ServerNpc> npcs_;
  std::map<int, gs2::VarPtr> npc_vars_;  // NPCs with a script (131)
  std::set<int> npc_touching_;            // NPCs the player stood in last tick
  // findplayer(account): other players' objects, keyed by lower-case account.
  // Self returns scripts_.player(); missing account returns 0.
  std::map<std::string, gs2::VarPtr> found_players_;
  std::unique_ptr<GuiHost> gui_;
  std::unique_ptr<CanvasPainter> painter_;
  std::string cache_server_;
  Draw::WorldRenderer renderer_;
  std::unique_ptr<Draw::Assets> assets_;
  std::unique_ptr<Draw::Hud> hud_;
  int frame_ = 0;
  std::map<int, std::pair<std::string, int>> gani_start_;  // id (-1 for me) -> gani, first tick
  // GuiShowImgCtrl ani clocks: each control keeps its own start tick.
  std::map<const gs2::gui::Control*, std::pair<std::string, int>> showimg_start_;
  Draw::Canvas canvas_;
  std::string level_name_;
  std::vector<std::string> passes_;
  bool quit_ = false;
  bool offline_ = false;
  int logins_seen_ = 0;
  std::set<std::string> gani_requests_; // per connection, unlike run-wide file requests
  std::filesystem::file_time_type run_start_;  // a cached package older than this counts
  Files::Gmap gmap_;
  bool have_gmap_ = false;
  std::string offline_dir_;  // the offline file's folder, searched first
  // From the offline level's own script (read_level_script).
  std::vector<std::pair<std::string, std::string>> tiledefs_;  // prefix, image; newest first
  std::map<std::string, std::string> replace_ani_;
  std::map<std::string, Draw::Image> sheets_;  // "" is the default sheet
  std::set<std::string> asked_;                // files asked for (C->S 23), lower case
  std::set<std::string> refused_;              // asked for, but dropped as too large
  std::map<std::string, std::string> large_;   // large files being received
};

}  // namespace Quattro::Shell
