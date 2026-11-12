// GS2 bytecode loader: segments, operands and the load-time pair fusions.
// Graal_analysis `client-internals/gs2-vm-from-engines.md`, "Bytecode and
// source" and "Differences between the three engines".

#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <set>
#include <sstream>

#include "gs2.hpp"

namespace gs2 {

namespace {

std::set<int> base42() {
  std::set<int> s;
  for (int i = 1; i <= 11; ++i) s.insert(i);
  for (int i = 20; i <= 27; ++i) s.insert(i);
  for (int i = 30; i <= 47; ++i) s.insert(i);
  for (int i = 50; i <= 53; ++i) s.insert(i);
  for (int i = 60; i <= 104; ++i) s.insert(i);
  for (int i = 110; i <= 120; ++i) s.insert(i);
  for (int i = 130; i <= 142; ++i) s.insert(i);
  s.insert(150); s.insert(151); s.insert(163);
  for (int i = 180; i <= 184; ++i) s.insert(i);
  s.insert(189); s.insert(190);
  for (int i = 200; i <= 233; ++i) s.insert(i);
  return s;
}

const std::set<int>& opset(Profile p) {
  static const std::set<int> s42 = base42();
  static const std::set<int> s50 = [] {
    auto s = base42();
    s.insert(48); s.insert(49); s.insert(54); s.insert(121);
    return s;
  }();
  static const std::set<int> s600 = [] {
    auto s = base42();
    s.insert(54); s.insert(121);
    for (int i = 234; i <= 242; ++i) s.insert(i);
    return s;
  }();
  switch (p) {
    case Profile::Engine42: return s42;
    case Profile::Engine50: return s50;
    default: return s600;
  }
}

std::uint32_t be32(const std::uint8_t* p) {
  return (std::uint32_t(p[0]) << 24) | (std::uint32_t(p[1]) << 16) | (std::uint32_t(p[2]) << 8) | p[3];
}

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

bool isArithOrBool(int op) { return op >= 60 && op <= 67; }
bool isOrderedCompare(int op) { return op >= 72 && op <= 75; }

// The pairs the engines rewrite after a load. The following instructions
// stay in the list; the executor steps over them.
int fuse(std::vector<Instruction>& code) {
  int n = 0;
  auto opAt = [&](std::size_t i) { return i < code.size() ? code[i].loadedOp : -1; };
  for (std::size_t i = 0; i < code.size(); ++i) {
    const int a = code[i].loadedOp, b = opAt(i + 1), c = opAt(i + 2);
    int fused = 0;
    if (a == 20 && isArithOrBool(b)) fused = (c == 50 ? 216 : 200) + (b - 60);
    else if (isArithOrBool(a) && b == 50) fused = 208 + (a - 60);
    else if (a == 20 && isOrderedCompare(b)) fused = 224 + (b - 72);
    else if (a == 46 && b == 30) fused = 228;
    else if (a == 46 && b == 34) fused = 229;
    else if (a == 46 && b == 33) fused = 230;
    else if (a == 46 && b == 36) fused = 233;
    else if (a == 46 && b == 52 && c == 32) fused = 231;
    else if (a == 46 && b == 53 && c == 32) fused = 232;
    if (fused) { code[i].op = fused; ++n; }
  }
  return n;
}

}  // namespace

const char* profileName(Profile p) {
  switch (p) {
    case Profile::Engine42: return "4.2";
    case Profile::Engine50: return "5.0";
    default: return "6.00";
  }
}

bool opcodeInProfile(int op, Profile p) { return opset(p).count(op) != 0; }

const Function* Script::findFunction(const std::string& name) const {
  const std::string want = lower(name);
  for (const auto& f : functions)
    if (lower(f.name) == want) return &f;
  return nullptr;
}

LoadResult load(const std::string& bytes) {
  return load(reinterpret_cast<const std::uint8_t*>(bytes.data()), bytes.size());
}

LoadResult load(const std::uint8_t* data, std::size_t size) {
  LoadResult r;
  auto s = std::make_shared<Script>();
  const std::uint8_t* codeBytes = nullptr;
  std::size_t codeLen = 0;
  bool any = false;

  std::size_t pos = 0;
  while (pos + 8 <= size) {
    const std::uint32_t type = be32(data + pos), len = be32(data + pos + 4);
    if (type < 1 || type > 4) break;              // ends the read
    if (len > size - pos - 8) break;              // truncated: ends the read
    const std::uint8_t* body = data + pos + 8;
    any = true;
    if (type == 1) {
      if (len >= 4) s->gs1EventMask = be32(body);
    } else if (type == 2) {
      std::size_t p = 0;
      while (p + 4 <= len) {
        Function f;
        f.index = be32(body + p);
        p += 4;
        std::size_t e = p;
        while (e < len && body[e] != 0) ++e;
        if (e >= len) { r.error = "function table: name without a NUL"; return r; }
        f.name.assign(reinterpret_cast<const char*>(body + p), e - p);
        p = e + 1;
        if (f.name.compare(0, 7, "public.") == 0) { f.name.erase(0, 7); f.isPublic = true; }
        s->functions.push_back(std::move(f));
      }
    } else if (type == 3) {
      std::size_t p = 0;
      while (p < len) {
        std::size_t e = p;
        while (e < len && body[e] != 0) ++e;
        s->strings.emplace_back(reinterpret_cast<const char*>(body + p), e - p);
        p = e + 1;
      }
    } else {
      codeBytes = body;
      codeLen = len;
    }
    pos += 8 + len;
  }
  if (!any) { r.error = "no segment"; return r; }

  for (std::size_t p = 0; p < codeLen;) {
    const std::uint8_t b = codeBytes[p++];
    if (b < 0xF0) {
      Instruction in;
      in.op = in.loadedOp = b;
      s->code.push_back(in);
      continue;
    }
    if (s->code.empty()) { r.error = "operand before the first opcode"; return r; }
    Instruction& in = s->code.back();
    auto need = [&](std::size_t n) { return p + n <= codeLen; };
    auto str = [&](long idx) -> bool {
      if (idx < 0 || static_cast<std::size_t>(idx) >= s->strings.size()) {
        r.error = "string index " + std::to_string(idx) + " outside the table";
        return false;
      }
      in.kind = Instruction::Kind::String;
      in.str = s->strings[static_cast<std::size_t>(idx)];
      in.num = static_cast<double>(idx);
      return true;
    };
    auto num = [&](double d) { in.kind = Instruction::Kind::Number; in.num = d; };
    switch (b) {
      case 0xF0:
        if (!need(1)) { r.error = "truncated operand"; return r; }
        if (!str(codeBytes[p])) return r;
        p += 1;
        break;
      case 0xF1:
        if (!need(2)) { r.error = "truncated operand"; return r; }
        if (!str((long(codeBytes[p]) << 8) | codeBytes[p + 1])) return r;
        p += 2;
        break;
      case 0xF2: {
        if (!need(4)) { r.error = "truncated operand"; return r; }
        const auto v = static_cast<std::int32_t>(be32(codeBytes + p));
        if (!str(v)) return r;
        p += 4;
        break;
      }
      case 0xF3:
        if (!need(1)) { r.error = "truncated operand"; return r; }
        num(static_cast<std::int8_t>(codeBytes[p]));
        p += 1;
        break;
      case 0xF4:
        if (!need(2)) { r.error = "truncated operand"; return r; }
        num(static_cast<std::int16_t>((codeBytes[p] << 8) | codeBytes[p + 1]));
        p += 2;
        break;
      case 0xF5:
        if (!need(4)) { r.error = "truncated operand"; return r; }
        num(static_cast<std::int32_t>(be32(codeBytes + p)));
        p += 4;
        break;
      case 0xF6: {
        std::size_t e = p;
        while (e < codeLen && codeBytes[e] != 0) ++e;
        if (e >= codeLen) { r.error = "decimal operand without a NUL"; return r; }
        const std::string text(reinterpret_cast<const char*>(codeBytes + p), e - p);
        num(std::strtod(text.c_str(), nullptr));
        p = e + 1;
        break;
      }
      default:
        r.error = "unknown operand marker " + std::to_string(b);
        return r;
    }
  }
  s->fusedPairs = fuse(s->code);
  r.script = s;
  return r;
}

std::string opcodeName(int op) {
  static const std::map<int, const char*> names = {
      {1, "jmp"}, {2, "jmptrue"}, {3, "or"}, {4, "if"}, {5, "and"}, {6, "call"},
      {7, "ret"}, {8, "sleep"}, {9, "loopcheck"}, {10, "savestackpos"}, {11, "waitfor"},
      {20, "number"}, {21, "string"}, {22, "var"}, {23, "marker"}, {24, "true"},
      {25, "false"}, {26, "null"}, {27, "pi"}, {30, "copy"}, {31, "swap"}, {32, "pop"},
      {33, "tofloat"}, {34, "tostring"}, {35, "member"}, {36, "toobject"},
      {37, "arrayend"}, {38, "arraynew"}, {39, "setarray"}, {40, "inlinenew"},
      {41, "makevar"}, {42, "newobject"}, {43, "objfromstr"}, {44, "inlinecond"},
      {45, "slotstore"}, {46, "slotload"}, {47, "op47"}, {48, "op48"}, {49, "op49"},
      {50, "assign"}, {51, "paramsend"}, {52, "inc"}, {53, "dec"}, {54, "op54"},
      {60, "add"}, {61, "sub"}, {62, "mul"}, {63, "div"}, {64, "mod"}, {65, "pow"},
      {66, "booland"}, {67, "boolor"}, {68, "not"}, {69, "neg"}, {70, "eq"}, {71, "neq"},
      {72, "lt"}, {73, "gt"}, {74, "lte"}, {75, "gte"}, {76, "bitor"}, {77, "bitand"},
      {78, "bitxor"}, {79, "bitinvert"}, {80, "inrange"}, {81, "inobj"}, {82, "objindex"},
      {83, "objtype"}, {84, "format"}, {85, "int"}, {86, "abs"}, {87, "random"},
      {88, "sin"}, {89, "cos"}, {90, "arctan"}, {91, "exp"}, {92, "log"}, {93, "min"},
      {94, "max"}, {95, "getangle"}, {96, "getdir"}, {97, "vecx"}, {98, "vecy"},
      {99, "objindices"}, {100, "objlink"}, {101, "shl"}, {102, "shr"}, {103, "char"},
      {104, "objcompare"}, {110, "trim"}, {111, "length"}, {112, "pos"}, {113, "join"},
      {114, "charat"}, {115, "substring"}, {116, "starts"}, {117, "ends"},
      {118, "tokenize"}, {119, "translate"}, {120, "positions"}, {121, "op121"},
      {130, "size"}, {131, "arrayget"}, {132, "arrayset"}, {133, "array2get"},
      {134, "array2set"}, {135, "subarray"}, {136, "addstring"}, {137, "deletestring"},
      {138, "removestring"}, {139, "replacestring"}, {140, "insertstring"},
      {141, "clear"}, {142, "arraynew2"}, {150, "with"}, {151, "endwith"},
      {163, "foreach"}, {180, "this"}, {181, "thiso"}, {182, "player"},
      {183, "playero"}, {184, "level"}, {189, "temp"}, {190, "params"}};
  auto it = names.find(op);
  if (it != names.end()) return it->second;
  if (op >= 200 && op <= 207) return std::string("imm.") + opcodeName(op - 200 + 60);
  if (op >= 208 && op <= 215) return std::string(opcodeName(op - 208 + 60)) + ".assign";
  if (op >= 216 && op <= 223) return std::string("imm.") + opcodeName(op - 216 + 60) + ".assign";
  if (op >= 224 && op <= 227) return std::string("imm.") + opcodeName(op - 224 + 72);
  switch (op) {
    case 228: return "slotload.copy";
    case 229: return "slotload.tostring";
    case 230: return "slotload.tofloat";
    case 231: return "slotinc";
    case 232: return "slotdec";
    case 233: return "slotload.toobject";
    default: return "op" + std::to_string(op);
  }
}

std::string disassemble(const Script& s) {
  std::ostringstream o;
  o << "gs1 event mask " << s.gs1EventMask << "\n";
  for (const auto& f : s.functions)
    o << "function " << (f.isPublic ? "public " : "") << f.name << " @" << f.index << "\n";
  for (std::size_t i = 0; i < s.code.size(); ++i) {
    const auto& in = s.code[i];
    o << i << "\t" << opcodeName(in.op);
    if (in.op != in.loadedOp) o << " (" << opcodeName(in.loadedOp) << ")";
    if (in.kind == Instruction::Kind::Number) o << " " << Machine::numberText(in.num);
    if (in.kind == Instruction::Kind::String) o << " \"" << in.str << "\"";
    o << "\n";
  }
  return o.str();
}

}  // namespace gs2
