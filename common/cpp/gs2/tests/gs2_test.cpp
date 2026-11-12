// Unit tests for the GS2 loader and machine. Every script here is written
// by hand with tests/assembler.hpp.

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

#include <zlib.h>

#include "../engine_commands.hpp"
#include "../gs2.hpp"
#include "../startscripts.hpp"
#include "assembler.hpp"

using gs2asm::Asm;

static int failures = 0;
#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) {                                                      \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                       \
    }                                                                   \
  } while (0)

static bool hasError(const gs2::Machine& m, const std::string& part) {
  for (const auto& e : m.errors())
    if (e.find(part) != std::string::npos) return true;
  return false;
}

static double global(const gs2::Machine& m, const std::string& name) {
  auto v = m.universe()->child(name);
  return v ? v->number() : -9999;
}

static std::string globalStr(const gs2::Machine& m, const std::string& name) {
  auto v = m.universe()->child(name);
  return v ? v->string() : "<missing>";
}

// x = <value>; as the compiler-shaped "var x, value, assign".
static void setGlobal(Asm& a, const std::string& name, double value) {
  a.var(name).num(value).op(Asm::ASSIGN);
}

static gs2::VarPtr run(gs2::Machine& m, const Asm& a, const std::string& name = "npc") {
  auto v = m.newVar(name);
  std::string err;
  if (!m.setScript(v, a.bytes(), &err)) std::fprintf(stderr, "load failed: %s\n", err.c_str());
  m.runScripts();
  return v;
}

static void testLoader() {
  Asm a;
  a.mask = 0x81;
  a.function("public.onCreated", {});
  a.num(5).num(-200).num(100000).num(0.5).str("hello").op(Asm::RET);
  auto r = gs2::load(a.bytes());
  CHECK(r.ok());
  if (!r.ok()) return;
  const auto& s = *r.script;
  CHECK(s.gs1EventMask == 0x81);
  CHECK(s.functions.size() == 1);
  CHECK(s.functions[0].name == "onCreated");
  CHECK(s.functions[0].isPublic);
  CHECK(s.findFunction("ONCREATED") != nullptr);
  // marker, paramsend, savestack, 4 numbers, string, ret
  CHECK(s.code.size() == 9);
  CHECK(s.code[3].num == 5);
  CHECK(s.code[4].num == -200);
  CHECK(s.code[5].num == 100000);
  CHECK(s.code[6].num == 0.5);
  CHECK(s.code[7].str == "hello");

  // A truncated segment and an unknown type end the read; what came
  // before stays.
  std::string b = a.bytes();
  std::string cut = b.substr(0, 8 + 4) + std::string("\x00\x00\x00\x09\x7f\xff\xff\xff", 8);
  auto r2 = gs2::load(cut);
  CHECK(r2.ok() && r2.script->gs1EventMask == 0x81 && r2.script->code.empty());

  // A string index past the table is refused.
  std::string bad;
  auto be = [&](std::uint32_t v) { for (int s = 24; s >= 0; s -= 8) bad.push_back(static_cast<char>((v >> s) & 0xFF)); };
  be(3); be(2); bad += std::string("a\0", 2);
  be(4); be(3); bad += std::string("\x15\xF0\x05", 3);
  auto r3 = gs2::load(bad);
  CHECK(!r3.ok() && r3.error.find("outside the table") != std::string::npos);

  // An operand with no opcode before it is refused.
  std::string bad2;
  auto be2 = [&](std::uint32_t v) { for (int s = 24; s >= 0; s -= 8) bad2.push_back(static_cast<char>((v >> s) & 0xFF)); };
  be2(4); be2(2); bad2 += std::string("\xF3\x01", 2);
  CHECK(!gs2::load(bad2).ok());

  CHECK(!gs2::load(std::string("junk")).ok());
}

static void testFusion() {
  Asm a;
  a.var("x").op(Asm::COPY).num(1).op(Asm::ADD).op(Asm::ASSIGN);     // 216
  a.var("y").var("x").var("x").op(Asm::MUL).op(Asm::ASSIGN);         // mul+assign -> 210
  a.var("x").num(3).op(Asm::LT).op(Asm::POP);                        // 224
  a.op(Asm::SLOTLOAD).operand(2).op(Asm::COPY).op(Asm::POP).op(Asm::POP);  // 228
  a.op(Asm::SLOTLOAD).operand(2).op(Asm::INC).op(Asm::POP);         // 231
  auto r = gs2::load(a.bytes());
  CHECK(r.ok());
  if (!r.ok()) return;
  const auto& c = r.script->code;
  CHECK(c[2].op == 216 && c[2].loadedOp == 20);
  CHECK(c[3].op == 208);  // the add before assign is rewritten too; it is stepped over
  CHECK(c[8].op == 210);
  CHECK(c[11].op == 224);
  CHECK(c[14].op == 233);
  CHECK(c[18].op == 231);
  CHECK(r.script->fusedPairs >= 5);
}

static void testProfiles() {
  using gs2::Profile;
  CHECK(gs2::opcodeInProfile(6, Profile::Engine42));
  CHECK(!gs2::opcodeInProfile(48, Profile::Engine42));
  CHECK(gs2::opcodeInProfile(48, Profile::Engine50));
  CHECK(!gs2::opcodeInProfile(48, Profile::Engine600));
  CHECK(!gs2::opcodeInProfile(54, Profile::Engine42));
  CHECK(gs2::opcodeInProfile(54, Profile::Engine50));
  CHECK(gs2::opcodeInProfile(54, Profile::Engine600));
  CHECK(gs2::opcodeInProfile(121, Profile::Engine600));
  CHECK(gs2::opcodeInProfile(240, Profile::Engine600));
  CHECK(!gs2::opcodeInProfile(240, Profile::Engine50));
  int n = 0;
  for (int i = 0; i < 256; ++i) n += gs2::opcodeInProfile(i, Profile::Engine42);
  CHECK(n == 154);
}

static void testArithmeticAndAssign() {
  gs2::Machine m;
  Asm a;
  a.function("onCreated", {});
  a.var("x").num(1).num(2).op(Asm::ADD).op(Asm::ASSIGN);           // fused 208
  a.var("z").num(7).num(2).op(Asm::MOD).op(Asm::ASSIGN);
  a.var("w").num(-7).num(2).op(Asm::MOD).op(Asm::ASSIGN);           // floor remainder: 1
  a.var("d").num(1).num(0).op(Asm::DIV).op(Asm::ASSIGN);            // fused divide by 0: 0
  a.var("n").num(-1.5).op(Asm::INT).op(Asm::ASSIGN);
  a.var("b").num(5).num(3).op(Asm::BITOR).op(Asm::ASSIGN);
  a.var("c").num(3).op(Asm::NOT).op(Asm::ASSIGN);
  a.var("q").num(2).op(Asm::NEG).op(Asm::ASSIGN);
  a.var("i").num(1).op(Asm::ASSIGN);
  a.var("i").op(Asm::INC).op(Asm::POP);
  a.var("vx").num(3).op(Asm::VECX).op(Asm::ASSIGN);
  a.var("vy").num(-1).op(Asm::VECY).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  run(m, a);
  CHECK(m.errors().empty());
  CHECK(global(m, "x") == 3);
  CHECK(global(m, "z") == 1);
  CHECK(global(m, "w") == 1);
  CHECK(global(m, "d") == 0);
  CHECK(global(m, "n") == -2);
  CHECK(global(m, "b") == 7);
  CHECK(global(m, "c") == 0);
  CHECK(global(m, "q") == -2);
  CHECK(global(m, "i") == 2);
  CHECK(global(m, "vx") == 1);
  CHECK(global(m, "vy") == 0);  // direction 3 (right): y 0
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
}

static void testCallsAndReturn() {
  gs2::Machine m;
  Asm a;
  // function add(a, b) { return a + b; }
  a.function("add", {"a", "b"});
  a.var("a").var("b").op(Asm::ADD).op(Asm::RET);
  // function onCreated() { r = add(2, 5); s = add("x", 1); }
  a.function("onCreated", {});
  a.var("r").op(Asm::MARKER).num(5).num(2).callName("add").op(Asm::ASSIGN);
  a.var("temp").var("k").op(Asm::MEMBER).num(9).op(Asm::ASSIGN);
  a.var("t").var("temp").var("k").op(Asm::MEMBER).op(Asm::ASSIGN);
  a.op(Asm::MARKER).callName("nosuch").op(Asm::POP);
  a.num(0).op(Asm::RET);
  run(m, a);
  CHECK(global(m, "r") == 7);
  CHECK(global(m, "t") == 9);
  CHECK(m.universe()->child("k") == nullptr);  // temp.k stayed in the frame
  CHECK(m.universe()->child("a") == nullptr);  // parameters are frame locals
  CHECK(hasError(m, "GraalScript: Function npc nosuch not found in script of npc"));

  // Calling into the machine from outside.
  auto v = m.universe()->child("npc");
  auto r = m.callFunction(v, "add", {gs2::Value::number(4), gs2::Value::number(6)});
  CHECK(r.tag == gs2::Value::Tag::Number && r.num == 10);
}

static void testBranchesAndLoops() {
  gs2::Machine m;
  Asm a;
  a.function("onCreated", {});
  // sum = 0; i = 0; while (i < 5) { loopcheck; sum += i; i++; }
  setGlobal(a, "sum", 0);
  setGlobal(a, "i", 0);
  const int top = a.here();
  a.var("i").num(5).op(Asm::LT);
  a.op(Asm::IF);
  const auto exit = a.jumpOperand();
  a.op(Asm::LOOPCHECK);
  a.var("sum").op(Asm::COPY).var("i").op(Asm::ADD).op(Asm::ASSIGN);
  a.var("i").op(Asm::INC).op(Asm::POP);
  a.op(Asm::JMP).jumpOperand(top);
  a.patch(exit, a.here());
  // s = (sum == 10) ? via and/or: s = sum == 10 || 0
  a.var("ok").var("sum").num(10).op(Asm::EQ).op(Asm::OR);
  const auto orEnd = a.jumpOperand();
  a.num(0);
  a.patch(orEnd, a.here());
  a.op(Asm::INLINECOND).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  run(m, a);
  CHECK(m.errors().empty());
  CHECK(global(m, "sum") == 10);
  CHECK(global(m, "ok") == 1);

  // The 10001st loop check stops the script.
  gs2::Machine m2;
  Asm b;
  b.function("onCreated", {});
  setGlobal(b, "n", 0);
  const int loop = b.here();
  b.op(Asm::LOOPCHECK);
  b.var("n").op(Asm::INC).op(Asm::POP);
  b.op(Asm::JMP).jumpOperand(loop);
  run(m2, b);
  CHECK(hasError(m2, "Loop limit exceeded"));
  CHECK(global(m2, "n") == 10000);
}

static void testStringsAndCommands() {
  gs2::Machine m;
  std::vector<std::string> said;
  m.addCommand("echo", "s", [&](gs2::Machine& mm, gs2::Var&, std::vector<gs2::Value>& args) {
    said.push_back(mm.toString(args[0]));
    return gs2::Value::number(0);
  });
  m.addCommand("adventure.secret", "", [&](gs2::Machine&, gs2::Var&, std::vector<gs2::Value>&) {
    said.push_back("secret");
    return gs2::Value::number(1);
  });
  Asm a;
  a.function("onCreated", {});
  a.var("s").str("ab").str("cd").op(Asm::JOIN).op(Asm::ASSIGN);
  a.var("l").var("s").op(Asm::LENGTH).op(Asm::ASSIGN);
  a.var("e").var("s").str("abcd").op(Asm::EQ).op(Asm::ASSIGN);
  a.var("f").str("5").num(5).op(Asm::EQ).op(Asm::ASSIGN);
  a.op(Asm::MARKER).var("s").callName("echo").op(Asm::POP);
  a.op(Asm::MARKER).num(2.5).callName("echo").op(Asm::POP);
  a.op(Asm::MARKER).callName("echo").op(Asm::POP);  // no argument
  a.op(Asm::MARKER).var("adventure").var("secret").op(Asm::MEMBER).op(Asm::CALL).op(Asm::POP);
  a.num(0).op(Asm::RET);
  run(m, a);
  CHECK(globalStr(m, "s") == "abcd");
  CHECK(global(m, "l") == 4);
  CHECK(global(m, "e") == 1);
  CHECK(global(m, "f") == 1);
  CHECK(said.size() == 2 && said[0] == "abcd" && said[1] == "2.5");
  CHECK(hasError(m, "Not enough parameters for echo (1 needed, 0 given)"));
  CHECK(hasError(m, "Unauthorized call of adventure.secret"));

  // A variable whose name starts with "login" may call adventure. commands.
  gs2::Machine m2;
  bool called = false;
  m2.addCommand("adventure.secret", "", [&](gs2::Machine&, gs2::Var&, std::vector<gs2::Value>&) {
    called = true;
    return gs2::Value::number(1);
  });
  run(m2, a, "loginmenu");
  CHECK(called);
}

static void testObjectsAndWith() {
  gs2::Machine m;
  auto box = m.newVar("box");
  box->childOrCreate("size")->setNumber(4);
  Asm a;
  a.function("onCreated", {});
  // this.hp = 3; with (box) { found = size; } ; me = thiso
  a.op(Asm::THIS).var("hp").op(Asm::MEMBER).num(3).op(Asm::ASSIGN);
  a.var("box").op(Asm::TOOBJECT).op(Asm::WITH);
  const auto end = a.jumpOperand();
  a.var("found").var("size").op(Asm::ASSIGN);
  a.op(Asm::ENDWITH);
  a.patch(end, a.here());
  a.var("nobody").op(Asm::TOOBJECT).op(Asm::WITH);
  const auto skip = a.jumpOperand();
  a.var("skipped").num(1).op(Asm::ASSIGN);
  a.op(Asm::ENDWITH);
  a.patch(skip, a.here());
  a.num(0).op(Asm::RET);
  auto npc = run(m, a);
  CHECK(m.errors().empty());
  CHECK(npc->child("hp") && npc->child("hp")->number() == 3);
  CHECK(box->child("found") == nullptr);
  CHECK(global(m, "found") == 4);
  CHECK(m.universe()->child("skipped") == nullptr);
}

static void testSleepAndScheduling() {
  gs2::Machine m;
  Asm a;
  a.function("onCreated", {});
  setGlobal(a, "x", 1);
  a.num(0.1).op(Asm::SLEEP);
  setGlobal(a, "x", 2);
  a.num(0).op(Asm::RET);
  a.function("onPing", {});
  a.var("pings").op(Asm::INC).op(Asm::POP);
  a.num(0).op(Asm::RET);
  auto v = run(m, a);  // clock 0.05: created runs to the sleep
  CHECK(global(m, "x") == 1);
  m.runScripts();      // 0.10
  CHECK(global(m, "x") == 1);
  m.runScripts();      // 0.15: due
  CHECK(global(m, "x") == 2);

  m.scheduleEvent(v, 0.1, "ping");
  m.scheduleEvent(v, 0.1, "Ping");
  m.scheduleEvent(v, 0.2, "other");
  m.runScripts();
  CHECK(m.universe()->child("pings") == nullptr);
  m.runScripts();  // due: queued and run in the same pass
  CHECK(global(m, "pings") == 2);
  m.scheduleEvent(v, 0.1, "ping");
  m.cancelEvents(v, "PING");
  for (int i = 0; i < 5; ++i) m.runScripts();
  CHECK(global(m, "pings") == 2);

  // invokeInitialized drops a queued created and queues initialized.
  gs2::Machine m2;
  Asm b;
  b.function("onCreated", {});
  setGlobal(b, "c", 1);
  b.num(0).op(Asm::RET);
  b.function("onInitialized", {});
  setGlobal(b, "i", 1);
  b.num(0).op(Asm::RET);
  auto w = m2.newVar("w");
  m2.setScript(w, b.bytes());
  m2.invokeInitialized(w);
  m2.runScripts();
  CHECK(m2.universe()->child("c") == nullptr);
  CHECK(global(m2, "i") == 1);
}

static void testLimitsAndRefusals() {
  // Callstack overrun: f() calls itself.
  gs2::Machine m;
  Asm a;
  a.function("f", {});
  a.op(Asm::MARKER).callName("f").op(Asm::POP);
  a.num(0).op(Asm::RET);
  a.function("onCreated", {});
  a.op(Asm::MARKER).callName("f").op(Asm::POP);
  setGlobal(a, "after", 1);
  a.num(0).op(Asm::RET);
  run(m, a);
  CHECK(hasError(m, "Callstack overrun"));
  CHECK(global(m, "after") == 1);

  // Opcode 54 is a 5.0 opcode: unknown on 4.2, refused (not guessed) on 5.0.
  Asm b;
  b.function("onCreated", {});
  b.op(54);
  setGlobal(b, "reached", 1);
  b.num(0).op(Asm::RET);
  gs2::Machine m42(gs2::Profile::Engine42), m50(gs2::Profile::Engine50);
  run(m42, b);
  run(m50, b);
  CHECK(hasError(m42, "unknown opcode 54 for engine 4.2"));
  CHECK(hasError(m50, "opcode 54 (op54) is not implemented"));
  CHECK(m42.universe()->child("reached") == nullptr);

  // waitfor is refused until its stack layout is read.
  Asm c;
  c.function("onCreated", {});
  c.op(Asm::WAITFOR);
  c.num(0).op(Asm::RET);
  gs2::Machine mw;
  run(mw, c);
  CHECK(hasError(mw, "opcode 11 (waitfor) is not implemented"));

  // Underflow stops the script.
  Asm d;
  d.function("onCreated", {});
  d.op(Asm::ADD);
  d.num(0).op(Asm::RET);
  gs2::Machine mu;
  run(mu, d);
  CHECK(hasError(mu, "Stack underflow"));

  // The recorder keeps at most 20 distinct texts.
  gs2::Machine me;
  me.logMissingFunctions = true;
  Asm e;
  e.function("onCreated", {});
  for (int i = 0; i < 30; ++i) e.op(Asm::MARKER).callName("missing" + std::to_string(i)).op(Asm::POP);
  e.op(Asm::MARKER).callName("missing0").op(Asm::POP);
  e.num(0).op(Asm::RET);
  run(me, e);
  CHECK(me.errors().size() == 20);
}

static void testSlots() {
  gs2::Machine m;
  Asm a;
  a.function("onCreated", {});
  a.num(41).op(Asm::SLOTSTORE).operand(3).op(Asm::POP);
  a.op(Asm::SLOTLOAD).operand(3).op(Asm::INC).op(Asm::POP);  // 231: slot 3 += 1
  a.var("r").op(Asm::SLOTLOAD).operand(3).op(Asm::TOFLOAT).op(Asm::ASSIGN);  // 230
  a.num(0).op(Asm::RET);
  run(m, a);
  CHECK(m.errors().empty());
  CHECK(global(m, "r") == 42);
}

static void testDisassemble() {
  Asm a;
  a.function("onCreated", {});
  a.var("x").num(1).op(Asm::ADD).op(Asm::ASSIGN);
  auto r = gs2::load(a.bytes());
  CHECK(r.ok());
  if (!r.ok()) return;
  const std::string d = gs2::disassemble(*r.script);
  CHECK(d.find("function onCreated @0") != std::string::npos);
  CHECK(d.find("imm.add.assign (number) 1") != std::string::npos);
}

static void testObjectsFromNew() {
  // The menus' shape: new T("Name") { field = value; fontColor = {1,2,3}; };
  // then addcontrol(Name), all as the 4.04r2 corpus compiles it.
  gs2::Machine m;
  std::vector<std::string> added;
  std::vector<std::string> parents;
  m.addCommand("addcontrol", "o", [&](gs2::Machine& mm, gs2::Var& self, std::vector<gs2::Value>& args) {
    auto o = mm.toObject(args[0]);
    parents.push_back(self.name());
    added.push_back(o ? o->type() + ":" + o->name() : "null");
    return gs2::Value::number(0);
  });
  Asm a;
  a.function("onCreated", {});
  a.str("MyProfile").op(40).op(Asm::COPY).op(Asm::COPY).op(Asm::COPY);
  a.str("GuiControlProfile").op(Asm::TOSTRING).op(42).op(Asm::ASSIGN).op(Asm::TOOBJECT).op(Asm::WITH);
  const auto end = a.jumpOperand();
  a.var("tab").op(Asm::FALSE_).op(Asm::ASSIGN);
  a.var("fontColor").op(Asm::MARKER).num(255).num(224).num(192).op(37).op(Asm::ASSIGN);
  a.op(Asm::ENDWITH);
  a.patch(end, a.here());
  a.op(Asm::MARKER).op(Asm::SWAP).callName("addcontrol").op(Asm::POP);
  // An unnamed one.
  a.var("unknown_object").op(Asm::COPY).op(Asm::COPY).op(Asm::COPY);
  a.str("GuiTextCtrl").op(Asm::TOSTRING).op(42).op(Asm::ASSIGN).op(Asm::TOOBJECT).op(Asm::WITH);
  const auto end2 = a.jumpOperand();
  a.var("text").str("hi").op(Asm::ASSIGN);
  // a child added inside the parent's with block
  a.str("Inner").op(40).op(Asm::COPY).op(Asm::COPY).op(Asm::COPY);
  a.str("GuiButtonCtrl").op(Asm::TOSTRING).op(42).op(Asm::ASSIGN).op(Asm::TOOBJECT).op(Asm::WITH);
  const auto end3 = a.jumpOperand();
  a.op(Asm::ENDWITH);
  a.patch(end3, a.here());
  a.op(Asm::MARKER).op(Asm::SWAP).callName("addcontrol").op(Asm::POP);
  a.op(Asm::ENDWITH);
  a.patch(end2, a.here());
  a.op(Asm::MARKER).op(Asm::SWAP).callName("addcontrol").op(Asm::POP);
  a.num(0).op(Asm::RET);
  run(m, a);
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(m.errors().empty());
  CHECK(added.size() == 3 && added[0] == "GuiControlProfile:MyProfile" && added[1] == "GuiButtonCtrl:Inner" &&
        added[2] == "GuiTextCtrl:unknown_object");
  CHECK(parents.size() == 3 && parents[0] == "npc" && parents[1] == "unknown_object" && parents[2] == "npc");
  CHECK(m.objects().size() == 3);
  auto p = m.objects()[0];
  CHECK(p->child("tab") && p->child("tab")->number() == 0);
  auto fc = p->child("fontColor");
  CHECK(fc && fc->kind() == gs2::Var::Kind::Array && fc->elements().size() == 3 && fc->elements()[0]->number() == 255 &&
        fc->elements()[2]->number() == 192);
  CHECK(m.universe()->child("tab") == nullptr);
  CHECK(m.objects()[1]->child("text") && m.objects()[1]->child("text")->string() == "hi");
  CHECK(m.objects()[1]->child("Inner") == nullptr);  // the global holds Inner, not the parent
  // The global named after the object links to it.
  CHECK(m.universe()->child("MyProfile") && m.universe()->child("MyProfile")->object() == p);
}

static void testRegistersForeachStrings() {
  gs2::Machine m;
  m.addCommand("files", "", [&](gs2::Machine&, gs2::Var&, std::vector<gs2::Value>&) {
    auto arr = std::make_shared<gs2::Var>();
    arr->setArray(3);
    arr->elements()[0]->setString("a.cs");
    arr->elements()[1]->setString("bb.cs");
    arr->elements()[2]->setString("ccc.cs");
    return gs2::Value::object(arr);
  });
  Asm a;
  a.function("onCreated", {});
  // local registers: var "file" makeprop slotstore 0 pop
  a.var("file").op(47).op(Asm::SLOTSTORE).operand(0).op(Asm::POP);
  a.var("total").num(0).op(Asm::ASSIGN);
  a.var("last").str("").op(Asm::ASSIGN);
  // for (file : files()) { total += length(file); last = file.substring(0, -1); }
  a.op(Asm::SLOTLOAD).operand(0);
  a.op(Asm::MARKER).callName("files").op(Asm::TOOBJECT).num(0);
  const int loop = a.here();
  a.op(163);
  const auto exit = a.jumpOperand();
  a.op(Asm::LOOPCHECK);
  a.var("total").op(Asm::COPY).op(Asm::SLOTLOAD).operand(0).op(Asm::TOSTRING).op(Asm::LENGTH).op(Asm::ADD).op(Asm::ASSIGN);
  a.var("last").op(Asm::SLOTLOAD).operand(0).op(Asm::TOSTRING).num(1).num(-1).op(115).op(Asm::ASSIGN);
  a.op(Asm::INC);
  a.op(Asm::JMP).jumpOperand(loop);
  a.patch(exit, a.here());
  a.op(Asm::POP).op(Asm::POP).op(Asm::POP);
  // case-insensitive string equality, and the 0.0001 band
  a.var("ci").str("Hello").str("hELLO").op(Asm::EQ).op(Asm::ASSIGN);
  a.var("band").num(1).num(1.00001).op(Asm::EQ).op(Asm::ASSIGN);
  a.var("sorted").str("apple").str("Banana").op(Asm::LT).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  run(m, a);
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(m.errors().empty());
  CHECK(global(m, "total") == 15);
  CHECK(globalStr(m, "last") == "cc.cs");
  CHECK(globalStr(m, "file") == "ccc.cs");
  CHECK(global(m, "ci") == 1);
  CHECK(global(m, "band") == 1);
  CHECK(global(m, "sorted") == 1);
}

static void testEngine50And600() {
  // 121 adds numbers or appends strings; 48 builds an object from pairs;
  // 49 an array from numbers.
  gs2::Machine m(gs2::Profile::Engine50);
  Asm a;
  a.function("onCreated", {});
  a.var("n").num(2).num(3).op(121).op(Asm::ASSIGN);
  a.var("s").str("a").num(3).op(121).op(Asm::ASSIGN);
  a.var("o").num(0).str("x").num(7).str("y").str("why").num(2).op(48).op(Asm::ASSIGN);
  a.var("arr").num(4).num(5).num(2).op(49).op(Asm::ASSIGN);
  a.num(0).op(Asm::RET);
  run(m, a);
  for (const auto& e : m.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(global(m, "n") == 5);
  CHECK(globalStr(m, "s") == "a3");
  auto o = m.universe()->child("o");
  auto ob = o ? o->object() : nullptr;
  CHECK(ob && ob->child("x") && ob->child("x")->number() == 7 && ob->child("y")->string() == "why");
  auto arr = m.universe()->child("arr");
  CHECK(arr && arr->kind() == gs2::Var::Kind::Array && arr->elements().size() == 2 &&
        arr->elements()[0]->number() == 5 && arr->elements()[1]->number() == 4);

  // The 6.00 folds load only on 6.00 and run like the pairs they replace.
  Asm b;
  b.function("onCreated", {});
  b.var("box").op(Asm::TOOBJECT).op(Asm::POP);
  b.var("box").var("w").op(Asm::MEMBER).num(9).op(Asm::ASSIGN);       // 234
  b.var("r").var("box").var("w").op(Asm::MEMBER).op(Asm::TOFLOAT).op(Asm::ASSIGN);  // 236
  b.var("q").op(47).op(Asm::SLOTSTORE).operand(5).op(Asm::POP);        // 242
  b.num(0).op(Asm::RET);
  auto r42 = gs2::load(b.bytes(), gs2::Profile::Engine42);
  auto r600 = gs2::load(b.bytes(), gs2::Profile::Engine600);
  CHECK(r42.ok() && r600.ok());
  if (r42.ok() && r600.ok()) {
    CHECK(r600.script->fusedPairs > r42.script->fusedPairs);
    bool has236 = false, has242 = false;
    for (const auto& in : r600.script->code) {
      has236 |= in.op == 236;
      has242 |= in.op == 242;
    }
    CHECK(has236 && has242);
  }
  gs2::Machine m6(gs2::Profile::Engine600);
  auto box = m6.newVar("box");
  box->setAcceptsAllProperties(true);
  run(m6, b);
  for (const auto& e : m6.errors()) std::fprintf(stderr, "  %s\n", e.c_str());
  CHECK(m6.errors().empty());
  CHECK(global(m6, "r") == 9);
}

static std::string deflate(const std::string& in) {
  uLongf n = compressBound(static_cast<uLong>(in.size()));
  std::string out(n, '\0');
  compress(reinterpret_cast<Bytef*>(&out[0]), &n, reinterpret_cast<const Bytef*>(in.data()), static_cast<uLong>(in.size()));
  out.resize(n);
  return out;
}

static void testStartScripts() {
  Asm profiles;
  profiles.function("onCreated", {});
  profiles.op(Asm::MARKER).callName("addProfiles").op(Asm::POP).num(0).op(Asm::RET);
  profiles.function("addProfiles", {});
  profiles.var("made").num(1).op(Asm::ASSIGN).num(0).op(Asm::RET);
  Asm keys;
  keys.function("onCreated", {});
  keys.str("moveMap2D").str("ActionMap").op(Asm::POP).op(Asm::POP).num(0).op(Asm::RET);
  Asm other;
  other.function("onWeaponFired", {});
  other.num(0).op(Asm::RET);
  // A program image: junk, the three streams, a stream that is not a
  // script, more junk.
  std::string image = std::string(100, 'x') + deflate(profiles.bytes()) + std::string(7, '\x78') +
                      deflate(keys.bytes()) + "pad" + deflate(other.bytes()) + deflate("plain text") +
                      std::string(50, 'y');
  auto found = gs2::loadStartScripts(image, gs2::Profile::Engine42);
  CHECK(found.size() == 3);
  if (found.size() == 3) {
    CHECK(found[0].name == "StartScript_Profiles");
    CHECK(found[1].name == "StartScript_MoveMap2D");
    CHECK(found[2].name.empty());
  }
  gs2::Machine m;
  gs2::attachStartScripts(m, found);
  m.runScripts();
  CHECK(m.universe()->child("StartScript_Profiles") != nullptr);
  CHECK(global(m, "made") == 1);
  CHECK(m.objects().empty());
}

static void testEngineCommands() {
  CHECK(gs2::extractFileBase("languages3D/languageenglish.cs") == "languageenglish");
  CHECK(gs2::extractFileBase("a\\b.c.png") == "b.c");
  CHECK(gs2::extractFilePath("levels/x/y.nw") == "levels/x/");
  CHECK(gs2::extractFilePath("y.nw").empty());

  gs2::Machine m;
  std::vector<std::string> log;
  gs2::EngineHost host;
  host.log = [&](const std::string& s) { log.push_back(s); };
  gs2::addEngineCommands(m, host);
  Asm a;
  a.function("onCreated", {});
  a.op(Asm::MARKER).num(0.1).callName("setTimer").op(Asm::POP);
  a.op(Asm::MARKER).str("hi").callName("echo").op(Asm::POP);
  a.op(Asm::MARKER).str("onPicked").str("onPicked").str("picker").callName("catchevent").op(Asm::POP);
  a.op(Asm::MARKER).str("Hello").callName("lowercase").var("lc").op(Asm::SWAP).op(Asm::ASSIGN);
  a.op(Asm::MARKER).callName("openURL").op(Asm::POP);  // the host gave no openUrl
  a.num(0).op(Asm::RET);
  a.function("onTimeout", {});
  a.var("timeouts").op(Asm::INC).op(Asm::POP).num(0).op(Asm::RET);
  a.function("onPicked", {});
  a.var("picked").op(Asm::INC).op(Asm::POP).num(0).op(Asm::RET);
  Asm b;  // the object whose event is caught
  b.function("onCreated", {});
  b.num(0).op(Asm::RET);
  auto picker = m.newVar("picker");
  m.setScript(picker, b.bytes());
  run(m, a, "menu");
  CHECK(log.size() == 1 && log[0] == "hi");
  CHECK(globalStr(m, "lc") == "hello");
  CHECK(hasError(m, "openURL not found"));
  m.runScripts();
  m.runScripts();
  CHECK(global(m, "timeouts") == 1);
  m.runScripts();
  CHECK(global(m, "timeouts") == 1);  // one event, not repeating
  m.queueEvent(picker, "picked");
  m.runScripts();
  CHECK(global(m, "picked") == 1);
}

int main() {
  testStartScripts();
  testEngineCommands();
  testObjectsFromNew();
  testRegistersForeachStrings();
  testEngine50And600();
  testLoader();
  testFusion();
  testProfiles();
  testArithmeticAndAssign();
  testCallsAndReturn();
  testBranchesAndLoops();
  testStringsAndCommands();
  testObjectsAndWith();
  testSleepAndScheduling();
  testLimitsAndRefusals();
  testSlots();
  testDisassemble();
  if (failures) {
    std::fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  std::printf("gs2 tests passed\n");
  return 0;
}
