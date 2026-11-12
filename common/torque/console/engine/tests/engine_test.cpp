// Engine checks. Each case is a hand-assembled instruction stream with its
// expected console lines, values or files written down beside it. No
// original script, DSO or engine code is used.

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "../engine.hpp"
#include "assembler.hpp"

using namespace Asm;
using Torque::Engine;
using Torque::Value;

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
  Engine engine;
  std::vector<std::string> lines;
  Run() { engine.print = [this](const std::string& s) { lines.push_back(s); }; }
  std::string out() const {
    std::string s;
    for (const auto& l : lines) s += l + "\n";
    return s;
  }
  bool run(Block& code, const std::string& name = "test.cs", std::string* result = nullptr) {
    std::string err;
    auto block = engine.link(name, code.b, err);
    if (!block) { std::cerr << "link: " << err << "\n"; return false; }
    return engine.run_block(block, result);
  }
};

std::string slurp(const std::filesystem::path& p) {
  std::ifstream in(p, std::ios::binary);
  std::ostringstream s;
  s << in.rdbuf();
  return s.str();
}

// echo(A @ B SPC C) the way the scripts build it: ADVANCE_STR, then
// ADVANCE_STR_APPENDCHAR ' ', then REWIND_STR twice.
void test_strings() {
  Run r;
  Block c;
  c.w(PUSH_FRAME);
  c.str("Hello"); c.w(ADVANCE_STR); c.str("World"); c.w(ADVANCE_STR_APPENDCHAR); c.w(' ');
  c.str("again"); c.w(REWIND_STR); c.w(REWIND_STR); c.w(PUSH);
  c.callfunc("echo");
  c.w(STR_TO_NONE);
  // Case-insensitive $= : "ABC" $= "abc" is 1.
  c.str("ABC"); c.w(ADVANCE_STR_NUL); c.str("abc"); c.w(COMPARE_STR);
  c.w(UINT_TO_STR); c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.w(RETURN);
  check(r.run(c), "strings ran");
  same(r.out(), std::string("HelloWorld again\n1\n"), "concatenation and $=");
}

// Operand order: the left operand is on top. "%a - %b" pushes %b then %a.
void test_numbers() {
  Run r;
  Block c;
  c.flt(2); c.flt(5); c.w(SUB); c.w(FLT_TO_STR); c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.flt(4); c.flt(1); c.w(DIV); c.w(FLT_TO_STR); c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.flt(3); c.flt(1); c.w(CMPLT); c.w(UINT_TO_STR); c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.uint(3); c.uint(7); c.w(MOD); c.w(UINT_TO_STR); c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.uint(0xffffffffu); c.w(UINT_TO_STR); c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.str("12abc"); c.w(STR_TO_UINT); c.w(UINT_TO_FLT); c.flt(0.5); c.w(ADD); c.w(FLT_TO_STR);
  c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.w(RETURN);
  check(r.run(c), "numbers ran");
  same(r.out(), std::string("3\n0.25\n1\n1\n-1\n12.5\n"), "arithmetic order and formatting");
}

// Branches: JMPIFNOT pops; JMPIF_NP keeps the value when it jumps.
void test_branches() {
  Run r;
  Block c;
  c.uint(0); c.w(JMPIFNOT); auto j = c.here(); c.w(0);
  c.call("echo", {"skipped"}); c.w(STR_TO_NONE);
  c.patch(j, c.here());
  c.uint(7); c.w(JMPIF_NP); auto k = c.here(); c.w(0);
  c.uint(99);  // not reached
  c.patch(k, c.here());
  c.w(UINT_TO_STR); c.w(PUSH_FRAME); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.w(RETURN);
  check(r.run(c), "branches ran");
  same(r.out(), std::string("7\n"), "branch results");
}

// Globals keep their stored type; arrays join the index with '_'.
void test_variables() {
  Run r;
  Block c;
  c.uint(40); c.w(SETCURVAR_CREATE); c.ident("$pref::Count"); c.w(SAVEVAR_UINT); c.w(UINT_TO_NONE);
  c.flt(0.1); c.w(SETCURVAR_CREATE); c.ident("$pref::Speed"); c.w(SAVEVAR_FLT); c.w(FLT_TO_NONE);
  c.set_global_str("$pref::Name", "Fresh \"Meat\"");
  c.w(RETURN);
  // $grid[1, 2] = "x"; in the scripts' order: the name, then the value.
  Block d;
  d.id("$grid"); d.w(ADVANCE_STR); d.str("1"); d.w(ADVANCE_STR_COMMA); d.str("2"); d.w(REWIND_STR); d.w(REWIND_STR);
  d.w(SETCURVAR_ARRAY_CREATE); d.str("x"); d.w(SAVEVAR_STR); d.w(STR_TO_NONE);
  d.w(RETURN);
  r.engine.bind_variable("$pref::Engine", "1");
  Block e;
  e.uint(0); e.w(SETCURVAR_CREATE); e.ident("$PREF::engine"); e.w(SAVEVAR_UINT); e.w(UINT_TO_NONE); e.w(RETURN);
  check(r.run(c) && r.run(d) && r.run(e), "variables ran");
  same(r.engine.global("$grid1_2").str(), std::string("x"), "array name with comma");
  same(r.engine.global("$PREF::COUNT").str(), std::string("40"), "names ignore case");
  check(r.engine.global("$pref::Speed").kind == Value::Kind::floating, "float kept");
  check(r.engine.global("$pref::Engine").kind == Value::Kind::string, "engine variable stays a string");

  r.lines.clear();
  r.engine.call_function("export", {"$pref::*"});
  same(r.out(), std::string("$pref::Count = 40;\n$pref::Engine = \"0\";\n$pref::Name = \"Fresh \\\"Meat\\\"\";\n"
                             "$pref::Speed = 0.1;\n"), "export to the console: sorted, typed, escaped");
}

// A function with two arguments, one unused, returning a concatenation.
void test_functions() {
  Run r;
  Block c;
  auto end = c.function("join", "", "", {"%a", "", "%c"});
  c.w(SETCURVAR); c.ident("%a"); c.w(LOADVAR_STR); c.w(ADVANCE_STR);
  c.w(SETCURVAR); c.ident("%c"); c.w(LOADVAR_STR); c.w(REWIND_STR);
  c.end_function(end);
  c.w(PUSH_FRAME); c.call("join", {"x", "ignored", "z"}); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  // Missing arguments read as empty.
  c.w(PUSH_FRAME); c.call("join", {"only"}); c.w(PUSH); c.callfunc("echo"); c.w(STR_TO_NONE);
  c.call("nothere", {}); c.w(STR_TO_NONE);
  c.w(RETURN);
  check(r.run(c, "scripts/f.cs"), "functions ran");
  same(r.out(), std::string("xz\nonly\nscripts/f.cs (0): Unable to find function nothere\n"), "calls and unknown function");
}

// Packages: base, then common, then graal activated on top. Each calls
// Parent:: first, then echoes, so the base runs first.
void test_packages() {
  Run r;
  Block c;
  auto e1 = c.function("onStart", "", "", {});
  c.call("echo", {"base"}); c.w(STR_TO_NONE);
  c.end_function(e1);
  for (const char* pkg : {"common", "graal"}) {
    auto e = c.function("onStart", "", pkg, {});
    c.w(PUSH_FRAME); c.callfunc("onStart", 2); c.w(STR_TO_NONE);
    c.call("echo", {pkg}); c.w(STR_TO_NONE);
    c.end_function(e);
  }
  c.call("activatePackage", {"common"}); c.w(STR_TO_NONE);
  c.call("activatePackage", {"graal"}); c.w(STR_TO_NONE);
  c.call("onStart", {}); c.w(STR_TO_NONE);
  c.call("deactivatePackage", {"common"}); c.w(STR_TO_NONE);
  c.call("onStart", {}); c.w(STR_TO_NONE);
  c.w(RETURN);
  check(r.run(c), "packages ran");
  same(r.out(), std::string("base\ncommon\ngraal\nbase\n"), "package layering, Parent:: and deactivation");
}

// new GuiControl(Outer) { text = "a"; new GuiControl(Inner) { text = "b"; }; };
// in the scripts' shape, then a method on the name namespace.
void test_objects() {
  Run r;
  r.engine.add_class({"GuiControl", "SimGroup", true, true, true});
  Block c;
  auto end = c.function("Outer", "", "", {});  // placeholder to keep tables apart
  c.end_function(end);
  auto m = c.function("describe", "Outer", "", {"%this"});
  c.w(SETCURVAR); c.ident("%this"); c.w(LOADVAR_STR); c.w(SETCUROBJECT); c.w(SETCURFIELD); c.ident("text");
  c.w(LOADFIELD_STR); c.w(ADVANCE_STR); c.w(SETCURVAR); c.ident("%this"); c.w(LOADVAR_STR);
  c.w(SETCUROBJECT); c.w(SETCURFIELD); c.ident("width"); c.w(LOADFIELD_FLT); c.w(FLT_TO_STR); c.w(REWIND_STR);
  c.end_function(m);
  c.uint(0);
  c.w(PUSH_FRAME); c.id("GuiControl"); c.w(PUSH); c.id("Outer"); c.w(PUSH);
  c.w(CREATE_OBJECT); c.ident(""); c.w(0); auto fail = c.here(); c.w(0);
  c.str("a"); c.w(ADVANCE_STR); c.w(SETCUROBJECT_NEW); c.w(SETCURFIELD); c.ident("text");
  c.w(TERMINATE_REWIND_STR); c.w(SAVEFIELD_STR); c.w(STR_TO_NONE);
  c.flt(12); c.w(SETCUROBJECT_NEW); c.w(SETCURFIELD); c.ident("width"); c.w(SAVEFIELD_FLT); c.w(FLT_TO_NONE);
  c.w(ADD_OBJECT); c.w(1);
  c.w(PUSH_FRAME); c.id("GuiControl"); c.w(PUSH); c.id("Inner"); c.w(PUSH);
  c.w(CREATE_OBJECT); c.ident(""); c.w(0); auto fail2 = c.here(); c.w(0);
  c.str("b"); c.w(ADVANCE_STR); c.w(SETCUROBJECT_NEW); c.w(SETCURFIELD); c.ident("text");
  c.w(TERMINATE_REWIND_STR); c.w(SAVEFIELD_STR); c.w(STR_TO_NONE);
  c.w(ADD_OBJECT); c.w(0);
  c.w(END_OBJECT); c.w(0);
  c.patch(fail2, c.here());
  c.w(END_OBJECT); c.w(1);
  c.patch(fail, c.here());
  c.w(SETCURVAR_CREATE); c.ident("$made"); c.w(SAVEVAR_UINT); c.w(UINT_TO_NONE);
  // echo(Outer.describe());
  c.w(PUSH_FRAME); c.w(PUSH_FRAME); c.id("Outer"); c.w(PUSH); c.callfunc("describe", 1); c.w(PUSH);
  c.callfunc("echo"); c.w(STR_TO_NONE);
  // A class that does not exist jumps to the fail target with 0.
  c.uint(0);
  c.w(PUSH_FRAME); c.id("NoSuchClass"); c.w(PUSH); c.str(""); c.w(PUSH);
  c.w(CREATE_OBJECT); c.ident(""); c.w(0); auto fail3 = c.here(); c.w(0);
  c.w(ADD_OBJECT); c.w(1); c.w(END_OBJECT); c.w(1);
  c.patch(fail3, c.here());
  c.w(SETCURVAR_CREATE); c.ident("$failed"); c.w(SAVEVAR_UINT); c.w(UINT_TO_NONE);
  c.call("frob", {"Inner"}, 1); c.w(STR_TO_NONE);
  c.call("frob", {"Nobody"}, 1); c.w(STR_TO_NONE);
  c.w(RETURN);
  check(r.run(c, "ui/test.gui"), "objects ran");
  auto* outer = r.engine.find_object("Outer");
  auto* inner = r.engine.find_object("Outer/Inner");
  check(outer && inner, "named objects and a child path");
  if (outer && inner) {
    same(r.engine.global("$made").str(), std::to_string(outer->id), "new returns the outer id");
    check(outer->members.size() == 1 && outer->members[0] == inner->id, "inner is a child of outer");
    check(inner->group == outer->id, "inner's group");
    check(outer->group == 0 && r.engine.root_group()->members.back() == outer->id, "outer is in RootGroup");
    same(inner->field("TEXT"), std::string("b"), "field names ignore case");
  }
  same(r.engine.global("$failed").str(), std::string("0"), "failed new returns 0");
  const std::string inner_id = inner ? std::to_string(inner->id) : "?";
  same(r.out(), std::string("a12\n"
                             "ui/test.gui (0): Unable to instantiate non-conobject class NoSuchClass.\n"
                             "ui/test.gui (0): Unknown command frob.\n"
                             "  Object Inner(" + inner_id + ") Inner -> GuiControl -> SimGroup -> SimSet -> SimObject\n"
                             "ui/test.gui (0): Unable to find object: 'Nobody' attempting to call function 'frob'\n"),
        "method on a name namespace and object errors");
  // Deleting a group deletes its children.
  if (outer) r.engine.delete_object(outer->id);
  check(!r.engine.find_object("Inner") && !r.engine.find_object("Outer"), "group delete");
}

// Native argument counts: too few prints the two usage lines.
void test_arity() {
  Run r;
  Block c;
  c.call("strlen", {}); c.w(STR_TO_NONE);
  c.w(RETURN);
  check(r.run(c, "a.cs"), "arity ran");
  same(r.out(), std::string("a.cs (0): ::strlen - wrong number of arguments.\na.cs (0): usage: strlen(string)\n"),
        "wrong argument count");
}

void test_builtins() {
  Run r;
  auto call = [&](const char* fn, Torque::Args a) { return r.engine.call_function(fn, std::move(a)); };
  same(call("getWord", {"a b  c", "2"}), std::string(""), "consecutive spaces make an empty word");
  same(call("getWord", {"a b  c", "3"}), std::string("c"), "word after the empty one");
  same(call("getWordCount", {"a b  c"}), std::string("4"), "word count");
  same(call("getWords", {"a b c d", "1", "2"}), std::string("b c"), "word range");
  same(call("getField", {"x\ty z\tw", "1"}), std::string("y z"), "fields split on tabs only");
  same(call("setWord", {"a b c", "1", "X"}), std::string("a X c"), "set word");
  same(call("removeWord", {"a b c", "0"}), std::string("b c"), "remove word");
  same(call("getSubStr", {"language English", "9", "7"}), std::string("English"), "substring");
  same(call("strstr", {"abc", "c"}), std::string("2"), "strstr");
  same(call("strstr", {"abc", "z"}), std::string("-1"), "strstr miss");
  same(call("stripMLControlChars", {"<font:Arial:14>Hi"}), std::string("Hi"), "strip markup");
  same(call("fileBase", {"graaldata/languages/languageEnglish.cs"}), std::string("languageEnglish"), "fileBase");
  same(call("filePath", {"a/b/c.cs"}), std::string("a/b"), "filePath");
  same(call("fileExt", {"a/b/c.cs"}), std::string(".cs"), "fileExt");
  same(call("isObject", {"RootGroup"}), std::string("1"), "RootGroup exists");
  same(call("isObject", {"GlobalActionMap"}), std::string("1"), "GlobalActionMap exists");
  same(call("isObject", {""}), std::string("0"), "empty name");
  same(call("strupr", {"abc"}), std::string("ABC"), "strupr");
  same(call("trim", {"  x \t"}), std::string("x"), "trim");
}

// ActionMap.save() and export() files, with exec path rules.
void test_files() {
  namespace fs = std::filesystem;
  const fs::path dir = fs::temp_directory_path() / "tq-engine-test";
  fs::remove_all(dir);
  fs::create_directories(dir / "root/mod/client");
  Run r;
  r.engine.files.root = (dir / "root").string();
  r.engine.files.prefs_dir = (dir / "prefs").string();

  // mod/main.cs.dso: exec("./client/init.cs"); then save and export.
  Block m;
  m.call("exec", {"./client/init.cs"}); m.w(STR_TO_NONE);
  m.call("echo", {"main done"}); m.w(STR_TO_NONE);
  m.w(RETURN);
  // mod/client/init.cs.dso: new ActionMap(moveMap); binds; save; export.
  Block i;
  i.uint(0);
  i.w(PUSH_FRAME); i.id("ActionMap"); i.w(PUSH); i.id("moveMap"); i.w(PUSH);
  i.w(CREATE_OBJECT); i.ident(""); i.w(0); auto f = i.here(); i.w(0);
  i.w(ADD_OBJECT); i.w(1); i.w(END_OBJECT); i.w(1);
  i.patch(f, i.here());
  i.w(UINT_TO_NONE);
  i.call("bind", {"moveMap", "keyboard", "F3", "bringUpOptions"}, 1); i.w(STR_TO_NONE);
  i.call("bind", {"moveMap", "keyboard0", "up", "moveUp"}, 1); i.w(STR_TO_NONE);
  i.call("save", {"moveMap", "./config.cs", "0"}, 1); i.w(STR_TO_NONE);
  i.set_global_str("$pref::B", "2");
  i.uint(1); i.w(SETCURVAR_CREATE); i.ident("$pref::a"); i.w(SAVEVAR_UINT); i.w(UINT_TO_NONE);
  i.call("export", {"$pref::*", "~/prefs.cs", "0"}); i.w(STR_TO_NONE);
  i.call("echo", {"init done"}); i.w(STR_TO_NONE);
  i.w(RETURN);
  {
    auto bytes = m.bytes();
    std::ofstream(dir / "root/mod/main.cs.dso", std::ios::binary).write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    bytes = i.bytes();
    std::ofstream(dir / "root/mod/client/init.cs.dso", std::ios::binary).write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  }
  check(r.engine.exec_file("mod/main.cs"), "exec of a compiled script");
  same(r.out(), std::string("init done\nmain done\n"), "nested exec ran in order");
  same(slurp(dir / "prefs/mod/client/config.cs"),
        std::string("// Torque Input Map File\nmoveMap.delete();\nnew ActionMap(moveMap);\n"
                    "moveMap.bind(keyboard, \"f3\", bringUpOptions);\nmoveMap.bind(keyboard, \"up\", moveUp);\n"),
        "ActionMap file, relative to the running script");
  same(slurp(dir / "prefs/mod/prefs.cs"), std::string("$pref::a = 1;\r\n$pref::B = \"2\";\r\n"),
        "export file: case-insensitive order, CRLF, ~/ is the mod root");
  check(!r.engine.exec_file("mod/missing.cs"), "missing script fails");
  // A plain script needs a compiler; none is linked.
  std::ofstream(dir / "prefs/mod/client/prefs.cs") << "$x = 1;\n";
  check(!r.engine.exec_file("mod/client/prefs.cs"), "plain script without a compiler fails");
  fs::remove_all(dir);
}

// Events run in time order; an object's events die with it.
void test_schedule() {
  Run r;
  r.engine.call_function("schedule", {"20", "0", "echo", "second"});
  r.engine.call_function("schedule", {"10", "0", "echo", "first"});
  auto* o = r.engine.create_object("ScriptObject", "Temp");
  r.engine.call_function("schedule", {"15", "Temp", "echo", "never"});
  r.engine.delete_object(o->id);
  r.engine.advance(30);
  same(r.out(), std::string("first\nsecond\n"), "event order and cancellation");
  same(r.engine.sim_time(), 30u, "sim time");
}

// Runaway and malformed code stop with an error instead of running on.
void test_limits() {
  Run r;
  r.engine.limits.steps = 1000;
  Block loop;
  loop.w(JMP); loop.w(0);
  check(!r.run(loop), "step limit stops an infinite loop");
  Block under;
  under.w(UINT_TO_NONE); under.w(RETURN);
  check(!r.run(under), "integer stack underflow");
  Block tag;
  tag.w(TAG_TO_STR); tag.w(0); tag.w(RETURN);
  check(!r.run(tag), "unread opcode fails");
  Block off;
  off.uint(1);
  check(!r.run(off), "falling off the end fails");
  check(r.engine.trace.size() == 4, "each failure is traced");
}

} // namespace

int main() {
  test_strings();
  test_numbers();
  test_branches();
  test_variables();
  test_functions();
  test_packages();
  test_objects();
  test_arity();
  test_builtins();
  test_files();
  test_schedule();
  test_limits();
  if (failures) { std::cerr << failures << " check(s) failed\n"; return 1; }
  std::cout << "engine tests passed\n";
  return 0;
}
