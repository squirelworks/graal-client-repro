// Compiler checks. Every source script and expected word list here is
// hand-written; no original script or compiled file is included. Expected
// words are written out from the opcode table, not produced by the compiler.

#include "../compile.hpp"
#include "../../instructions.hpp"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

using namespace Torque;
using Words = std::vector<std::uint32_t>;

static int failures = 0;

#define CHECK(cond)                                                          \
  do {                                                                       \
    if (!(cond)) {                                                           \
      std::cerr << __FILE__ << ':' << __LINE__ << ": check failed: " #cond "\n"; \
      ++failures;                                                            \
    }                                                                        \
  } while (0)

static DsoBlock compile_ok(const std::string& src) {
  DsoBlock b;
  CompileError e;
  if (!compile_script(src, b, e)) {
    std::cerr << "unexpected compile error line " << e.line << ": " << e.message << '\n';
    ++failures;
  }
  return b;
}

static void check_words(const DsoBlock& b, const Words& expected, int line) {
  if (b.code == expected) return;
  std::cerr << "line " << line << ": code differs\n  got:     ";
  for (auto w : b.code) std::cerr << w << ' ';
  std::cerr << "\n  wanted:  ";
  for (auto w : expected) std::cerr << w << ' ';
  std::cerr << '\n';
  ++failures;
}

static std::string strings(std::initializer_list<const char*> list) {
  std::string out;
  for (const char* s : list) {
    out += s;
    out += '\0';
  }
  return out;
}

// Every compiled block must decode with the published operand widths and
// survive the DSO writer and the shared reader unchanged.
static void check_round_trip(const DsoBlock& b, FloatOrder order) {
  std::vector<DsoInstruction> ins;
  InstructionError ie;
  CHECK(decode_instructions(b.code, ins, ie));
  DsoBlock back;
  DsoError de;
  CHECK(load_dso(write_dso(b, order), order, back, de));
  CHECK(back.global_strings == b.global_strings);
  CHECK(back.function_strings == b.function_strings);
  CHECK(back.global_floats == b.global_floats);
  CHECK(back.function_floats == b.function_floats);
  CHECK(back.code == b.code);
  CHECK(back.lines.size() == b.lines.size());
  CHECK(back.identifiers.size() == b.identifiers.size());
  for (std::size_t k = 0; k < back.identifiers.size() && k < b.identifiers.size(); ++k) {
    CHECK(back.identifiers[k].string_offset == b.identifiers[k].string_offset);
    CHECK(back.identifiers[k].unnamed == b.identifiers[k].unnamed);
    CHECK(back.identifiers[k].uses == b.identifiers[k].uses);
  }
}

static void global_assignments() {
  // A string, an integer and a float value, as in an exported prefs file.
  const DsoBlock b = compile_ok("$a = \"1\";\n$b = 2;\n$c = 0.5;\n");
  check_words(b, {68, 0, 37, 0, 45, 58,  // LOADIMMED_STR "1"; SETCURVAR_CREATE $a; SAVEVAR_STR; STR_TO_NONE
                  65, 2, 37, 0, 43, 64,  // LOADIMMED_UINT 2; ...; SAVEVAR_UINT; UINT_TO_NONE
                  66, 0, 37, 0, 44, 61,  // LOADIMMED_FLT [0]; ...; SAVEVAR_FLT; FLT_TO_NONE
                  13},
              __LINE__);
  // Values enter the table before the variable they are stored in.
  CHECK(b.global_strings == strings({"1", "$a", "$b", "$c"}));
  CHECK(b.global_floats == std::vector<double>{0.5});
  CHECK(b.function_strings.empty());
  CHECK(b.lines.empty());
  // Identifier groups: newest first.
  CHECK(b.identifiers.size() == 3);
  if (b.identifiers.size() == 3) {
    CHECK(b.identifiers[0].name == "$c" && b.identifiers[0].uses == Words{15});
    CHECK(b.identifiers[1].name == "$b" && b.identifiers[1].uses == Words{9});
    CHECK(b.identifiers[2].name == "$a" && b.identifiers[2].string_offset == 2 &&
          b.identifiers[2].uses == Words{3});
  }
  check_round_trip(b, FloatOrder::little);
  check_round_trip(b, FloatOrder::big);
}

static void calls_and_objects() {
  const DsoBlock b = compile_ok(
      "map.clear();\n"
      "new Thing(map);\n"
      "map.add(key, \"k\", act);\n"
      "map.add(key, \"j\", act2);\n");
  check_words(b, {81, 69, 0, 80, 71, 0, 0, 1, 58,             // PUSH_FRAME map PUSH CALLFUNC clear 0 1; STR_TO_NONE
                  65, 0, 81, 69, 0, 80, 69, 0, 80, 1, 0, 0, 26, // UINT 0; PUSH_FRAME Thing map; CREATE_OBJECT "" 0 ->26
                  4, 1, 5, 1, 64,                              // ADD_OBJECT 1; END_OBJECT 1; UINT_TO_NONE
                  81, 69, 0, 80, 69, 0, 80, 68, 25, 80, 69, 0, 80, 71, 0, 0, 1, 58,  // "k" at 25
                  81, 69, 0, 80, 69, 0, 80, 68, 31, 80, 69, 0, 80, 71, 0, 0, 1, 58,  // "j" at 31
                  13},
              __LINE__);
  // A call's own name enters the table before its arguments; an object's
  // (empty) parent name before its class.
  CHECK(b.global_strings ==
        strings({"clear", "map", "", "Thing", "add", "key", "k", "act", "j", "act2"}));
  // The first use leads each group; later uses follow newest first.
  bool found = false;
  for (const auto& id : b.identifiers) {
    if (id.name == "map") {
      found = true;
      CHECK((id.uses == Words{2, 47, 29, 16}));
    }
  }
  CHECK(found);
  CHECK(b.identifiers.front().name == "act2");
  check_round_trip(b, FloatOrder::little);
}

static void function_body() {
  const char* src =
      "function f(%a, %b) {\n"
      "  if (%a $= \"\")\n"
      "    return;\n"
      "  %b = %a @ \"x\" SPC 2.5;\n"
      "  for (%i = 0; %i < 3; %i++)\n"
      "    g(%i);\n"
      "}\n";
  const DsoBlock b = compile_ok(src);
  const Words expected = {
      0, 0, 0, 0, 1, 76, 2, 0, 0,             // FUNC_DECL f 0 0 hasBody end=76 argc=2 %a %b
      36, 0, 42, 76, 68, 0, 79, 7, 19,        // %a $= "" -> JMPIFNOT 19
      13,                                     // return
      36, 0, 42, 73, 68, 1, 77, 74, 32, 68, 3, 77,  // ((%a @ "x") SPC "2.5")
      37, 0, 45, 58,                          // %b = ...
      65, 0, 37, 0, 43, 64,                   // %i = 0
      66, 0, 36, 0, 41, 17, 7, 75,            // 3.0, %i (right operand first); CMPLT; JMPIFNOT 75
      81, 36, 0, 42, 80, 70, 0, 0, 0, 58,     // g(%i)
      66, 1, 37, 0, 41, 31, 44, 61,           // %i++
      66, 0, 36, 0, 41, 17, 9, 49,            // test again, JMPIF top
      13,                                     // implicit return
      13};
  check_words(b, expected, __LINE__);
  CHECK(b.function_strings == strings({"", "x", "2.5"}));
  CHECK((b.function_floats == std::vector<double>{3.0, 1.0}));
  CHECK(b.global_floats.empty());
  // One line pair per statement inside a function, nested ones included;
  // the loop's step is part of the for statement.
  CHECK(b.lines.size() == 5);
  if (b.lines.size() == 5) {
    CHECK(b.lines[0].line == 2 && b.lines[0].ip == 9);
    CHECK(b.lines[1].line == 3 && b.lines[1].ip == 18);
    CHECK(b.lines[2].line == 4 && b.lines[2].ip == 19);
    CHECK(b.lines[3].line == 5 && b.lines[3].ip == 35);
    CHECK(b.lines[4].line == 6 && b.lines[4].ip == 49);
  }
  check_round_trip(b, FloatOrder::little);
}

static void parameters() {
  // %b is unused and named nowhere: it points one past the table end.
  // %c is unused here but named later in the file: it keeps the name.
  const DsoBlock b = compile_ok(
      "function f(%a, %b, %c) { echo(%a); }\n"
      "function g(%c) { echo(%c); }\n");
  bool sentinel = false, named = false;
  for (const auto& id : b.identifiers) {
    if (id.unnamed) {
      sentinel = true;
      CHECK(id.string_offset == b.global_strings.size());
      CHECK(id.uses == Words{8});
    }
    if (id.name == "%c") {
      named = true;
      CHECK(id.uses.size() == 3 && id.uses[0] == 9);
    }
  }
  CHECK(sentinel);
  CHECK(named);
  check_round_trip(b, FloatOrder::little);
}

static void fields_and_arrays() {
  const DsoBlock b = compile_ok(
      "o.list[o.count] = %v;\n"
      "%x = $m[%k, 1];\n"
      "new Gui(w) { text = \"t\"; size = 3; new Gui() { x = 1; }; };\n");
  check_words(b, {36, 0, 42, 73,                            // %v; ADVANCE_STR
                  69, 0, 46, 48, 0, 52, 73,                 // index o.count; ADVANCE_STR
                  69, 0, 46, 48, 0, 78, 49, 78, 55, 58,     // o SETCUROBJECT list; TERM; FIELD_ARRAY; TERM; SAVEFIELD_STR
                  69, 0, 73, 36, 0, 42, 75, 68, 22, 77, 77, 38, 42,  // $m[%k, 1]; "1" at 22
                  37, 0, 45, 58,
                  65, 0, 81, 69, 0, 80, 69, 0, 80, 1, 0, 0, 93,  // fails to 93
                  68, 39, 73, 47, 48, 0, 78, 55, 58,        // text = "t" (at 39)
                  65, 3, 47, 48, 0, 53, 64,                 // size = 3 (no string stack)
                  4, 1,
                  81, 69, 0, 80, 68, 27, 80, 1, 0, 0, 91,   // child: name "" (at 27), fails to 91
                  65, 1, 47, 48, 0, 53, 64, 4, 0, 5, 0,
                  5, 1, 64, 13},
              __LINE__);
  CHECK(b.global_strings.find(std::string("1\0", 2)) != std::string::npos);
  check_round_trip(b, FloatOrder::little);
}

static void operators() {
  const DsoBlock b = compile_ok(
      "$r = !f() || ($a & 3) == -1;\n"
      "$s = $a ? 1 : 2;\n"
      "$t += 2;\n"
      "$u = 300;\n");
  check_words(b, {81, 70, 0, 0, 0, 57, 25,           // !f(): float NOTF
                  11, 20,                            // || -> JMPIF_NP 20
                  66, 0, 35,                         // -1 as float: 1.0 NEG
                  65, 3, 36, 0, 40, 22, 62,          // ($a & 3) as uint, then UINT_TO_FLT
                  14,                                // CMPEQ
                  37, 0, 43, 64,
                  36, 0, 41, 6, 33, 65, 1, 12, 35, 65, 2,  // $a (float test) ? 1 : 2
                  37, 0, 43, 64,
                  66, 1, 37, 0, 41, 31, 44, 61,      // $t += 2
                  65, 300, 37, 0, 43, 64,
                  13},
              __LINE__);
  // 300 needs the escaped form in the file.
  const auto bytes = write_dso(b, FloatOrder::little);
  bool escaped = false;
  for (std::size_t k = 0; k + 4 < bytes.size(); ++k)
    if (bytes[k] == 0xFF && bytes[k + 1] == 0x2C && bytes[k + 2] == 0x01 && bytes[k + 3] == 0 &&
        bytes[k + 4] == 0)
      escaped = true;
  CHECK(escaped);
  check_round_trip(b, FloatOrder::little);
}

static void control_flow() {
  const DsoBlock b = compile_ok(
      "function f(%x) {\n"
      "  while (%x) { if (%x == 2) break; %x--; continue; }\n"
      "  do { %x++; } while (%x < 5);\n"
      "  switch$ (%x) { case \"a\" or \"b\": g(); default: h(); }\n"
      "}\n");
  CHECK(!b.code.empty());
  std::vector<DsoInstruction> ins;
  InstructionError ie;
  CHECK(decode_instructions(b.code, ins, ie));
  // The switch$ becomes two string compares joined by JMPIF_NP.
  int compares = 0, np = 0;
  for (const auto& i : ins) {
    if (i.opcode == 79) ++compares;
    if (i.opcode == 11) ++np;
  }
  CHECK(compares == 2);
  CHECK(np == 1);
  check_round_trip(b, FloatOrder::little);
}

static void packages_and_tags() {
  const DsoBlock b = compile_ok(
      "package P { function A::m(%this) { Parent::m(%this); } };\n"
      "send('Tag');\n");
  CHECK(b.code.size() > 9);
  if (b.code.size() > 9) {
    CHECK(b.code[0] == 0);
    CHECK(b.code[4] == 1);
  }
  std::vector<std::string> names;
  for (const auto& id : b.identifiers) names.push_back(id.name);
  CHECK(std::find(names.begin(), names.end(), "P") != names.end());
  CHECK(std::find(names.begin(), names.end(), "Parent") != names.end());
  bool tag = false;
  for (std::size_t k = 0; k + 1 < b.code.size(); ++k)
    if (b.code[k] == 67 && b.global_strings.compare(b.code[k + 1], 4, std::string("Tag\0", 4)) == 0)
      tag = true;
  CHECK(tag);
  check_round_trip(b, FloatOrder::little);
}

static void errors() {
  struct Case { const char* src; int line; };
  const Case cases[] = {
      {"$a = ;\n", 1},
      {"\n\nfoo(\n", 4},
      {"function f() { function g() {} }\n", 1},
      {"break;\n", 1},
      {"$a = \"open\n", 1},
      {"\n5 = 3;\n", 2},
      {"x::y;\n", 1},
  };
  {
    // Nesting is bounded; 100000 parentheses or minus signs fail cleanly.
    CompileError e;
    DsoBlock b;
    CHECK(!compile_script("$a = " + std::string(100000, '(') + "1;", b, e));
    CHECK(!compile_script("$a = " + std::string(100000, '-') + "1;", b, e));
    CHECK(!compile_script("if (1) " + std::string(100000, '{'), b, e));
    std::string chain = "$a = 1";
    for (int k = 0; k < 100000; ++k) chain += " + 1";
    CHECK(!compile_script(chain + ";", b, e));
    std::string calls = "a";
    for (int k = 0; k < 100000; ++k) calls += ".b()";
    CHECK(!compile_script(calls + ";", b, e));
    CHECK(compile_script("$a = " + std::string(100, '(') + "1" + std::string(100, ')') + ";", b, e));
  }
  for (const auto& c : cases) {
    DsoBlock b;
    b.code = {99};
    CompileError e;
    CHECK(!compile_script(c.src, b, e));
    CHECK(e.line == c.line);
    CHECK(!e.message.empty());
    CHECK(b.code == Words{99});  // output unchanged on failure
  }
}

// Optional: byte-for-byte comparison against .dso files the real client
// wrote next to its own plain scripts. Set TORQUE_ORACLE_DIR to a folder
// holding NAME.cs and NAME.cs.dso pairs (not distributed; skipped if unset).
static void external_oracle() {
  const char* dir = std::getenv("TORQUE_ORACLE_DIR");
  if (!dir) {
    std::cout << "external oracle: skipped (TORQUE_ORACLE_DIR unset)\n";
    return;
  }
  int compared = 0;
  for (const char* name : {"prefs.cs", "config.cs"}) {
    const std::string base = std::string(dir) + "/" + name;
    std::ifstream src(base, std::ios::binary), dso(base + ".dso", std::ios::binary);
    if (!src || !dso) continue;
    const std::string text((std::istreambuf_iterator<char>(src)), std::istreambuf_iterator<char>());
    const std::vector<std::uint8_t> want((std::istreambuf_iterator<char>(dso)),
                                         std::istreambuf_iterator<char>());
    const auto got = write_dso(compile_ok(text), FloatOrder::little);
    if (got != want) {
      std::cerr << name << ": compiled bytes differ from the client's .dso\n";
      ++failures;
    }
    ++compared;
  }
  std::cout << "external oracle: " << compared << " file(s) compared\n";
}

int main() {
  global_assignments();
  calls_and_objects();
  function_body();
  parameters();
  fields_and_arrays();
  operators();
  control_flow();
  packages_and_tags();
  errors();
  external_oracle();
  if (failures) {
    std::cerr << failures << " check(s) failed\n";
    return 1;
  }
  std::cout << "compiler tests passed\n";
  return 0;
}
