#pragma once

// A hand assembler for test scripts. Each test writes the exact opcode
// stream it runs; nothing here comes from a compiler.

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace gs2asm {

class Asm {
 public:
  // Opcode numbers used by the tests (the engines' numbers).
  enum : int {
    JMP = 1, JMPTRUE = 2, OR = 3, IF = 4, AND = 5, CALL = 6, RET = 7, SLEEP = 8,
    LOOPCHECK = 9, SAVESTACK = 10, NUMBER = 20, STRING = 21, VAR = 22, MARKER = 23,
    TRUE_ = 24, FALSE_ = 25, COPY = 30, SWAP = 31, POP = 32, TOFLOAT = 33, TOSTRING = 34,
    MEMBER = 35, TOOBJECT = 36, INLINECOND = 44, SLOTSTORE = 45, SLOTLOAD = 46,
    ASSIGN = 50, PARAMSEND = 51, INC = 52, DEC = 53, ADD = 60, SUB = 61, MUL = 62,
    DIV = 63, MOD = 64, NOT = 68, NEG = 69, EQ = 70, NEQ = 71, LT = 72, GT = 73,
    BITOR = 76, INT = 85, VECX = 97, VECY = 98, JOIN = 113, LENGTH = 111, SIZE = 130,
    ARRAYGET = 131, WITH = 150, ENDWITH = 151, THIS = 180, THISO = 181, TEMP = 189,
    WAITFOR = 11, OP48 = 48
  };

  std::uint32_t mask = 0;

  // Instruction index of the next opcode.
  int here() const { return count_; }

  Asm& op(int o) { code_.push_back(static_cast<std::uint8_t>(o)); ++count_; return *this; }

  // An integer operand in the smallest marker, or a decimal for fractions.
  Asm& operand(double d) {
    const auto i = static_cast<long long>(d);
    if (static_cast<double>(i) != d) {
      code_.push_back(0xF6);
      const std::string t = std::to_string(d);
      code_.insert(code_.end(), t.begin(), t.end());
      code_.push_back(0);
    } else if (i >= -128 && i <= 127) {
      code_.push_back(0xF3);
      code_.push_back(static_cast<std::uint8_t>(i));
    } else if (i >= -32768 && i <= 32767) {
      code_.push_back(0xF4);
      code_.push_back(static_cast<std::uint8_t>((i >> 8) & 0xFF));
      code_.push_back(static_cast<std::uint8_t>(i & 0xFF));
    } else {
      code_.push_back(0xF5);
      for (int s = 24; s >= 0; s -= 8) code_.push_back(static_cast<std::uint8_t>((i >> s) & 0xFF));
    }
    return *this;
  }

  // A jump operand always as F4, patchable later.
  std::size_t jumpOperand(int target = 0) {
    code_.push_back(0xF4);
    const std::size_t at = code_.size();
    code_.push_back(static_cast<std::uint8_t>((target >> 8) & 0xFF));
    code_.push_back(static_cast<std::uint8_t>(target & 0xFF));
    return at;
  }
  void patch(std::size_t at, int target) {
    code_[at] = static_cast<std::uint8_t>((target >> 8) & 0xFF);
    code_[at + 1] = static_cast<std::uint8_t>(target & 0xFF);
  }

  Asm& strOperand(const std::string& s) {
    const std::size_t i = intern(s);
    if (i < 256) {
      code_.push_back(0xF0);
      code_.push_back(static_cast<std::uint8_t>(i));
    } else {
      code_.push_back(0xF1);
      code_.push_back(static_cast<std::uint8_t>(i >> 8));
      code_.push_back(static_cast<std::uint8_t>(i & 0xFF));
    }
    return *this;
  }

  Asm& num(double d) { return op(NUMBER).operand(d); }
  Asm& str(const std::string& s) { return op(STRING).strOperand(s); }
  Asm& var(const std::string& s) { return op(VAR).strOperand(s); }

  // `name(args)` as a statement: marker, arguments in reverse, name, call.
  // `pushArgs` pushes the arguments in source order; the helper reverses
  // nothing itself, so the test states the order it emits.
  Asm& callName(const std::string& name) { return var(name).op(CALL); }

  // A function: entry at the current index, parameters bound, stack saved.
  Asm& function(const std::string& name, const std::vector<std::string>& params) {
    functions_.push_back({static_cast<std::uint32_t>(count_), name});
    op(MARKER);
    for (auto it = params.rbegin(); it != params.rend(); ++it) var(*it);
    op(PARAMSEND).op(SAVESTACK);
    return *this;
  }

  std::size_t intern(const std::string& s) {
    for (std::size_t i = 0; i < strings_.size(); ++i)
      if (strings_[i] == s) return i;
    strings_.push_back(s);
    return strings_.size() - 1;
  }

  std::string bytes() const {
    std::string out;
    auto seg = [&](std::uint32_t type, const std::string& body) {
      be32(out, type);
      be32(out, static_cast<std::uint32_t>(body.size()));
      out += body;
    };
    std::string m;
    be32(m, mask);
    seg(1, m);
    std::string f;
    for (const auto& fn : functions_) {
      be32(f, fn.first);
      f += fn.second;
      f.push_back('\0');
    }
    seg(2, f);
    std::string st;
    for (const auto& s : strings_) {
      st += s;
      st.push_back('\0');
    }
    seg(3, st);
    seg(4, std::string(code_.begin(), code_.end()));
    out.push_back('\n');
    return out;
  }

 private:
  static void be32(std::string& o, std::uint32_t v) {
    for (int s = 24; s >= 0; s -= 8) o.push_back(static_cast<char>((v >> s) & 0xFF));
  }
  std::vector<std::uint8_t> code_;
  std::vector<std::string> strings_;
  std::vector<std::pair<std::uint32_t, std::string>> functions_;
  int count_ = 0;
};

}  // namespace gs2asm
