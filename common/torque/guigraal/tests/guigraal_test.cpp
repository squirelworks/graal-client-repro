// GuiGraalCtrl (3.04) against a fake game. The control tree and the
// scripts here are written for the test: no original script, DSO or
// engine code is used. Each case states what the control must do.

#include <cstdio>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "../../console/compiler/compile.hpp"
#include "../guigraal304.hpp"

using namespace Torque;

namespace {

int failures = 0;

void check(bool ok, const std::string& what) {
  if (!ok) {
    ++failures;
    std::cerr << "FAIL: " << what << "\n";
  }
}

void check_eq(const std::string& got, const std::string& want, const std::string& what) {
  if (got != want) {
    ++failures;
    std::cerr << "FAIL: " << what << ": got \"" << got << "\", want \"" << want << "\"\n";
  }
}

struct FakeGame : Game304 {
  std::vector<std::string> calls;
  std::vector<ListServerEntry> list;
  int poll_result = list_waiting;
  bool connect_ok = true, tick_ok = true;
  int st = 0;
  std::string err;
  std::uint32_t pixels[4] = {0xFF000000u, 0xFFFF0000u, 0xFF00FF00u, 0xFF0000FFu};

  std::string error() override { return err; }
  void set_nickname(const std::string& n) override { calls.push_back("nick " + n); }
  bool list_open(const std::string& a, const std::string& p) override {
    calls.push_back("list " + a + " " + p);
    return true;
  }
  int list_poll() override { return poll_result; }
  std::string list_status() override { return poll_result == list_failed ? "the listserver closed the link" : "3 servers"; }
  int list_count() override { return static_cast<int>(list.size()); }
  ListServerEntry list_entry(int i) override { return list[static_cast<std::size_t>(i)]; }
  bool connect(const std::string& host, int port, const std::string& a, const std::string& p) override {
    calls.push_back("connect " + host + " " + std::to_string(port) + " " + a + " " + p);
    if (connect_ok) st = connected;
    return connect_ok;
  }
  bool offline(const std::string& level, double x, double y) override {
    std::ostringstream s;
    s << "offline " << level << " " << x << " " << y;
    calls.push_back(s.str());
    st = playing_offline;
    return true;
  }
  std::string offline_path() override { return "/install/levels/tutorial/offlinetutorial.gmap"; }
  void key(int dir, bool down) override { calls.push_back("key " + std::to_string(dir) + " " + (down ? "1" : "0")); }
  void say(const std::string& t) override { calls.push_back("say " + t); }
  void to_all(const std::string& t) override { calls.push_back("toall " + t); }
  bool tick(bool) override {
    calls.push_back("tick");
    if (!tick_ok) st = 0;
    return tick_ok;
  }
  int state() override { return st; }
  const std::uint32_t* frame(int& w, int& h) override { w = 2; h = 2; return pixels; }
  std::string player() override { return "onlinestartlocal.graal 30.50 31.00 2"; }

  std::string last() const { return calls.empty() ? std::string() : calls.back(); }
  bool has(const std::string& c) const {
    for (const auto& x : calls) if (x == c) return true;
    return false;
  }
};

ListServerEntry entry(const std::string& name, const std::string& host, const std::string& port) {
  ListServerEntry e;
  e.fields[0] = name;
  e.fields[1] = "English";
  e.fields[2] = "desc of " + name;
  e.fields[3] = "http://example.invalid/";
  e.fields[4] = "3.04";
  e.fields[5] = "7";
  e.fields[6] = host;
  e.fields[7] = port;
  return e;
}

// A small control tree shaped like the shipped one (names only), and the
// script hooks the control relies on.
const char* kTree = R"(
new GuiCanvas(Canvas) {};
new GuiControl(MainMenuGui) {};
new GuiControl(ServerListGui) {
  new GuiTextListCtrl(ServerList) {};
  new GuiTextEditCtrl(ServerLanguage) {};
  new GuiTextEditCtrl(ServerGraalVersion) {};
  new GuiTextEditCtrl(ServerHomepage) {};
  new GuiMLTextCtrl(ServerDescription) {};
};
new GuiControl(AdventureGui) {
  new GuiGraalCtrl(Adventure) {
    new GuiTextEditCtrl(ChatBar) { text = "hello"; };
  };
};
new GuiControl(LoadLevelGui) {
  new GuiTextEditCtrl(LoadLevelFilenameField) {};
  new GuiTextEditCtrl(LoadLevelXField) {};
  new GuiTextEditCtrl(LoadLevelYField) {};
};
function ServerList::onSelect(%this, %row) { Adventure.selectServer(%row); }
function MessageBoxOK(%title, %message) { $mbTitle = %title; $mbText = %message; }
$pref::Graal::accountname = "labacct";
$pref::Graal::nickname = "Lab Nick";
)";

struct Rig {
  Engine engine;
  std::ostringstream console;
  FakeGame* game = nullptr;
  std::unique_ptr<GuiGraal304> graal;

  Rig() {
    engine.print = [this](const std::string& t) { console << t << "\n"; };
    register_builtins(engine);
    register_classes_304(engine);
    register_input_304(engine);
    register_text_list_304(engine);
    engine.compiler = [](const std::string& source, const std::string&, DsoBlock& out, std::string& error) {
      CompileError e;
      if (compile_script(source, out, e)) return true;
      error = "line " + std::to_string(e.line) + ": " + e.message;
      return false;
    };
    auto g = std::make_unique<FakeGame>();
    game = g.get();
    graal = std::make_unique<GuiGraal304>(engine, std::move(g));
    check(engine.evaluate(kTree), "the test tree compiles and runs");
  }
  std::string eval(const std::string& code) {
    std::string r;
    check(engine.evaluate(code, &r), "evaluates: " + code);
    return r;
  }
  std::string content() {
    SimObject* c = engine.find_object(engine.find_object("Canvas")->field("content"));
    return c ? c->name : std::string();
  }
  std::string text(const std::string& obj) { return engine.find_object(obj)->field("text"); }
};

void test_method_table() {
  Rig r;
  check_eq(std::to_string(GuiGraal304::method_names().size()), "31", "31 methods");
  // Each method answers with exactly its count; one more argument is refused.
  const std::vector<std::pair<std::string, std::string>> calls = {
      {"moveUp", "1"}, {"openServerList", ""}, {"loadLevel", "\"a.graal\", 1, 2"},
      {"updatePlayerProfile", "1,2,3,4,5,6,7,8,9,10"}, {"updateGraalOptions", ""}};
  for (const auto& c : calls) {
    r.game->calls.clear();
    r.engine.trace.clear();
    r.eval("Adventure." + c.first + "(" + c.second + ");");
    const bool reached = !r.game->calls.empty() || !r.engine.trace.empty();
    check(reached, c.first + " is registered with its argument count");
  }
  r.game->calls.clear();
  r.eval("Adventure.moveUp(1, 2);");
  check(r.game->calls.empty(), "moveUp with two arguments is refused");
  for (const auto& name : GuiGraal304::method_names())
    check(name != "setNickName" && name != "retrieveAccountFields", "3.153-only " + name + " is not on the 3.04 table");
}

void test_moves_and_chat() {
  Rig r;
  r.eval("Adventure.moveRight(1); Adventure.moveRight(0); Adventure.moveUp(1);");
  check(r.game->has("key 3 1") && r.game->has("key 3 0") && r.game->has("key 0 1"), "moves reach the player");
  r.eval("Adventure.setChat(\"toall:hi all\");");
  check_eq(r.game->last(), "toall hi all", "toall: is stripped and sent to all");
  check_eq(r.text("ChatBar"), "", "setChat clears ChatBar");
  r.game->calls.clear();
  r.eval("Adventure.setChat(\"showname\");");
  check(r.game->calls.empty(), "showname sends nothing");
  r.eval("Adventure.setChat(\"showap\");");
  check_eq(r.game->last(), "say ", "showap sends an empty chat");
  r.eval("Adventure.setChat(\"hello there\");");
  check_eq(r.game->last(), "say hello there", "other lines are the player's chat");
  r.engine.trace.clear();
  r.eval("Adventure.doA(1);");
  check(!r.engine.trace.empty() && r.engine.trace.back().find("doA(1)") != std::string::npos,
        "doA is traced as not yet in the game");
}

void test_server_list_and_connect() {
  Rig r;
  r.game->list = {entry("P Gold One", "10.0.0.1", "14900"), entry("Lab Classic", "127.0.0.1", "14802"),
                  entry("H Hosted", "10.0.0.3", "14901"), entry("U Hidden", "10.0.0.4", "14902"),
                  entry("3 Three", "10.0.0.5", "14903")};
  r.eval("Adventure.setPassWord(\"secret\"); Canvas.setContent(ServerListGui); Adventure.openServerList();");
  check_eq(r.game->last(), "list labacct secret", "the list is asked with the account pref and password");
  check_eq(r.content(), "ServerListGui", "the server list is shown");
  r.graal->tick();
  check_eq(r.eval("return ServerList.rowCount();"), "0", "no rows while the list is pending");
  r.game->poll_result = Game304::list_done;
  r.graal->tick();
  check_eq(r.eval("return ServerList.rowCount();"), "1", "the Classic tab shows the unprefixed server");
  check_eq(r.eval("return getField(ServerList.getRowText(0), 0);"), "Lab Classic", "row column 0 is the name");
  check_eq(r.eval("return getField(ServerList.getRowText(0), 1);"), "7", "row column 1 is the players");
  r.eval("Adventure.selectServerCategory(0);");
  check_eq(r.eval("return ServerList.getRowId(0) SPC ServerList.rowCount();"), "0 1", "Gold has the P server");
  r.eval("Adventure.selectServerCategory(3);");
  check_eq(r.eval("return ServerList.getRowId(0);"), "2", "Hosted has the H server");
  r.eval("Adventure.selectServerCategory(1);");
  check_eq(r.eval("return ServerList.getRowId(0);"), "4", "3D has the 3 server");
  r.eval("Adventure.selectServerCategory(2);");
  r.eval("ServerList.setSelectedRow(0);");
  check_eq(r.text("ServerLanguage"), "English", "onSelect fills the language");
  check_eq(r.text("ServerDescription"), "desc of Lab Classic", "onSelect fills the description");
  check_eq(r.text("ServerGraalVersion"), "3.04", "onSelect fills the version");
  r.eval("Adventure.connectToSelectedServer();");
  check(r.game->has("nick Lab Nick"), "the nickname pref is copied");
  check_eq(r.game->last(), "connect 127.0.0.1 14802 labacct secret", "the row's host and port are used");
  check_eq(r.content(), "AdventureGui", "the game is shown");
  check(r.graal->activated(), "the control was activated by its wake");
  check_eq(r.console.str(), "Graal activated!\nConnecting to the game server...\nDone.\n", "console lines");
  r.graal->tick();
  check_eq(r.game->last(), "tick", "the game ticks once playing");
  r.game->tick_ok = false;
  r.game->err = "link closed";
  r.graal->tick();
  check_eq(r.eval("return $mbTitle TAB $mbText;"), "Disconnected\tlink closed", "a dead link raises MessageBoxOK");
  check_eq(r.content(), "MainMenuGui", "and returns to the main menu");
}

void test_list_drop_and_direct() {
  Rig r;
  r.eval("Adventure.openServerList();");
  r.game->poll_result = Game304::list_failed;
  r.graal->tick();
  check(r.console.str().find("Disconnected from serverlister\n") != std::string::npos, "list drop logs");
  check_eq(r.content(), "MainMenuGui", "list drop returns to the main menu");
  r.eval("Adventure.serverDirectConnect(\"127.0.0.1:14900\");");
  check_eq(r.game->last(), "connect 127.0.0.1 14900 labacct ", "direct connect with a port");
  r.eval("Adventure.serverDirectConnect(\"lab.invalid\");");
  check_eq(r.game->last(), "connect lab.invalid 14802 labacct ", "direct connect, default port");
}

void test_offline() {
  Rig r;
  r.game->st = Game304::connected;
  r.eval("Adventure.startOfflineMode();");
  check(r.game->calls.empty(), "no offline mode while a game connection is open");
  r.game->st = 0;
  r.eval("Adventure.startOfflineMode();");
  check(r.game->has("offline /install/levels/tutorial/offlinetutorial.gmap 30 30"), "offline loads the tutorial gmap");
  check_eq(r.content(), "AdventureGui", "offline shows the game");
  check(r.console.str().find("Player enters local level onlinestartlocal.graal.\n") != std::string::npos,
        "offline logs the local level");
  r.eval("Adventure.updateLoadLevelFields();");
  check_eq(r.engine.find_object("LoadLevelFilenameField")->field("value"), "onlinestartlocal.graal", "F5 level name");
  check_eq(r.engine.find_object("LoadLevelXField")->field("value"), "30.50", "F5 x");
  check_eq(r.engine.find_object("LoadLevelYField")->field("value"), "31.00", "F5 y");
}

void test_text_list() {
  Rig r;
  r.eval("ServerList.addRow(5, \"b\\t2\"); ServerList.addRow(3, \"a\\t10\"); ServerList.addRow(9, \"c\\t1\", 0);");
  check_eq(r.eval("return ServerList.getRowId(0) SPC ServerList.getRowId(1) SPC ServerList.getRowId(2);"), "9 5 3",
           "addRow at an index");
  r.eval("ServerList.sort(0);");
  check_eq(r.eval("return ServerList.getRowId(0) SPC ServerList.getRowId(2);"), "3 9", "sort by column 0");
  r.eval("ServerList.sortNumerical(1, 0);");
  check_eq(r.eval("return ServerList.getRowId(0) SPC ServerList.getRowId(2);"), "3 9", "numerical, decreasing");
  r.eval("ServerList.setRowById(5, \"bb\\t2\");");
  check_eq(r.eval("return getField(ServerList.getRowTextById(5), 0);"), "bb", "setRowById");
  check_eq(r.eval("return ServerList.getSelectedId();"), "-1", "nothing selected");
  r.eval("ServerList.setSelectedById(5); ServerList.removeRowById(5);");
  check_eq(r.eval("return ServerList.getSelectedId() SPC ServerList.rowCount();"), "-1 2", "removing the selected row");
}

} // namespace

int main() {
  test_method_table();
  test_moves_and_chat();
  test_server_list_and_connect();
  test_list_drop_and_direct();
  test_offline();
  test_text_list();
  if (failures) {
    std::cerr << failures << " failure(s)\n";
    return 1;
  }
  std::cout << "guigraal-test: all passed\n";
  return 0;
}
