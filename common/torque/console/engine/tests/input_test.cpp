// Input, dialog and console checks (stage 3). Each case is a short script
// written for the test and compiled with ../compiler, then keys are fed in
// through Engine::process_input. The expected console lines, calls and
// files are written beside each case. No original script is used.

#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "../engine.hpp"
#include "../../compiler/compile.hpp"

using namespace Torque;

namespace {
int failures = 0;

void check(bool ok, const std::string& what) {
  if (!ok) { std::cerr << "FAIL: " << what << "\n"; ++failures; }
}
template <class A, class B>
void same(const A& got, const B& want, const std::string& what) {
  if (!(got == want)) {
    std::cerr << "FAIL: " << what << "\n  got:  [" << got << "]\n  want: [" << want << "]\n";
    ++failures;
  }
}

struct Run {
  Engine e;
  std::vector<std::string> lines;
  std::filesystem::path dir;
  Run() {
    e.print = [this](const std::string& s) { lines.push_back(s); e.add_console_text(s); };
    e.compiler = [](const std::string& source, const std::string&, DsoBlock& out, std::string& error) {
      CompileError ce;
      if (compile_script(source, out, ce)) return true;
      error = "line " + std::to_string(ce.line) + ": " + ce.message;
      return false;
    };
    register_classes_304(e);
    register_input_304(e);
    e.create_object("GuiCanvas", "Canvas");
    start_input_304(e);
  }
  ~Run() { if (!dir.empty()) std::filesystem::remove_all(dir); }
  void files() {
    dir = std::filesystem::temp_directory_path() / ("tq-input-test-" + std::to_string(reinterpret_cast<std::uintptr_t>(this)));
    std::filesystem::create_directories(dir);
    e.files.root = dir.string();
    e.files.prefs_dir = dir.string();
  }
  void eval(const std::string& src) {
    if (!e.evaluate(src)) {
      std::cerr << "FAIL: script did not run:\n" << src << "\n";
      for (const auto& t : e.trace) std::cerr << "  " << t << "\n";
      ++failures;
    }
  }
  bool press(const std::string& key, unsigned mods = 0, char ascii = 0) {
    InputEvent ev; ev.key = key; ev.modifiers = mods; ev.ascii = ascii;
    return e.process_input(ev);
  }
  bool release(const std::string& key, unsigned mods = 0) {
    InputEvent ev; ev.key = key; ev.modifiers = mods; ev.make = false;
    return e.process_input(ev);
  }
  void tap(const std::string& key, unsigned mods = 0) { press(key, mods); release(key, mods); }
  void type(const std::string& text) {
    for (char c : text) {
      std::string k = c == ' ' ? "space" : std::string(1, static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
      press(k, (c >= 'A' && c <= 'Z') ? InputEvent::shift : 0u, c);
      release(k);
    }
  }
  std::string take() {
    std::string s;
    for (const auto& l : lines) s += l + "\n";
    lines.clear();
    return s;
  }
};

std::string slurp(const std::filesystem::path& p) {
  std::ifstream in(p, std::ios::binary);
  std::ostringstream s;
  s << in.rdbuf();
  return s.str();
}

const char* kMoveScript = R"(
new ActionMap(walkMap);
function walk(%v) { echo("walk " @ %v); }
function act(%v) { echo("act " @ %v); }
walkMap.bind(keyboard, up, walk);
walkMap.bind(keyboard, A, act);
)";

void bind_routes_make_and_break() {
  Run r;
  r.eval(kMoveScript);
  check(!r.press("up"), "an unpushed map takes nothing");
  r.release("up");
  same(r.take(), std::string(), "no call before push");

  r.eval("walkMap.push();");
  r.e.input_log.clear();
  check(r.press("up"), "pushed map takes up");
  check(r.release("up"), "release goes to the binding");
  same(r.take(), std::string("walk 1\nwalk 0\n"), "bind calls the function with 1 then 0");
  r.tap("a");
  same(r.take(), std::string("act 1\nact 0\n"), "key names bind without case (A)");
  r.tap("a", InputEvent::shift);
  same(r.take(), std::string(), "shift a does not match a binding for a (policy)");

  same(r.e.input_log.front(), std::string("keyboard up make: walkMap bind walk(1)"), "call chain logged");

  r.eval("walkMap.pop();");
  r.tap("up");
  same(r.take(), std::string(), "popped map takes nothing");
}

void top_map_wins_and_break_follows_make() {
  Run r;
  r.eval(kMoveScript);
  r.eval(R"(
new ActionMap(otherMap);
function other(%v) { echo("other " @ %v); }
otherMap.bind(keyboard, up, other);
walkMap.push();
otherMap.push();
)");
  r.press("up");
  r.eval("otherMap.pop();");
  r.release("up");
  r.tap("up");
  same(r.take(), std::string("other 1\nother 0\nwalk 1\nwalk 0\n"),
       "the top map takes the key; its release still goes there after a pop");

  r.eval("walkMap.delete();");
  check(r.e.action_maps.empty(), "a deleted map is no longer pushed");
  r.eval(kMoveScript);
  r.tap("up");
  same(r.take(), std::string(), "a new map of the same name is not pushed");
}

void global_map_first_and_bindcmd() {
  Run r;
  r.eval(kMoveScript);
  r.eval(R"(
walkMap.push();
walkMap.bind(keyboard, F2, walk);
function globalF2(%v) { echo("global " @ %v); }
GlobalActionMap.bind(keyboard, "F2", globalF2);
GlobalActionMap.bindCmd(keyboard, "alt enter", "", "echo(\"full screen\");");
GlobalActionMap.bindCmd(keyboard, "escape", "echo(\"esc down\");", "echo(\"esc up\");");
)");
  r.tap("f2");
  same(r.take(), std::string("global 1\nglobal 0\n"), "GlobalActionMap before the pushed maps");
  check(r.press("enter", InputEvent::alt), "alt enter is taken although its make command is empty");
  same(r.take(), std::string(), "empty make command runs nothing");
  r.release("enter", InputEvent::alt);
  same(r.take(), std::string("full screen\n"), "break command on release");
  check(!r.press("enter"), "plain enter does not match alt enter");
  r.tap("escape");
  same(r.take(), std::string("esc down\nesc up\n"), "bindCmd make then break");
  r.eval("GlobalActionMap.save();");
  same(r.take(), std::string("GlobalActionMap.bind(keyboard, \"f2\", globalF2);\n"
                             "GlobalActionMap.bindCmd(keyboard, \"alt return\", \"\", \"echo(\\\"full screen\\\");\");\n"
                             "GlobalActionMap.bindCmd(keyboard, \"escape\", \"echo(\\\"esc down\\\");\", \"echo(\\\"esc up\\\");\");\n"),
       "enter is stored as return (lab, 3.04)");
  check(r.press("return", InputEvent::alt), "the key named return matches too");
  r.release("return", InputEvent::alt);
  r.take();
}

const char* kConsoleScript = R"(
new GuiControl(TestConsoleDlg) {
  new GuiWindowCtrl() {
    new GuiScrollCtrl() { new GuiConsole("logView") {}; };
    new GuiConsoleEditCtrl("TestEntry") { historySize = "3"; altCommand = "TestEntry::eval();"; };
  };
};
$open = 0;
function TestEntry::eval() {
  %text = TestEntry.getValue();
  echo("==>" @ %text);
  eval(%text);
  TestEntry.setValue("");
}
function toggleTestConsole(%make) {
  if (!%make) return;
  if ($open) { Canvas.popDialog(TestConsoleDlg); $open = 0; }
  else { Canvas.pushDialog(TestConsoleDlg, 99); $open = 1; }
}
GlobalActionMap.bind(keyboard, "F2", toggleTestConsole);
)";

void console_dialog_evals_typed_line() {
  Run r;
  r.eval(kMoveScript);
  r.eval("walkMap.push();");
  r.eval(kConsoleScript);
  r.take();

  r.tap("f2");
  check(r.e.dialogs.size() == 1 && r.e.dialogs[0].layer == 99, "F2 pushes the console at layer 99");
  check(r.e.object(r.e.first_responder) && r.e.object(r.e.first_responder)->name == "TestEntry",
        "the edit line has the keys");
  r.type("echo(\"x\");");
  same(r.e.find_object("TestEntry")->field("value"), std::string("echo(\"x\");"), "typed text in the edit line");
  r.tap("enter");
  same(r.take(), std::string("==>echo(\"x\");\nx\n"), "enter runs altCommand, which evals the line");
  same(r.e.find_object("TestEntry")->field("value"), std::string(), "the line is cleared");
  same(r.e.console_buffer.back(), std::string("x"), "GuiConsole buffer has the output");

  r.type("a");
  same(r.take(), std::string(), "a typed into the console does not reach the map");
  r.tap("backspace");
  r.tap("up");
  same(r.e.find_object("TestEntry")->field("value"), std::string("echo(\"x\");"), "up recalls the last line");
  r.tap("down");
  same(r.e.find_object("TestEntry")->field("value"), std::string(), "down past the newest is empty");
  r.type("echo(1)");
  r.tap("left");
  r.type(";");
  r.tap("end");
  r.type(";");
  same(r.e.find_object("TestEntry")->field("value"), std::string("echo(1;);"), "cursor keys move the insert point");

  r.e.find_object("TestEntry")->set_field("value", "");
  r.type("%v = 7; echo(%v);");
  r.tap("enter");
  same(r.take(), std::string("==>%v = 7; echo(%v);\n7\n"),
       "a console line's locals live in ConsoleEntry::eval's frame, no global-scope error (lab, 3.04)");
  r.type("activateKeyboard();");
  r.tap("enter");
  same(r.take(), std::string("==>activateKeyboard();\n"), "activateKeyboard is registered and quiet (lab, 3.04)");
  r.tap("up");  // a direction key in the console is history, not the map
  same(r.take(), std::string(), "up in the console does not reach the map");

  r.tap("f2");
  check(r.e.dialogs.empty() && r.e.first_responder == 0, "F2 again pops the console and drops the focus");
  r.tap("a");
  same(r.take(), std::string("act 1\nact 0\n"), "keys reach the map again");
}

void console_history_size() {
  Run r;
  r.eval(kConsoleScript);
  r.tap("f2");
  for (const char* line : {"$a=1;", "$a=2;", "$a=3;", "$a=4;"}) { r.type(line); r.tap("enter"); }
  const auto& h = r.e.edits[r.e.find_object("TestEntry")->id].history;
  same(h.size(), std::size_t(3), "history keeps historySize lines");
  same(h.front(), std::string("$a=2;"), "the oldest line goes first");
  same(r.e.global("$a").str(), std::string("4"), "each line ran");
}

const char* kRemapScript = R"(
new ActionMap(walkMap);
function walk(%v) {}
function act(%v) {}
walkMap.bind(keyboard, up, walk);
walkMap.bind(keyboard, a, act);
new GuiControl(TestRemapDlg) {
  new GuiControl() { new GuiInputCtrl(TestInput) {}; };
};
function TestInput::onInputEvent(%this, %device, %action) {
  Canvas.popDialog(TestRemapDlg);
  echo("remap " @ %device @ " [" @ %action @ "]");
  if (%device $= "keyboard" && %action $= "escape") return;
  walkMap.bind(%device, %action, %this.cmd);
}
)";

void remap_dialog_saves_map() {
  Run r;
  r.files();
  r.eval(kRemapScript);
  r.eval("TestInput.cmd = \"walk\"; Canvas.pushDialog(TestRemapDlg);");
  check(r.e.object(r.e.first_responder) && r.e.object(r.e.first_responder)->name == "TestInput",
        "the input control has the keys");
  check(r.press("shift"), "a modifier alone is held back");
  r.release("shift");
  r.tap("k");
  same(r.take(), std::string("remap keyboard [k]\n"), "the next key goes to onInputEvent");
  check(r.e.dialogs.empty(), "the dialog popped itself");
  r.eval("Canvas.pushDialog(TestRemapDlg);");
  r.tap("k", InputEvent::ctrl);
  same(r.take(), std::string("remap keyboard [ctrl k]\n"), "modifiers lead the action string (policy)");
  r.eval("walkMap.save(\"client/config.cs\");");
  same(slurp(r.dir / "client/config.cs"),
       std::string("// Torque Input Map File\n"
                   "walkMap.delete();\n"
                   "new ActionMap(walkMap);\n"
                   "walkMap.bind(keyboard, \"a\", act);\n"
                   "walkMap.bind(keyboard, \"ctrl k\", walk);\n"),
       "binding walk again moves it: up and then k are unbound, the new key goes last (lab, 3.04)");
  r.take();
  r.eval("walkMap.save();");
  same(r.take(), std::string("walkMap.bind(keyboard, \"a\", act);\nwalkMap.bind(keyboard, \"ctrl k\", walk);\n"),
       "save() without a file prints only the binds (lab, 3.04)");
}

void remap_under_console_gets_keys_after() {
  Run r;
  r.eval(kRemapScript);
  r.eval(kConsoleScript);
  r.tap("f2");
  r.type("TestInput.cmd = \"walk\"; Canvas.pushDialog(TestRemapDlg);");
  r.tap("enter");
  same(r.e.object(r.e.first_responder)->name, std::string("TestEntry"), "the console stays on top and keeps the keys");
  r.tap("f2");
  same(r.e.object(r.e.first_responder)->name, std::string("TestInput"), "closing the console hands the keys to the remap dialog");
  r.take();
  r.tap("j");
  same(r.take(), std::string("remap keyboard [j]\n"), "the remap dialog takes the next key");
}

void remap_escape_goes_global_first() {
  Run r;
  r.eval(kRemapScript);
  r.eval("GlobalActionMap.bindCmd(keyboard, \"escape\", \"\", \"echo(\\\"quit box\\\");\");");
  r.eval("Canvas.pushDialog(TestRemapDlg);");
  r.tap("escape");
  same(r.take(), std::string("quit box\n"),
       "GlobalActionMap sees escape before the input control (policy; see README lab list)");
  check(r.e.dialogs.size() == 1, "the remap dialog is still up");
}

void dialogs_layers_and_focus() {
  Run r;
  r.eval(R"(
new GuiControl(LowDlg) { new GuiTextEditCtrl(LowEdit) {}; };
new GuiControl(HighDlg) { new GuiTextEditCtrl(HighEdit) {}; };
function LowDlg::onWake(%this) { echo("low wake"); }
function LowDlg::onSleep(%this) { echo("low sleep"); }
Canvas.pushDialog(HighDlg, 50);
Canvas.pushDialog(LowDlg);
)");
  same(r.take(), std::string("low wake\n"), "pushDialog wakes the dialog");
  same(r.e.dialogs.size(), std::size_t(2), "two dialogs");
  same(r.e.object(r.e.dialogs.back().control)->name, std::string("HighDlg"), "the higher layer stays on top");
  same(r.e.object(r.e.first_responder)->name, std::string("HighEdit"), "a dialog pushed below the top does not take the keys");
  r.eval("Canvas.popDialog();");
  same(r.e.object(r.e.dialogs.back().control)->name, std::string("LowDlg"), "popDialog() pops the top");
  same(r.e.object(r.e.first_responder)->name, std::string("LowEdit"), "focus moves to the dialog now on top");
  r.eval("Canvas.popDialog(LowDlg);");
  same(r.take(), std::string("low sleep\n"), "popDialog sleeps the dialog");
  check(r.e.first_responder == 0, "no dialog left, no focus");
}

void mouse_enabled_export() {
  Run r;
  r.files();
  r.eval("$pref::Input::MouseEnabled = 0;");
  start_input_304(r.e);
  r.eval("export(\"$pref::Input::*\", \"prefs.cs\", 0);");
  same(slurp(r.dir / "prefs.cs"), std::string("$pref::Input::MouseEnabled = \"1\";\r\n"),
       "input start-up sets MouseEnabled the way the original exports it");
}

} // namespace

int main() {
  bind_routes_make_and_break();
  top_map_wins_and_break_follows_make();
  global_map_first_and_bindcmd();
  console_dialog_evals_typed_line();
  console_history_size();
  remap_dialog_saves_map();
  remap_under_console_gets_keys_after();
  remap_escape_goes_global_first();
  dialogs_layers_and_focus();
  mouse_enabled_export();
  if (failures) { std::cerr << failures << " input test(s) failed\n"; return 1; }
  std::cout << "input tests passed\n";
  return 0;
}
