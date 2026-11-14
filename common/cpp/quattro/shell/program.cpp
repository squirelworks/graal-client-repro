#include "program.hpp"

#include "../draw/ui_font.hpp"
#include "../net/gtypes.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <sstream>

#include <zlib.h>

namespace Quattro::Shell {

namespace {

bool read_file(const std::string& path, std::string& out) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return false;
  out.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
  return true;
}

std::string lower_name(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

// A file under `root` by its name, any case, in any folder below it.
std::string find_below(const std::string& root, const std::string& name) {
  namespace fs = std::filesystem;
  std::error_code ec;
  const std::string want = lower_name(name);
  for (fs::recursive_directory_iterator it(root, fs::directory_options::skip_permission_denied | fs::directory_options::follow_directory_symlink, ec), end;
       !ec && it != end; it.increment(ec)) {
    if (it->is_regular_file(ec) && lower_name(it->path().filename().string()) == want) return it->path().string();
  }
  return {};
}

// A file name the program may ask for and save in the downloads folder:
// a plain name of at most 128 characters, with no folder, drive or stream
// part (no '/', '\\', ':', ".."), no control characters, and not a Windows
// device name (con, nul, com1 ... with any extension).
bool safe_file_name(const std::string& name) {
  if (name.empty() || name.size() > 128 || name.find("..") != std::string::npos) return false;
  for (unsigned char c : name)
    if (c < 32 || c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' ||
        c == '>' || c == '|')
      return false;
  std::string base = lower_name(name.substr(0, name.find('.')));
  while (!base.empty() && base.back() == ' ') base.pop_back();
  for (const char* dev : {"con", "prn", "aux", "nul"})
    if (base == dev) return false;
  if (base.size() == 4 && (base.compare(0, 3, "com") == 0 || base.compare(0, 3, "lpt") == 0) && base[3] >= '0' &&
      base[3] <= '9')
    return false;
  return true;
}

// The build's label without the platform ("6.03r7").
std::string short_label(const std::string& label) { return label.substr(0, label.find(' ')); }

}  // namespace

Program::Program(const Net::BuildProfile& profile, Options opt, Draw::Window& window)
    : profile_(profile),
      opt_(std::move(opt)),
      window_(window),
      session_(profile, {}),
      canvas_(opt_.width, opt_.height),
      run_start_(std::filesystem::file_time_type::clock::now()) {
  Net::Session::Events ev;
  ev.connecting = [this](const std::string& name, const std::string& addr) {
    if (log) log("connecting to " + name + " (" + addr + ")");
  };
  ev.connect_failed = [this](const std::string& why) {
    if (log) log("connect failed: " + why);
  };
  ev.disconnected = [this](const std::string& why) {
    if (log) log("disconnected: " + why);
    unlist_all();
    if (disconnected) disconnected(why);
  };
  ev.message = [this](int id, std::string_view body) { on_message(id, body); };
  session_.set_events(std::move(ev));
  world_.lobby_tiles = profile_.login_draws_tiles;
  world_.chest_boxes = profile_.draws_chests;
  me_.nickname = opt_.nickname.empty() ? "unknown" : opt_.nickname;  // the lab's 6.03r7 sent "unknown" with no nickname set
  me_.language = opt_.language;
  scripts_.set_send([this](int id, std::string_view body) { return session_.connection().send(id, body); });
  scripts_.on_log = [this](const std::string& s) {
    if (log) log(s);
  };
  register_weapon_commands();
  world_.player.x = 30;
  world_.player.y = 30;
  std::vector<std::string> asset_folders;
  for (const auto& root : roots())
    for (auto& d : Draw::asset_dirs(root)) asset_folders.push_back(std::move(d));
  assets_ = std::make_unique<Draw::Assets>(std::move(asset_folders));
  renderer_.set_assets(assets_.get());
  hud_ = std::make_unique<Draw::Hud>(assets_.get());
  gui_ = std::make_unique<GuiHost>(scripts_.machine());
  gui_->screen().setSize(opt_.width, opt_.height);
  std::vector<std::string> dirs;
  if (!opt_.assets.empty())
    for (const char* sub : {"", "/gui", "/images", "/levels", "/levels/images"}) dirs.push_back(opt_.assets + sub);
  painter_ = std::make_unique<CanvasPainter>(canvas_, dirs);
  painter_->on_engine_control = [this](const gs2::gui::Control& c, const gs2::gui::Rect& r) {
    // The playfield: the world passes inside the control's rectangle.
    if (c.type() != "GuiGraalCtrl" && c.type() != "guigraalctrl") return;
    canvas_.push_clip({r.x, r.y, r.w, r.h});
    renderer_.draw(canvas_, world_, Draw::follow(world_, canvas_.width(), canvas_.height()),
                   [this](const std::string& name) { passes_.push_back(name); });
    draw_hud();
    canvas_.pop_clip();
  };
  if (!opt_.program.empty()) {
    std::string err;
    int n = gui_->load_start_scripts(opt_.program, err);
    if (log) log(n ? "start scripts: " + std::to_string(n) : err);
  }

  load_tile_sheet();
  std::string table, err;
  for (const auto& root : roots()) {
    if (!read_file(root + "/arrays.dat", table)) continue;
    if (!World::read_arrays_dat(table, tile_types_, err) && log) log(err);
    World::read_object_tables(table, object_tables_);
    break;
  }
}

std::vector<std::string> Program::roots() const {
  std::vector<std::string> out;
  if (!opt_.assets.empty()) out.push_back(opt_.assets);
  for (const auto& r : opt_.asset_roots)
    if (!r.empty()) out.push_back(r);
  return out;
}

bool Program::load_tile_sheet() {
  std::vector<std::uint8_t> bytes;
  std::string err;
  Draw::Image sheet;
  // 4.x and 5.x installs keep the sheet in levels/tiles/ (docs/assets.md);
  // a downloaded one lands in levels/images/downloads/.
  for (const auto& root : roots())
    for (const char* rel : {"/pics1.png", "/levels/pics1.png", "/levels/tiles/pics1.png",
                            "/levels/images/downloads/pics1.png"}) {
      if (Torque::Gui::read_file(root + rel, bytes, err) && Torque::Gui::decode_png(bytes, sheet, err)) {
        sheets_[""] = sheet;  // the default when no addtiledef matches
        renderer_.set_tile_sheet(std::move(sheet));
        return true;
      }
    }
  return false;
}

void Program::want_file(const std::string& name) {
  if (!safe_file_name(name)) return;
  if (!asked_.insert(lower_name(name)).second) return;
  session_.connection().send(23, name);  // PLI_WANTFILE
  if (log) log("asking for " + name);
}

void Program::ask_for_missing() {
  // The real 5.x clients ask with 23 for a file they do not have (the
  // lab's 5.12 asked for its fonts, steps2.wav and push.gani so,
  // graal-decompile lab-v5v6 proxy logs); the tile sheet is asked for the
  // same way when no folder has it (a rebuild choice: the logs do not show
  // how a fresh 5.12 install gets pics1.png).
  if (!renderer_.has_tile_sheet()) want_file("pics1.png");
  auto images = [this](const World::Player& p) {
    for (const std::string* n : {&p.head, &p.body, &p.sword_image, &p.shield_image})
      if (!n->empty() && n->find('.') != std::string::npos && !assets_->image(*n)) want_file(*n);
  };
  images(me_);
  for (const auto& [pid, o] : others_) images(o);
}

namespace {

bool is_login_name(const std::string& name) { return lower_name(name).rfind("login", 0) == 0; }

}  // namespace

std::string Program::package_dir(const std::string& server) {
  // The Login copy sits in updatepackages/; a game server's in a folder
  // named for it, a space as %032 (Lab%032Server, the 4.04r2 live run).
  // Other characters outside letters, digits, '-', '_' and '.' are written
  // the same way (rebuild reading).
  if (server.empty() || is_login_name(server)) return "updatepackages";
  std::string out = "updatepackages/";
  for (unsigned char c : server) {
    if (std::isalnum(c) || c == '-' || c == '_' || (c == '.' && out.back() != '.')) {
      out += static_cast<char>(c);
    } else {
      char buf[8];
      std::snprintf(buf, sizeof buf, "%%%03u", static_cast<unsigned>(c));
      out += buf;
    }
  }
  return out;
}

std::string Program::package_path(const std::string& server) const {
  return opt_.assets + "/" + package_dir(server) + "/basepackage.gupd";
}

void Program::ask_update_packages() {
  // basepackage.gupd twice: 47 with the CRC-32 of a copy cached before
  // this run, else 23 (a copy saved during the run is not checked).
  std::string body = "basepackage.gupd";
  int id = 23;
  if (!opt_.assets.empty()) {
    std::error_code ec;
    const std::string path = package_path(session_.server_name());
    auto when = std::filesystem::last_write_time(path, ec);
    std::string data;
    if (!ec && when < run_start_ && read_file(path, data)) {
      const auto crc = crc32(0L, reinterpret_cast<const Bytef*>(data.data()), static_cast<uInt>(data.size()));
      id = 47;
      body = Net::gint5(static_cast<uint64_t>(crc)) + body;
    }
  }
  asked_.insert("basepackage.gupd");
  for (int i = 0; i < 2; ++i) session_.connection().send(id, body);
  // bigmap.txt once per run, on the Login session only.
  if (is_login_name(session_.server_name())) want_file("bigmap.txt");
}

bool Program::wanted(const std::string& name) const {
  return opt_.download_files && safe_file_name(name) && asked_.count(lower_name(name)) != 0 &&
         refused_.count(lower_name(name)) == 0;
}

void Program::save_download(const std::string& name, const std::string& data) {
  // Only a file this program asked for is kept; anything else the server
  // sends is dropped.
  if (!wanted(name) || opt_.assets.empty()) return;
  if (data.size() > opt_.max_download) {
    if (log) log(name + " is too large to keep");
    refused_.insert(lower_name(name));
    return;
  }
  if (lower_name(name) == "basepackage.gupd") {
    // Kept in updatepackages/, and on a game server in its own folder too.
    std::vector<std::string> dirs{package_dir("")};
    if (!is_login_name(session_.server_name())) dirs.push_back(package_dir(session_.server_name()));
    for (const auto& d : dirs) {
      std::error_code ec;
      std::filesystem::create_directories(opt_.assets + "/" + d, ec);
      std::ofstream(opt_.assets + "/" + d + "/basepackage.gupd", std::ios::binary)
          .write(data.data(), static_cast<std::streamsize>(data.size()));
    }
    if (log) log("got basepackage.gupd (" + std::to_string(data.size()) + " bytes)");
    return;
  }
  std::string dir = opt_.assets + "/levels/images/downloads";
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  std::ofstream out(dir + "/" + name, std::ios::binary);
  if (!out) {
    if (log) log("could not save " + name);
    return;
  }
  out.write(data.data(), static_cast<std::streamsize>(data.size()));
  out.close();
  assets_->forget(name);
  if (lower_name(name) == "pics1.png") load_tile_sheet();
  if (log) log("got " + name + " (" + std::to_string(data.size()) + " bytes)");
}

void Program::draw_hud() {
  if (!profile_.hud_6x || world_.lobby) return;
  Draw::HudState s;
  s.half_hearts = me_.power;
  s.gralats = me_.rupees;
  s.bombs = me_.bombs;
  s.arrows = me_.arrows;
  s.ap = me_.ap;
  s.mp = me_.mp;
  s.glove_power = me_.glove_power;
  s.sword_power = me_.sword_power;
  s.sword_image = me_.sword_image;
  hud_->draw(canvas_, s);
  passes_.push_back("HUD");
}

Draw::Actor Program::actor_for(int id, const World::Player& p) {
  Draw::Actor a;
  a.x = p.x;
  a.y = p.y;
  a.chat = p.chat;
  a.gani = p.gani.empty() ? "idle" : p.gani;
  // replaceani from an offline level's script (idle -> human2_idle in 4.x).
  if (auto r = replace_ani_.find(lower_name(a.gani)); r != replace_ani_.end()) a.gani = r->second;
  a.dir = p.dir;
  a.head = p.head;
  a.body = p.body;
  a.sword = p.sword_image;
  a.shield = p.shield_image;
  for (size_t i = 1; i < a.attr.size(); ++i) a.attr[i] = p.attr[i];
  for (size_t i = 0; i < a.colors.size(); ++i) a.colors[i] = p.colors[i];
  a.carry = sprite_cell(World::carried_sprite(p.carry_sprite));
  // A gani plays from the tick it was set.
  auto& start = gani_start_[id];
  if (start.first != a.gani) start = {a.gani, frame_};
  a.ani_tick = frame_ - start.second;
  return a;
}

bool Program::action(std::string_view command, bool down) {
  // The 2D bindings (Graal_analysis torque/scripting.md): the arrows, A, S
  // (Space is doS2, a second sword key) and D. Q with no weapon toggles the
  // weapon state as D does (the 6.03r7 item-keys lab, world/actions.hpp);
  // with a weapon shown, D uses it and Q steps the selection (tick).
  static const struct {
    const char* name;
    unsigned move, item;
  } kBindings[] = {
      {"moveUp2D", 1u, 0}, {"moveLeft2D", 2u, 0}, {"moveDown2D", 4u, 0}, {"moveRight2D", 8u, 0},
      {"doA", 0, World::kKeyA}, {"doS", 0, World::kKeyS}, {"doS2", 0, World::kKeyS}, {"doD", 0, World::kKeyD},
      {"doQ", 0, World::kKeyD},
  };
  bool known = false;
  action_moves_ = action_items_ = 0;
  action_d_ = action_q_ = false;
  for (unsigned i = 0; i < sizeof kBindings / sizeof kBindings[0]; ++i) {
    if (command == kBindings[i].name) {
      known = true;
      action_held_ = down ? (action_held_ | (1u << i)) : (action_held_ & ~(1u << i));
    }
    if (action_held_ & (1u << i)) {
      action_moves_ |= kBindings[i].move;
      action_items_ |= kBindings[i].item;
      if (std::string_view(kBindings[i].name) == "doD") action_d_ = true;
      if (std::string_view(kBindings[i].name) == "doQ") action_q_ = true;
    }
  }
  return known;
}

Draw::Rect Program::sprite_cell(int sprite) const {
  int x, y, w, h;
  if (!World::sprite_rect(object_tables_, sprite, x, y, w, h)) return {0, 0, 0, 0};
  return {x, y, w, h};
}

void Program::say(const std::string& text) {
  me_.chat = text;
  if (props_sent_) session_.connection().send(2, Net::gchar(World::kCurChat) + Net::gstring(text));
}

std::string Program::window_title() const {
  // The real 6.03r7 Linux client shows the server name alone (frames lab,
  // 2026-11-13). Other rows: "Graal 5.12 - Lab Server", the rebuild's form.
  // Offline, the server name is "Offline" (the 2.x clients read
  // tiledefsOffline.txt for it: Graal_analysis client-internals/offline-tutorial-205.md).
  const std::string server = offline_ ? std::string("Offline") : session_.server_name();
  if (profile_.title_is_server) return server;
  return "Graal " + short_label(profile_.label) + " - " + server;
}

bool Program::load_offline_level(const std::string& name) {
  std::string data, err;
  std::vector<std::string> dirs;
  if (!offline_dir_.empty()) dirs.push_back(offline_dir_ + "/");
  if (!opt_.assets.empty()) dirs.insert(dirs.end(), {opt_.assets + "/levels/", opt_.assets + "/"});
  std::string path;
  for (const std::string& dir : dirs)
    if (read_file(dir + name, data)) {
      path = dir + name;
      break;
    }
  if (path.empty() && !opt_.assets.empty()) {
    path = find_below(opt_.assets + "/levels", name);
    if (path.empty() || !read_file(path, data)) {
      if (log) log("offline: no level " + name);
      return false;
    }
  }
  if (path.empty()) return false;
  Files::Level lv;
  if (!Files::read_level(data, lv, err)) {
    if (log) log(name + ": " + err);
    return false;
  }
  world_.level = std::move(lv);
  world_.have_level = true;
  level_name_ = name;
  me_.level = name;
  read_level_script();
  pick_tile_sheet();
  return true;
}

namespace {

// The arguments of each `command ` in a script, to ';', a line end or '}'.
std::vector<std::vector<std::string>> calls_of(const std::string& script, const std::string& command) {
  std::vector<std::vector<std::string>> out;
  const std::string low = lower_name(script), key = command + " ";
  for (size_t p = low.find(key); p != std::string::npos; p = low.find(key, p + key.size())) {
    if (p > 0 && (std::isalnum(static_cast<unsigned char>(low[p - 1])) || low[p - 1] == '_')) continue;
    size_t e = p + key.size();
    while (e < script.size() && script[e] != ';' && script[e] != '\n' && script[e] != '\r' && script[e] != '}') ++e;
    std::vector<std::string> args;
    std::stringstream in(script.substr(p + key.size(), e - p - key.size()));
    for (std::string a; std::getline(in, a, ',');) {
      a.erase(0, a.find_first_not_of(" \t"));
      a.erase(a.find_last_not_of(" \t") + 1);
      args.push_back(a);
    }
    out.push_back(std::move(args));
  }
  return out;
}

}  // namespace

void Program::read_level_script() {
  // Offline there is no server to run the level's NPCs, and no GS1 engine
  // here yet: like the Pascal 4.04r2 rebuild's tile defs, the lines the
  // offline tutorial's `playerenters` block sets up are read wherever they
  // stand, without their condition (rebuild reading). That block sets the
  // look (`setplayerprop` #1 sword, #2 shield, #3 head, #8 body, #Pn
  // attribute n: npc-library/gs1-command-reference-205.md), the tile sheet
  // (`addtiledef image,prefix`), the gani names (`replaceani old,new`) and
  // the first gani (`setani`).
  for (const auto& npc : world_.level.npcs) {
    for (const auto& a : calls_of(npc.script, "addtiledef")) {
      if (a.size() < 2 || a[0].empty() || a[0].find("..") != std::string::npos) continue;
      std::pair<std::string, std::string> def{lower_name(a[1]), a[0]};
      tiledefs_.erase(std::remove(tiledefs_.begin(), tiledefs_.end(), def), tiledefs_.end());
      tiledefs_.insert(tiledefs_.begin(), def);
    }
    for (const auto& a : calls_of(npc.script, "replaceani"))
      if (a.size() >= 2 && !a[0].empty()) replace_ani_[lower_name(a[0])] = a[1];
    for (const auto& a : calls_of(npc.script, "setplayerprop")) {
      if (a.size() < 2 || a[0].size() < 2 || a[0][0] != '#') continue;
      const std::string code = a[0].substr(1);
      if (code == "1") me_.sword_image = a[1];
      else if (code == "2") me_.shield_image = a[1];
      else if (code == "3") me_.head = a[1];
      else if (code == "8") me_.body = a[1];
      else if ((code[0] == 'P' || code[0] == 'p') && code.size() > 1) {
        const int n = std::atoi(code.c_str() + 1);
        if (n >= 1 && static_cast<size_t>(n) < me_.attr.size()) me_.attr[static_cast<size_t>(n)] = a[1];
      }
    }
    for (const auto& a : calls_of(npc.script, "setani"))
      if (!a.empty() && !a[0].empty()) me_.gani = a[0];
  }
}

void Program::pick_tile_sheet() {
  // An addtiledef image for every level whose name starts with its prefix.
  std::string image;
  const std::string name = lower_name(level_name_);
  for (const auto& [prefix, img] : tiledefs_)
    if (name.compare(0, prefix.size(), prefix) == 0) {
      image = img;
      break;
    }
  auto it = sheets_.find(image);
  if (it == sheets_.end() && !image.empty() && !opt_.assets.empty()) {
    std::vector<std::uint8_t> bytes;
    std::string err;
    Draw::Image sheet;
    std::vector<std::string> dirs;
    if (!offline_dir_.empty()) dirs.push_back(offline_dir_);
    for (const char* sub : {"/levels/tiles", "/levels", "", "/levels/images", "/images"}) dirs.push_back(opt_.assets + sub);
    for (const auto& d : dirs)
      if (Torque::Gui::read_file(d + "/" + image, bytes, err) && Torque::Gui::decode_png(bytes, sheet, err)) {
        it = sheets_.emplace(image, std::move(sheet)).first;
        break;
      }
    if (it == sheets_.end() && log) log("offline: no tile sheet " + image);
  }
  if (it == sheets_.end()) it = sheets_.find("");
  if (it != sheets_.end()) renderer_.set_tile_sheet(it->second);
}

bool Program::start_offline(const std::string& file, double x, double y, const std::string& part) {
  offline_ = true;
  have_gmap_ = false;
  offline_dir_.clear();
  tiledefs_.clear();
  replace_ani_.clear();
  world_.lobby = false;
  others_.clear();
  me_.x = x;
  me_.y = y;
  window_.set_title(window_title());
  const bool is_gmap = lower_name(file).size() > 5 && lower_name(file).compare(file.size() - 5, 5, ".gmap") == 0;
  walker_.clamp = true;
  if (!is_gmap) return load_offline_level(file);
  std::string data, path, err;
  if (!opt_.assets.empty()) {
    for (const std::string& dir : {opt_.assets + "/levels/", opt_.assets + "/"})
      if (read_file(dir + file, data)) {
        path = dir + file;
        break;
      }
    if (path.empty()) {
      path = find_below(opt_.assets + "/levels", file);
      if (!path.empty() && !read_file(path, data)) path.clear();
    }
  }
  if (path.empty()) {
    if (log) log("offline: no map " + file);
    return false;
  }
  if (!Files::read_gmap(data, gmap_, err)) {
    if (log) log(file + ": " + err);
    return false;
  }
  have_gmap_ = true;
  walker_.clamp = false;  // the gmap's parts hold the edges
  offline_dir_ = std::filesystem::path(path).parent_path().string();
  // The 2.x Training starts in the centre cell (b-2 of 3 x 3).
  std::string first = part.empty() ? gmap_.at(gmap_.width / 2, gmap_.height / 2) : part;
  return !first.empty() && load_offline_level(first);
}

void Program::cross_gmap_edge() {
  int gx = 0, gy = 0;
  if (!have_gmap_ || !gmap_.find(level_name_, gx, gy)) return;
  // The gmap is one board in global tiles (local + 64 * cell): a step to
  // x 64 is x 0 of the next part, a step below 0 is x 63.5 of the one
  // before (the 2.22 lab crossing, Graal_analysis
  // client-internals/feature-specs/06-gmap-overworld.md). With no part
  // beyond, the board's edge holds, as on a single level.
  const double side = Files::kBoardSide, edge = side - 2.0;
  auto wrap = [&](double& v, int& cell, bool horizontal) {
    int d = v < 0 ? -1 : v >= side ? 1 : 0;
    const std::string next = d ? (horizontal ? gmap_.at(gx + d, gy) : gmap_.at(gx, gy + d)) : std::string();
    if (d && !next.empty() && load_offline_level(next)) {
      v -= d * side;
      cell += d;
      return;
    }
    const bool open_after = !(horizontal ? gmap_.at(gx + 1, gy) : gmap_.at(gx, gy + 1)).empty();
    v = std::max(0.0, std::min(v, open_after ? side - 0.5 : edge));
  };
  wrap(me_.x, gx, true);
  wrap(me_.y, gy, false);
}

void Program::list_player(int id, const World::Player& p, int flags) {
  ListRow row;
  row.id = id;
  row.nick = (flags & kListSelf) ? std::string() : p.nickname;  // the lab's 5.12 sent its own row with no nick
  row.head = p.head;
  std::string account = p.account, level = p.level;
  if (flags & kListSelf) {  // what the client knows of itself when the server has not said
    if (account.empty()) account = opt_.account;
    if (level.empty()) level = level_name_;
  }
  row.props = "account=" + account + ",level=" + level + ",communityname=" + p.community + ",attr[1]=" + p.attr[1];
  row.flags = flags;
  auto it = listed_.find(id);
  if (it != listed_.end() && it->second == row) return;
  listed_[id] = row;
  if (list_update) list_update(row);
}

void Program::unlist(int id) {
  listed_.erase(id);
  if (list_delete) list_delete(id);
}

void Program::unlist_all() {
  // Others first, then the client's own row, which the lab's 5.12 deleted
  // on every disconnect.
  std::vector<int> ids;
  for (const auto& [id, row] : listed_)
    if (!(row.flags & kListSelf)) ids.push_back(id);
  for (int id : ids) unlist(id);
  listed_.erase(self_list_id_);
  if (list_delete) list_delete(self_list_id_);
  everyone_.clear();
}

bool Program::start() {
  // The lab's 5.12 deleted its own row before the first connect.
  if (list_delete) list_delete(self_list_id_);
  bool ok = session_.start(opt_.host, opt_.port, opt_.account, opt_.password, opt_.language, opt_.server_name);
  window_.set_title(window_title());
  return ok;
}

void Program::load_local_level(const std::string& name) {
  if (opt_.assets.empty()) return;
  std::string data, err;
  for (const std::string& dir : {opt_.assets + "/levels/", opt_.assets + "/"}) {
    if (!read_file(dir + name, data)) continue;
    Files::Level lv;
    if (Files::read_level(data, lv, err)) {
      world_.level = std::move(lv);
      world_.have_level = true;
    } else if (log) {
      log(name + ": " + err);
    }
    return;
  }
}

void Program::on_message(int id, std::string_view body) {
  // The script cache is per server host (weblevels/<host>).
  if (!opt_.assets.empty() && cache_server_ != session_.server_host()) {
    cache_server_ = session_.server_host();
    scripts_.set_cache_dir(opt_.assets + "/weblevels/" + cache_server_);
  }
  // The weapon list; the scripts also see 33, 34 and 194.
  switch (id) {
    case 33: {  // PLO_NPCWEAPONADD: str name, then the NPC props (0: image)
      Net::Reader wr(body);
      std::string name = wr.gstring(), image;
      if (!wr.ok() || name.empty()) {
        name = std::string(body);
      } else if (wr.gchar() == 0 && wr.ok()) {
        image = wr.gstring();
        if (!wr.ok()) image.clear();
      }
      weapons_.add(name, image);
      break;
    }
    case 34:  // PLO_NPCWEAPONDEL: the name
      weapons_.remove(std::string(body));
      break;
    case 43: {  // PLO_DEFAULTWEAPON: the item index
      Net::Reader wr(body);
      int item = static_cast<int>(wr.gchar());
      if (wr.ok()) weapons_.add_default(item);
      return;
    }
    case 40:  // PLO_HURTPLAYER: s attacker, c dx, c dy, c power
      send_packets(health_.on_hurt_player(me_, body, others_));
      return;
    case 194:  // PLO_RESETCLIENT: the weapon list follows
      weapons_.clear();
      scripts_.clear_weapons();
      return;
    default:
      break;
  }
  if (combat_.on_message(id, body)) return;
  if (scripts_.on_message(id, body)) return;
  Net::Reader r(body);
  switch (id) {
    case 6:  // PLO_LEVELNAME
      // The same name again after its board (a Seihai gserver sends it
      // once more with the level's props) keeps the board.
      if (world_.have_level && body == level_name_) break;
      level_name_ = std::string(body);
      world_.level = Files::Level{};
      world_.have_level = false;
      item_keys_.new_level();
      effects_.clear();
      combat_.clear();
      entry_x_ = me_.x;  // where a dead player comes back
      entry_y_ = me_.y;
      load_local_level(level_name_);
      break;
    case 7: {  // PLO_BOARDMODIFY: x, y, w, h, then the tiles row by row
      int x = static_cast<int>(r.gchar()), y = static_cast<int>(r.gchar());
      int w = static_cast<int>(r.gchar()), h = static_cast<int>(r.gchar());
      if (world_.level.layers.empty() || !r.ok()) break;
      for (int ty = y; ty < y + h; ++ty)
        for (int tx = x; tx < x + w; ++tx) {
          unsigned t = r.gshort();
          if (!r.ok()) break;
          if (tx >= 0 && ty >= 0 && tx < Files::kBoardSide && ty < Files::kBoardSide)
            world_.level.layers[0][static_cast<size_t>(tx + ty * Files::kBoardSide)] = static_cast<uint16_t>(t);
        }
      break;
    }
    case 101: {  // PLO_BOARDPACKET
      std::string err;
      if (Files::apply_board_packet(body, world_.level, err))
        world_.have_level = true;
      else if (log)
        log(err);
      break;
    }
    case 1: {  // PLO_LEVELLINK: "dest x y w h newx newy"
      std::istringstream in{std::string(body)};
      std::vector<std::string> tok;
      for (std::string t; in >> t;) tok.push_back(t);
      if (tok.size() >= 7) {
        Files::Link k;
        size_t n = tok.size();
        for (size_t i = 0; i + 6 < n; ++i) k.dest += (i ? " " : "") + tok[i];
        k.x = std::atoi(tok[n - 6].c_str());
        k.y = std::atoi(tok[n - 5].c_str());
        k.w = std::atoi(tok[n - 4].c_str());
        k.h = std::atoi(tok[n - 3].c_str());
        k.newx = tok[n - 2];
        k.newy = tok[n - 1];
        world_.level.links.push_back(k);
      }
      break;
    }
    case 4: {  // PLO_LEVELCHEST: x, y, item, sign
      Files::Chest c;
      c.x = static_cast<int>(r.gchar());
      c.y = static_cast<int>(r.gchar());
      c.item = static_cast<int>(r.gchar());
      c.sign = static_cast<int>(r.gchar());
      if (r.ok()) world_.level.chests.push_back(c);
      break;
    }
    case 9: {  // PLO_PLAYERPROPS
      World::apply_props(r, me_, false, profile_.last_prop);
      if (!props_sent_) {
        // Logged in: the client's own props, then only what moves.
        session_.connection().send(2, World::initial_props(me_, profile_.platform));
        mover_.reset(me_);
        props_sent_ = true;
        if (logged_in) logged_in();
      }
      if (me_.id > 0 && me_.id != self_list_id_) {
        listed_.erase(self_list_id_);
        self_list_id_ = me_.id;
      }
      list_player(self_list_id_, me_, kListSelf);
      break;
    }
    case 8: {  // PLO_OTHERPLPROPS: GSHORT id, then props
      if (body.size() < 2) break;
      int pid = static_cast<int>(r.gshort());
      World::Player& o = others_[pid];
      o.id = pid;
      World::apply_props(r, o, true, profile_.last_prop);
      if (o.gone) {
        others_.erase(pid);
        gani_start_.erase(pid);
      }
      // The player list keeps everyone the server names, on any level,
      // until the player leaves the server.
      Net::Reader all(body.substr(2));
      World::Player& e = everyone_[pid];
      e.id = pid;
      World::apply_props(all, e, true, profile_.last_prop);
      if (e.disconnected) {
        everyone_.erase(pid);
        if (listed_.count(pid)) unlist(pid);
      } else {
        list_player(pid, e, kListServer);
      }
      break;
    }
    case 14:    // PLO_PLAYERWARP: c x*2, c y*2, level
    case 49: {  // PLO_PLAYERWARP2: c x*2, c y*2, c z, c gmap x, c gmap y, level
      me_.x = r.gchar() / 2.0;
      me_.y = r.gchar() / 2.0;
      if (id == 49) {
        r.gchar();
        me_.gmap_x = static_cast<int>(r.gchar());
        me_.gmap_y = static_cast<int>(r.gchar());
      }
      me_.level = r.rest();
      others_.clear();
      mover_.reset(me_);
      break;
    }
    case 102: {  // PLO_FILE: GINT5 mod time, GCHAR name length, name, data
      r.gint5();
      size_t n = r.gchar();
      std::string rest = r.rest();
      if (!r.ok() || rest.size() < n) break;
      std::string name = rest.substr(0, n), data = rest.substr(n);
      if (auto it = large_.find(name); it != large_.end()) {
        if (it->second.size() + data.size() > opt_.max_download) {
          // Later chunks of this file are dropped too: the name is refused,
          // so they are not saved as if each were a whole file.
          if (log) log(name + " is too large to keep");
          refused_.insert(lower_name(name));
          large_.erase(it);
        } else {
          it->second += data;
        }
      } else {
        save_download(name, data);
      }
      break;
    }
    case 68:  // PLO_LARGEFILESTART: name; 102 chunks follow until 69
      if (wanted(std::string(body))) large_[std::string(body)].clear();
      break;
    case 69:  // PLO_LARGEFILEEND: name
      if (auto it = large_.find(std::string(body)); it != large_.end()) {
        std::string data = std::move(it->second);
        large_.erase(it);
        save_download(std::string(body), data);
      }
      break;
    case 30:  // PLO_FILESENDFAILED: name (it stays asked, so it is not asked again)
      if (log) log("the server has no " + std::string(body));
      break;
    case 178:  // the session follows the warp; the title follows the name
      props_sent_ = false;
      others_.clear();
      unlist_all();  // the next server names its own players
      break;
    default:
      break;
  }
}

bool Program::tick() {
  if (!offline_) session_.tick();
  if (!offline_ && session_.logins() != logins_seen_) {
    logins_seen_ = session_.logins();
    if (logins_seen_ > 0 && profile_.update_packages && opt_.download_files) ask_update_packages();
  }
  world_.lobby = !offline_ && session_.lobby_mode();
  if (window_.title() != window_title()) window_.set_title(window_title());

  for (Draw::Key k = window_.poll_key(); k != Draw::Key::NoKey; k = window_.poll_key()) {
    if (k == Draw::Key::Escape && item_list_open_) {
      item_list_open_ = false;  // Esc closes the item list
      continue;
    }
    if (k == Draw::Key::Close || (k == Draw::Key::Escape && !gui_->has_content())) quit_ = true;
  }
  for (Draw::InputEvent e; window_.poll_input(e);) {
    if (gui_->has_content())
      gui_->input(e);
    else if (item_list_open_)
      item_list_input(e);
    else if (e.type == Draw::InputEvent::KeyDown)
      scripts_.key_pressed(e.key, e.ch);
  }
  // Walking: half a tile per held arrow per tick, against the walls.
  if (!world_.lobby) {
    auto& p = me_;
    unsigned keys = (window_.held(Draw::Key::Up) ? 1u : 0u) | (window_.held(Draw::Key::Left) ? 2u : 0u) |
                    (window_.held(Draw::Key::Down) ? 4u : 0u) | (window_.held(Draw::Key::Right) ? 8u : 0u) |
                    action_moves_;
    // D, Q and Tab toggle the same status bit while no weapon is shown
    // (item-keys lab). With one, D uses the selected weapon and Q or Tab
    // opens and closes the item list.
    const bool d_held = window_.held(Draw::Key::D) || action_d_;
    const bool q_held = window_.held(Draw::Key::Q) || window_.held(Draw::Key::Tab) || action_q_;
    const bool armed = weapons_.any_shown();
    unsigned items = (window_.held(Draw::Key::A) ? World::kKeyA : 0u) |
                     (window_.held(Draw::Key::S) ? World::kKeyS : 0u) |
                     (!armed && (d_held || q_held) ? World::kKeyD : 0u) |
                     (action_items_ & (World::kKeyA | World::kKeyS));
    const bool q_pressed = armed && q_held && !weapon_keys_[1];
    const bool d_pressed = armed && d_held && !weapon_keys_[0];
    weapon_keys_[0] = armed && d_held;
    weapon_keys_[1] = armed && q_held;
    if (!armed) item_list_open_ = false;
    if (item_list_open_) {
      // The list holds the game: the item key closes it, so do A, S, D.
      if (q_pressed || d_pressed || (items & (World::kKeyA | World::kKeyS))) item_list_open_ = false;
      keys = 0;
      items = 0;
    } else if (q_pressed) {
      item_list_open_ = true;
      keys = 0;
      items = 0;
    }
    // Dead: nothing but an arrow key, which brings the player back where
    // the level was entered. Hurt: the knockback holds the walk.
    if (health_.dead()) {
      if (keys) send_packets(health_.respawn(p, entry_x_, entry_y_, level_name_));
      keys = 0;
      items = 0;
    } else if (health_.hurting()) {
      keys = 0;
      items &= ~World::kKeyD;
    }
    if (d_pressed && !item_list_open_ && !health_.dead() && !item_keys_.busy() && !item_keys_.carrying()) fire_weapon();
    // The item keys first (sword, lift, throw, grab); a swing or a lift
    // holds the walk.
    int carried = p.carry_sprite;
    auto sent = item_keys_.tick(p, items, keys, world_.level, object_tables_, tile_types_);
    for (const auto& pk : sent) {
      // What the keys did, for the effects: a throw, or a bush cut.
      if (pk.id == 11)
        effects_.throw_object(carried, static_cast<int>(std::lround(p.x * Draw::kTile)),
                              static_cast<int>(std::lround(p.y * Draw::kTile)), p.dir);
      if (pk.id == 1 && p.gani == "sword" && pk.body.size() >= 2) {
        Net::Reader br(pk.body);
        int bx = static_cast<int>(br.gchar()), by = static_cast<int>(br.gchar());
        effects_.cut_bush(bx, by);
      }
    }
    if (props_sent_) {
      for (const auto& pk : sent) session_.connection().send(pk.id, pk.body);
      if (!sent.empty()) mover_.gani_sent(p);
    }
    std::string action =
        walker_.tick(p, item_keys_.busy() ? 0u : keys, world_.level, tile_types_, item_keys_.carrying());
    if (offline_) cross_gmap_edge();
    for (const auto& pk : item_keys_.touch_chests(p, item_keys_.busy() ? 0u : keys, world_.level)) {
      Net::Reader cr(pk.body);
      int cx = static_cast<int>(cr.gchar()), cy = static_cast<int>(cr.gchar());
      for (const auto& ch : world_.level.chests)
        if (ch.x == cx && ch.y == cy) effects_.chest_item(ch.item, cx, cy);
      if (props_sent_) session_.connection().send(pk.id, pk.body);
    }
    if (!action.empty() && props_sent_) session_.connection().send(38, action);
    if (props_sent_) {
      std::string moved = mover_.diff(p);
      if (!moved.empty()) session_.connection().send(2, moved);
    }
  }
  // The thrown objects, pieces, leaves and chest items; a chest item's
  // time out sends its ITEMDEL.
  for (const auto& pk : effects_.tick())
    if (props_sent_) session_.connection().send(pk.id, pk.body);
  // Bombs burn, blasts age, shots fly; an own bomb's explosion and the
  // board it changed go out.
  if (!world_.lobby) {
    send_packets(combat_.tick(world_.level, object_tables_, tile_types_));
    // What hurts this player: blasts, other players' shots and swings.
    std::vector<World::Packet> back;
    for (const auto& h : combat_.hits_on(me_, object_tables_, back)) send_packets(health_.hit(me_, h.hearts, h.kx, h.ky));
    send_packets(back);
    send_packets(health_.check_swords(me_, others_));
    health_.tick(me_, world_.level, tile_types_);
  }
  send_counts();
  if (opt_.download_files && props_sent_ && frame_ % 10 == 0) ask_for_missing();
  ++frame_;
  world_.player = actor_for(-1, me_);
  // Our own load shows from the press on, before its carry sprite is sent.
  if (item_keys_.carrying()) {
    world_.player.carry = sprite_cell(World::carried_sprite(item_keys_.carry_sprite()));
    world_.player.lift_tick = item_keys_.lifting() ? world_.player.ani_tick : -1;
  }
  world_.effects.clear();
  for (const auto& pc : effects_.pieces()) {
    Draw::Rect r = sprite_cell(pc.sprite);
    if (r.width > 0) world_.effects.push_back({r, pc.x, pc.y, {}});
  }
  combat_effects();
  world_.others.clear();
  for (const auto& [pid, o] : others_) {
    if (!o.level.empty() && !me_.level.empty() && o.level != me_.level) continue;
    world_.others.push_back(actor_for(pid, o));
  }

  sync_player_in();
  scripts_.tick();
  sync_player_out();
  gui_->pick_content();
  gui_->screen().advance(0.05);  // the show-images' emitters, one 50 ms tick
  passes_.clear();
  if (gui_->has_content()) {
    // RenderGUI: the content and dialogs; the world shows in the playfield.
    canvas_.clear({0, 0, 0, 255});
    gs2::gui::drawScreen(gui_->screen(), *painter_);
    painter_->reset_clip();
    passes_.push_back("RenderGUI");
  } else {
    renderer_.draw(canvas_, world_, Draw::follow(world_, canvas_.width(), canvas_.height()),
                   [this](const std::string& name) { passes_.push_back(name); });
    draw_hud();
    draw_item_list();
  }
  window_.present(canvas_.surface());
  return !quit_;
}

// ------------------------------------------------------------- weapons

void Program::send_packets(const std::vector<World::Packet>& out) {
  if (!props_sent_) return;
  for (const auto& pk : out) session_.connection().send(pk.id, pk.body);
}

void Program::send_counts() {
  // Rebuild reading: the client tells the server its new counts after a
  // bomb or an arrow (props 4 and 5), as the server keeps them.
  if (!props_sent_) {
    sent_arrows_ = me_.arrows;
    sent_bombs_ = me_.bombs;
    return;
  }
  std::string props;
  if (me_.arrows != sent_arrows_ && sent_arrows_ >= 0)
    props += Net::gchar(World::kArrows) + Net::gchar(static_cast<unsigned>(std::clamp(me_.arrows, 0, 99)));
  if (me_.bombs != sent_bombs_ && sent_bombs_ >= 0)
    props += Net::gchar(World::kBombs) + Net::gchar(static_cast<unsigned>(std::clamp(me_.bombs, 0, 99)));
  sent_arrows_ = me_.arrows;
  sent_bombs_ = me_.bombs;
  if (!props.empty()) session_.connection().send(2, props);
}

void Program::fire_weapon() {
  const World::Weapon* w = weapons_.selected();
  if (!w || World::hidden_weapon(w->name)) return;
  // A server weapon with a GS2 script: onWeaponFired.
  if (scripts_.fire(w->name)) return;
  switch (w->item) {
    case 8: send_packets(combat_.lay_bomb(me_, 1)); break;
    case 12: send_packets(combat_.lay_bomb(me_, 2)); break;
    case 23: send_packets(combat_.lay_bomb(me_, 3)); break;
    case 7: send_packets(combat_.shoot(me_, 0)); break;
    case 20: send_packets(combat_.shoot(me_, 1)); break;
    case 21: send_packets(combat_.shoot(me_, 2)); break;
    case 22: send_packets(combat_.shoot(me_, 3)); break;
    default: break;
  }
  send_counts();
}

void Program::register_weapon_commands() {
  // The GS1 names the built-in weapons' scripts call, kept in GS2
  // (Graal_analysis npc-library/gs1-reference-205.md): putbomb power, x, y;
  // shootarrow dir; shootfireball, shootfireblast and shootnuke dir. That the
  // 6.x command run has these exact names is a reading; the run is not
  // copied out in client-internals/gs2-builtins-6113.md.
  gs2::Machine& m = scripts_.machine();
  m.addCommand("putbomb", "nnn", [this](gs2::Machine& mm, gs2::Var&, std::vector<gs2::Value>& a) {
    send_packets(combat_.put_bomb(static_cast<int>(mm.toNumber(a[0])), mm.toNumber(a[1]), mm.toNumber(a[2])));
    return gs2::Value::number(0);
  });
  static const char* kShots[4] = {"shootarrow", "shootfireball", "shootfireblast", "shootnuke"};
  for (int kind = 0; kind < 4; ++kind)
    m.addCommand(kShots[kind], "n", [this, kind](gs2::Machine& mm, gs2::Var&, std::vector<gs2::Value>& a) {
      World::Player p = me_;
      p.dir = static_cast<int>(mm.toNumber(a[0])) & 3;
      p.arrows = 1;  // a script's shot takes no arrow
      send_packets(combat_.shoot(p, kind));
      return gs2::Value::number(0);
    });
}

void Program::sync_player_in() {
  gs2::VarPtr pl = scripts_.player();
  auto num = [&](const char* k, double v) { pl->childOrCreate(k)->setNumber(v); };
  auto str = [&](const char* k, const std::string& v) { pl->childOrCreate(k)->setString(v); };
  num("x", me_.x);
  num("y", me_.y);
  num("dir", me_.dir);
  num("bombs", me_.bombs);
  num("darts", me_.arrows);
  num("rupees", me_.rupees);
  num("hearts", me_.power / 2.0);
  num("fullhearts", me_.max_power);
  num("id", me_.id);
  str("account", me_.account);
  str("nick", me_.nickname);
  str("ani", me_.gani);
  str("level", me_.level);
  script_seen_ = {me_.x, me_.y, me_.dir, me_.bombs, me_.arrows};
}

void Program::sync_player_out() {
  // What a script set on `player` goes back to the player; the walk diff
  // and send_counts send it.
  gs2::VarPtr pl = scripts_.player();
  auto num = [&](const char* k) {
    gs2::VarPtr c = pl->child(k);
    return c ? c->number() : 0.0;
  };
  if (num("x") != script_seen_.x) me_.x = num("x");
  if (num("y") != script_seen_.y) me_.y = num("y");
  if (static_cast<int>(num("dir")) != script_seen_.dir) me_.dir = static_cast<int>(num("dir")) & 3;
  if (static_cast<int>(num("bombs")) != script_seen_.bombs) me_.bombs = std::clamp(static_cast<int>(num("bombs")), 0, 99);
  if (static_cast<int>(num("darts")) != script_seen_.arrows) me_.arrows = std::clamp(static_cast<int>(num("darts")), 0, 99);
  send_counts();
}

void Program::combat_effects() {
  // Bombs and blasts from bomb1.png, as the 2.x rebuilds draw them: a
  // 32 x 32 bomb per power (blue, white, red), flashing in its last 15
  // ticks; a blast's vertical and horizontal arms, fat to thin as it ages.
  // Shots are list 24 sprites on sprites.png.
  for (const auto& b : combat_.bombs()) {
    if (b.fuse < 15 && (b.fuse / 2) % 2 == 1) continue;
    world_.effects.push_back({{32 * ((b.power - 1) % 3), 0, 32, 32},
                              static_cast<int>(std::lround(b.x * Draw::kTile)),
                              static_cast<int>(std::lround(b.y * Draw::kTile)), "bomb1.png"});
  }
  for (const auto& b : combat_.blasts()) {
    int stage = std::min(3, b.age / 3);
    int cx = static_cast<int>(std::lround((b.x + 1) * Draw::kTile));
    int cy = static_cast<int>(std::lround((b.y + 1) * Draw::kTile));
    world_.effects.push_back({{32 * stage, 32, 32, 160}, cx - 16, cy - 80, "bomb1.png"});
    world_.effects.push_back({{0, 192 + 32 * stage, 128, 32}, cx - 64, cy - 16, "bomb1.png"});
  }
  for (const auto& sh : combat_.shots()) {
    Draw::Rect r = sprite_cell(sh.sprite);
    if (r.width > 0)
      world_.effects.push_back({r, static_cast<int>(std::lround(sh.x * Draw::kTile)),
                                static_cast<int>(std::lround(sh.y * Draw::kTile)), {}});
  }
}

// ----------------------------------------------------------- item list

std::vector<World::ItemCell> Program::item_cells() const {
  return World::layout_items(
      weapons_, canvas_.width(), canvas_.height(),
      [this](const std::string& name) -> std::pair<int, int> {
        const Draw::Image* img = assets_ ? assets_->image(name) : nullptr;
        return img ? std::pair<int, int>{img->width, img->height} : std::pair<int, int>{0, 0};
      },
      [](const std::string& text) { return Draw::ui_text_width(text, false); });
}

void Program::item_list_input(const Draw::InputEvent& e) {
  if (e.type != Draw::InputEvent::KeyDown) return;
  static const char* kArrows[4] = {"up", "left", "down", "right"};
  for (int d = 0; d < 4; ++d)
    if (e.key == kArrows[d]) {
      int to = World::move_in_items(item_cells(), weapons_.selected_index(), d);
      if (to >= 0) weapons_.select(to);
      return;
    }
  if (e.key == "delete") {
    const World::Weapon* w = weapons_.selected();
    if (!w || World::hidden_weapon(w->name)) return;
    std::string name = w->name;
    weapons_.remove(name);
    if (props_sent_) session_.connection().send(29, name);  // PLI_NPCWEAPONDEL
    weapons_.select(weapons_.selected_index());
    return;
  }
  if (e.key == "escape") item_list_open_ = false;
}

void Program::draw_item_list() {
  if (!item_list_open_) return;
  const int w = canvas_.width(), h = canvas_.height();
  Draw::Rect win{World::kItemWindowLeft, World::kItemWindowTop, w - World::kItemWindowMargin - World::kItemWindowLeft,
                 h - World::kItemWindowMargin - World::kItemWindowTop};
  // The window's own colours were not read; a dark panel with a light frame.
  canvas_.fill_rect(win, {0, 0, 64, 200});
  canvas_.frame_rect(win, {255, 255, 255, 255});
  for (const auto& c : item_cells()) {
    const World::Weapon& wp = weapons_.list()[static_cast<size_t>(c.index)];
    if (c.index == weapons_.selected_index()) canvas_.fill_rect({c.x, c.y, c.w, c.h}, {255, 212, 128, 255});
    const Draw::Image* img = wp.image.empty() ? nullptr : assets_->image(wp.image);
    int ix = c.x + (c.w - c.image_w) / 2, iy = c.y + 5;
    if (img)
      canvas_.blit(*img, ix, iy);
    else
      canvas_.frame_rect({ix, iy, c.image_w, c.image_h}, {160, 160, 160, 255});
    Draw::ui_draw_text(canvas_, c.x + (c.w - c.label_w) / 2, iy + c.image_h + 5, wp.name, {255, 255, 255, 255}, false);
  }
  passes_.push_back("ItemList");
}

}  // namespace Quattro::Shell
