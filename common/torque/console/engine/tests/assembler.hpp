#pragma once

// A small hand assembler for test code blocks. It writes opcode words and
// table entries directly, so every test states the exact instruction stream
// it runs; nothing here is produced by a compiler or by the engine.

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "../../dso.hpp"

namespace Asm {

enum : std::uint32_t {
  FUNC_DECL = 0, CREATE_OBJECT = 1, ADD_OBJECT = 4, END_OBJECT = 5, JMPIFFNOT = 6,
  JMPIFNOT = 7, JMPIFF = 8, JMPIF = 9, JMPIFNOT_NP = 10, JMPIF_NP = 11, JMP = 12,
  RETURN = 13, CMPEQ = 14, CMPGR = 15, CMPGE = 16, CMPLT = 17, CMPLE = 18, CMPNE = 19,
  XOR = 20, MOD = 21, BITAND = 22, BITOR = 23, NOT = 24, NOTF = 25, ONESCOMPLEMENT = 26,
  SHR = 27, SHL = 28, AND = 29, OR = 30, ADD = 31, SUB = 32, MUL = 33, DIV = 34, NEG = 35,
  SETCURVAR = 36, SETCURVAR_CREATE = 37, SETCURVAR_ARRAY = 38, SETCURVAR_ARRAY_CREATE = 39,
  LOADVAR_UINT = 40, LOADVAR_FLT = 41, LOADVAR_STR = 42, SAVEVAR_UINT = 43,
  SAVEVAR_FLT = 44, SAVEVAR_STR = 45, SETCUROBJECT = 46, SETCUROBJECT_NEW = 47,
  SETCURFIELD = 48, SETCURFIELD_ARRAY = 49, LOADFIELD_UINT = 50, LOADFIELD_FLT = 51,
  LOADFIELD_STR = 52, SAVEFIELD_UINT = 53, SAVEFIELD_FLT = 54, SAVEFIELD_STR = 55,
  STR_TO_UINT = 56, STR_TO_FLT = 57, STR_TO_NONE = 58, FLT_TO_UINT = 59, FLT_TO_STR = 60,
  FLT_TO_NONE = 61, UINT_TO_FLT = 62, UINT_TO_STR = 63, UINT_TO_NONE = 64,
  LOADIMMED_UINT = 65, LOADIMMED_FLT = 66, TAG_TO_STR = 67, LOADIMMED_STR = 68,
  LOADIMMED_IDENT = 69, CALLFUNC_RESOLVE = 70, CALLFUNC = 71, ADVANCE_STR = 73,
  ADVANCE_STR_APPENDCHAR = 74, ADVANCE_STR_COMMA = 75, ADVANCE_STR_NUL = 76,
  REWIND_STR = 77, TERMINATE_REWIND_STR = 78, COMPARE_STR = 79, PUSH = 80,
  PUSH_FRAME = 81, BREAK = 82
};

class Block {
 public:
  Torque::DsoBlock b;
  bool in_function = false;  // which tables string()/number() write

  std::uint32_t here() const { return static_cast<std::uint32_t>(b.code.size()); }
  void w(std::uint32_t word) { b.code.push_back(word); }
  void patch(std::uint32_t at, std::uint32_t word) { b.code.at(at) = word; }

  // An identifier operand: a global string patched in through the table.
  void ident(const std::string& name) {
    if (name.empty()) { w(0); return; }
    const auto off = add(b.global_strings, name);
    for (auto& id : b.identifiers)
      if (!id.unnamed && id.string_offset == off) { id.uses.push_back(here()); w(0); return; }
    b.identifiers.push_back({off, false, name, {here()}});
    w(0);
  }
  // An unused-argument slot: an identifier at or past the table end.
  void unnamed(std::uint32_t past_end) {
    b.identifiers.push_back({static_cast<std::uint32_t>(b.global_strings.size()) + past_end, true, "", {here()}});
    w(0);
  }
  std::uint32_t string(const std::string& s) {
    return add(in_function ? b.function_strings : b.global_strings, s);
  }
  std::uint32_t number(double v) {
    auto& t = in_function ? b.function_floats : b.global_floats;
    t.push_back(v);
    return static_cast<std::uint32_t>(t.size() - 1);
  }

  // Sequences in the shapes the shipped 3.04 scripts use.
  void str(const std::string& s) { w(LOADIMMED_STR); w(string(s)); }
  void flt(double v) { w(LOADIMMED_FLT); w(number(v)); }
  void uint(std::uint32_t v) { w(LOADIMMED_UINT); w(v); }
  void id(const std::string& s) { w(LOADIMMED_IDENT); ident(s); }
  void call(const std::string& fn, const std::vector<std::string>& literal_args,
            std::uint32_t type = 0, const std::string& ns = "") {
    w(PUSH_FRAME);
    for (const auto& a : literal_args) { str(a); w(PUSH); }
    callfunc(fn, type, ns);
  }
  void callfunc(const std::string& fn, std::uint32_t type = 0, const std::string& ns = "") {
    w(CALLFUNC); ident(fn); ident(ns); w(type);
  }
  void set_global_str(const std::string& var, const std::string& value) {
    str(value); w(SETCURVAR_CREATE); ident(var); w(SAVEVAR_STR); w(STR_TO_NONE);
  }
  // FUNC_DECL header; returns the word to patch with the end ip.
  std::uint32_t function(const std::string& name, const std::string& ns, const std::string& pkg,
                         const std::vector<std::string>& args) {
    w(FUNC_DECL); ident(name); ident(ns); ident(pkg); w(1);
    const auto end = here(); w(0);
    w(static_cast<std::uint32_t>(args.size()));
    for (const auto& a : args) {
      if (a.empty()) unnamed(0);
      else ident(a);
    }
    in_function = true;
    return end;
  }
  void end_function(std::uint32_t end_word) {
    w(RETURN);
    patch(end_word, here());
    in_function = false;
  }

  // DSO v33 bytes, written from the documented layout (little-endian).
  std::vector<std::uint8_t> bytes() const {
    std::vector<std::uint8_t> out;
    auto u32 = [&](std::uint32_t v) { for (int i = 0; i < 4; ++i) out.push_back((v >> (8 * i)) & 255); };
    auto f64 = [&](double d) {
      std::uint64_t v;
      std::memcpy(&v, &d, 8);
      for (int i = 0; i < 8; ++i) out.push_back((v >> (8 * i)) & 255);
    };
    u32(33);
    u32(static_cast<std::uint32_t>(b.global_strings.size()));
    out.insert(out.end(), b.global_strings.begin(), b.global_strings.end());
    u32(static_cast<std::uint32_t>(b.global_floats.size()));
    for (double d : b.global_floats) f64(d);
    u32(static_cast<std::uint32_t>(b.function_strings.size()));
    out.insert(out.end(), b.function_strings.begin(), b.function_strings.end());
    u32(static_cast<std::uint32_t>(b.function_floats.size()));
    for (double d : b.function_floats) f64(d);
    u32(static_cast<std::uint32_t>(b.code.size()));
    u32(static_cast<std::uint32_t>(b.lines.size()));
    for (auto word : b.code) {
      if (word < 0xff) out.push_back(static_cast<std::uint8_t>(word));
      else { out.push_back(0xff); u32(word); }
    }
    for (const auto& l : b.lines) { u32(l.line); u32(l.ip); }
    u32(static_cast<std::uint32_t>(b.identifiers.size()));
    for (const auto& id : b.identifiers) {
      u32(id.string_offset);
      u32(static_cast<std::uint32_t>(id.uses.size()));
      for (auto u : id.uses) u32(u);
    }
    return out;
  }

 private:
  static std::uint32_t add(std::string& table, const std::string& s) {
    // Reuse an existing entry so identical strings share an offset.
    std::size_t pos = 0;
    while (pos < table.size()) {
      auto end = table.find('\0', pos);
      if (table.compare(pos, end - pos, s) == 0 && end - pos == s.size()) return static_cast<std::uint32_t>(pos);
      pos = end + 1;
    }
    const auto off = static_cast<std::uint32_t>(table.size());
    table += s;
    table.push_back('\0');
    return off;
  }
};

} // namespace Asm
