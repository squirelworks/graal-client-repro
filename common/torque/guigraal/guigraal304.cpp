// GuiGraalCtrl for 3.04. Each method body follows the native side read in
// Graal_analysis torque/304-adventure.md, 304-net.md and 304-audio-ui.md;
// README.md says which parts are observed and which are rebuild policy.

#include "guigraal304.hpp"

#include <cmath>

namespace Torque {
namespace {

const char* kClass = "GuiGraalCtrl";

bool on(const std::string& v) { return parse_float(v) != 0; }

std::vector<std::string> split_tabs(const std::string& text) {
  std::vector<std::string> out;
  std::size_t start = 0;
  for (;;) {
    const std::size_t tab = text.find('\t', start);
    out.push_back(text.substr(start, tab == std::string::npos ? std::string::npos : tab - start));
    if (tab == std::string::npos) return out;
    start = tab + 1;
  }
}

// Row columns: name, players, then the detail fields, host and port last
// (fields 0, 6 and 7 are observed; 1 to 5 are rebuild policy).
std::string row_text(const ListServerEntry& e) {
  const int order[8] = {0, 5, 1, 2, 3, 4, 6, 7};
  std::string text;
  for (int i = 0; i < 8; ++i) text += (i ? "\t" : "") + e.fields[order[i]];
  return text;
}

} // namespace

int server_category_304(const std::string& name) {
  if (name.size() < 2 || name[1] != ' ') return 2;
  switch (name[0]) {
    case 'P': return 0;
    case '3': return 1;
    case 'H': return 3;
    case 'U': return -1;
    default: return 2;
  }
}

std::string server_name_304(const std::string& name) {
  return name.size() >= 2 && name[1] == ' ' ? name.substr(2) : name;
}

const std::vector<std::string>& GuiGraal304::method_names() {
  static const std::vector<std::string> names = {
      "moveUp", "moveLeft", "moveDown", "moveRight", "doA", "doS", "doD", "doQ", "doP", "doM",
      "doMicro", "setChat", "setPassWord", "openServerList", "selectServer", "selectServerCategory",
      "startOfflineMode", "connectToSelectedServer", "serverDirectConnect", "privateMessageSend",
      "playerListOpenPlayer", "playerListProfile", "updateLoadLevelFields", "loadLevel",
      "updatePlayerProfile", "updatePlayerMuted", "updateMidiVolume", "updateMp3Volume",
      "updateRadioVolume", "updateMicroActivationLevel", "updateGraalOptions"};
  return names;
}

GuiGraal304::GuiGraal304(Engine& engine, std::unique_ptr<Game304> game)
    : engine_(engine), game_(std::move(game)) {
  game_->on_log = [this](const std::string& line) { engine_.trace.push_back("game: " + line); };
  auto previous = engine_.on_set_content;
  engine_.on_set_content = [this, previous](SimObject* canvas, SimObject* content) {
    if (previous) previous(canvas, content);
    check_activated();
  };
  register_methods();
}

void GuiGraal304::echo(const std::string& line) { engine_.call_function("echo", {line}); }

void GuiGraal304::trace_not_yet(const Args& a) {
  std::string line = std::string(kClass) + "::" + a[0] + "(";
  for (std::size_t i = 2; i < a.size(); ++i) line += (i > 2 ? ", " : "") + a[i];
  engine_.trace.push_back(line + "): not in the rebuilt 2D game yet");
}

std::string GuiGraal304::pref(const std::string& name) const {
  return engine_.global("$pref::Graal::" + name).str();
}

void GuiGraal304::set_content(const std::string& control) {
  if (SimObject* canvas = engine_.find_object("Canvas"))
    engine_.call_method(canvas, "setContent", {control});
}

void GuiGraal304::message_box(const std::string& title, const std::string& text) {
  engine_.call_function("MessageBoxOK", {title, text});
}

// The first wake of the control logs this line (304-adventure.md).
void GuiGraal304::check_activated() {
  if (activated_) return;
  SimObject* ctrl = engine_.find_object("Adventure");
  if (!ctrl || !ctrl->awake) return;
  activated_ = true;
  echo("Graal activated!");
}

void GuiGraal304::register_methods() {
  auto add = [this](const std::string& name, std::size_t count,
                    std::function<std::string(Args&)> body) {
    engine_.add_function(kClass, name, count, count, "",
                         [body](Engine&, SimObject*, Args& a) { return body(a); });
  };

  // Movement passes the key state to the local player (304-adventure.md).
  const char* moves[4] = {"moveUp", "moveLeft", "moveDown", "moveRight"};
  for (int dir = 0; dir < 4; ++dir)
    add(moves[dir], 3, [this, dir](Args& a) {
      game_->key(dir, on(a[2]));
      return std::string();
    });
  for (const char* name : {"doA", "doS", "doD", "doQ", "doP", "doM", "doMicro"})
    add(name, 3, [this](Args& a) {
      trace_not_yet(a);
      return std::string();
    });

  add("setChat", 3, [this](Args& a) {
    const std::string& text = a[2];
    if (text.compare(0, 6, "toall:") == 0) game_->to_all(text.substr(6));
    else if (text == "showname") {}          // kept on the player, not sent
    else if (text == "showap") game_->say("");
    else game_->say(text);
    if (SimObject* bar = engine_.find_object("ChatBar")) engine_.call_method(bar, "setText", {""});
    return std::string();
  });
  add("setPassWord", 3, [this](Args& a) {
    password_ = a[2];
    return std::string();
  });

  add("openServerList", 2, [this](Args&) {
    set_content("ServerListGui");
    servers_.clear();
    if (SimObject* list = engine_.find_object("ServerList")) engine_.call_method(list, "clear", {});
    listing_ = game_->list_open(pref("accountname"), password_);
    if (!listing_) list_dropped(game_->error());
    return std::string();
  });
  add("selectServer", 3, [this](Args& a) {
    select_server(a[2]);
    return std::string();
  });
  add("selectServerCategory", 3, [this](Args& a) {
    category_ = static_cast<std::int32_t>(parse_int(a[2]));
    fill_list();
    return std::string();
  });
  add("startOfflineMode", 2, [this](Args&) {
    if (game_->state() & Game304::connected) return std::string();
    set_content("AdventureGui");
    const std::string path = game_->offline_path();
    if (path.empty() || !game_->offline(path, 30, 30)) {
      engine_.trace.push_back("startOfflineMode: " + (path.empty() ? std::string("no offline level") : game_->error()));
      return std::string();
    }
    playing_ = true;
    game_->set_nickname(pref("nickname"));
    const std::string where = game_->player();
    echo("Player enters local level " + where.substr(0, where.find(' ')) + ".");
    return std::string();
  });
  add("connectToSelectedServer", 2, [this](Args&) {
    SimObject* list = engine_.find_object("ServerList");
    if (!list) return std::string();
    const std::string id = engine_.call_method(list, "getSelectedId", {});
    const auto fields = split_tabs(engine_.call_method(list, "getRowTextById", {id}));
    if (fields.size() <= 7) {   // a row needs more than seven fields
      engine_.trace.push_back("connectToSelectedServer: no server selected (row " + id + ")");
      return std::string();
    }
    connect_to(fields[6], static_cast<std::int32_t>(parse_int(fields[7])));
    return std::string();
  });
  add("serverDirectConnect", 3, [this](Args& a) {
    std::string host = a[2];
    int port = 14802;
    const std::size_t sep = host.find_last_of(": ");
    if (sep != std::string::npos) {
      port = static_cast<std::int32_t>(parse_int(host.substr(sep + 1)));
      host = host.substr(0, sep);
    }
    if (!host.empty() && port > 0) connect_to(host, port);
    return std::string();
  });

  for (const char* name : {"privateMessageSend"})
    add(name, 2, [this](Args& a) { trace_not_yet(a); return std::string(); });
  for (const char* name : {"playerListOpenPlayer", "playerListProfile", "updatePlayerMuted"})
    add(name, 3, [this](Args& a) { trace_not_yet(a); return std::string(); });

  add("updateLoadLevelFields", 2, [this](Args&) {
    std::string where = game_->player();
    const auto parts = split_tabs([&] { for (auto& c : where) if (c == ' ') c = '\t'; return where; }());
    const char* fields[3] = {"LoadLevelFilenameField", "LoadLevelXField", "LoadLevelYField"};
    for (int i = 0; i < 3; ++i)
      if (SimObject* f = engine_.find_object(fields[i]))
        engine_.call_method(f, "setValue", {i < static_cast<int>(parts.size()) ? parts[i] : std::string()});
    return std::string();
  });
  add("loadLevel", 5, [this](Args& a) {
    if (game_->state() & Game304::connected) {
      trace_not_yet(a);   // online, the level comes from the server
      return std::string();
    }
    std::string path = a[2];
    for (const std::string& dir : {std::string("levels/"), std::string()})
      if (engine_.files.exists(dir + a[2])) { path = engine_.files.root + "/" + dir + a[2]; break; }
    set_content("AdventureGui");
    if (game_->offline(path, parse_float(a[3]), parse_float(a[4]))) {
      playing_ = true;
      echo("Player enters local level " + a[2] + ".");
    } else {
      engine_.trace.push_back("loadLevel: " + game_->error());
    }
    return std::string();
  });
  add("updatePlayerProfile", 12, [this](Args& a) { trace_not_yet(a); return std::string(); });
  for (const char* name : {"updateMidiVolume", "updateMp3Volume", "updateRadioVolume",
                           "updateMicroActivationLevel", "updateGraalOptions"})
    add(name, 2, [this](Args& a) { trace_not_yet(a); return std::string(); });
}

void GuiGraal304::fill_list() {
  SimObject* list = engine_.find_object("ServerList");
  if (!list) return;
  engine_.call_method(list, "clear", {});
  for (std::size_t i = 0; i < servers_.size(); ++i)
    if (server_category_304(servers_[i].fields[0]) == category_)
      engine_.call_method(list, "addRow", {std::to_string(i), row_text(servers_[i])});
}

void GuiGraal304::select_server(const std::string& id) {
  const long i = static_cast<std::int32_t>(parse_int(id));
  if (i < 0 || static_cast<std::size_t>(i) >= servers_.size()) return;
  const ListServerEntry& e = servers_[static_cast<std::size_t>(i)];
  const std::pair<const char*, int> details[4] = {
      {"ServerLanguage", 1}, {"ServerGraalVersion", 4}, {"ServerDescription", 2}, {"ServerHomepage", 3}};
  for (const auto& d : details)
    if (SimObject* f = engine_.find_object(d.first)) engine_.call_method(f, "setText", {e.fields[d.second]});
}

void GuiGraal304::connect_to(const std::string& host, int port) {
  listing_ = false;
  game_->set_nickname(pref("nickname"));
  set_content("AdventureGui");
  echo("Connecting to the game server...");
  if (!game_->connect(host, port, pref("accountname"), password_)) {
    game_dropped(game_->error());
    return;
  }
  playing_ = true;
  echo("Done.");
}

void GuiGraal304::list_dropped(const std::string& why) {
  listing_ = false;
  echo("Disconnected from serverlister");
  engine_.trace.push_back("server lister: " + why);
  message_box("Disconnected", why);
  if (!(game_->state() & Game304::connected)) set_content("MainMenuGui");
}

void GuiGraal304::game_dropped(const std::string& why) {
  playing_ = false;
  engine_.trace.push_back("game server: " + why);
  message_box("Disconnected", why);
  set_content("MainMenuGui");
}

void GuiGraal304::tick(bool draw) {
  check_activated();
  if (listing_) {
    const int r = game_->list_poll();
    if (r == Game304::list_done) {
      listing_ = false;
      servers_.clear();
      for (int i = 0, n = game_->list_count(); i < n; ++i) servers_.push_back(game_->list_entry(i));
      engine_.trace.push_back("server lister: " + game_->list_status());
      engine_.trace.push_back("server lister: " + std::to_string(servers_.size()) + " servers");
      for (const auto& e : servers_)
        engine_.trace.push_back("server lister: \"" + e.fields[0] + "\" tab " +
                                std::to_string(server_category_304(e.fields[0])) + " at " + e.fields[6] + ":" +
                                e.fields[7]);
      fill_list();
    } else if (r == Game304::list_failed || r == Game304::list_none) {
      list_dropped(game_->list_status());
    }
  }
  if (playing_ && !game_->tick(draw)) game_dropped(game_->error());
}

} // namespace Torque
