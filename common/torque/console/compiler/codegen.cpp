// Code generation: one walk of the syntax tree emits DSO v33 code words.
//
// Every expression has a natural result type (none, unsigned, float or
// string) and is compiled for the type its consumer asks for, with one
// conversion opcode where the two differ. The emitted shapes, the operand
// order and the order in which names enter the string table were matched
// against the shipped Graal 3.04 .dso files and the prefs.cs / config.cs
// files the real client compiles (see README.md, "Evidence").

#include "compile.hpp"
#include "opcodes.hpp"
#include "parser.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <unordered_map>

namespace Torque {
namespace {

using namespace Script;

enum class Type { none, uint, flt, str };

struct Failure {
  int line;
  std::string message;
};

class StringTable {
 public:
  std::uint32_t add(const std::string& s) {
    const auto it = offsets_.find(s);
    if (it != offsets_.end()) return it->second;
    const auto at = static_cast<std::uint32_t>(bytes_.size());
    bytes_ += s;
    bytes_ += '\0';
    offsets_.emplace(s, at);
    return at;
  }
  bool find(const std::string& s, std::uint32_t& at) const {
    const auto it = offsets_.find(s);
    if (it == offsets_.end()) return false;
    at = it->second;
    return true;
  }
  const std::string& bytes() const { return bytes_; }

 private:
  std::string bytes_;
  std::unordered_map<std::string, std::uint32_t> offsets_;
};

class FloatTable {
 public:
  std::uint32_t add(double v) {
    for (std::size_t k = 0; k < values_.size(); ++k)
      if (std::memcmp(&values_[k], &v, sizeof v) == 0) return static_cast<std::uint32_t>(k);
    values_.push_back(v);
    return static_cast<std::uint32_t>(values_.size() - 1);
  }
  const std::vector<double>& values() const { return values_; }

 private:
  std::vector<double> values_;
};

// Text a number literal has when a string is wanted.
std::string number_text(const Expr& e) {
  if (e.kind == ExprKind::int_lit) return std::to_string(e.number);
  char buf[64];
  std::snprintf(buf, sizeof buf, "%g", e.real);
  return buf;
}

class Generator {
 public:
  DsoBlock run(const StmtList& script) {
    for (const auto& s : script) statement(*s);
    emit(Op::RETURN);
    return finish();
  }

 private:
  std::vector<std::uint32_t> code_;
  std::vector<DsoLine> lines_;
  StringTable global_, function_;
  FloatTable global_floats_, function_floats_;
  // Identifier operand sites: code index -> name. Function parameters are
  // resolved at the end (see finish()).
  std::vector<std::pair<std::uint32_t, std::string>> idents_;
  std::vector<std::pair<std::uint32_t, std::string>> params_;
  bool in_function_ = false;
  struct Loop { std::vector<std::uint32_t> breaks, continues; };
  std::vector<Loop> loops_;

  std::uint32_t here() const { return static_cast<std::uint32_t>(code_.size()); }
  void emit(std::uint32_t w) { code_.push_back(w); }
  std::uint32_t emit_hole() {
    code_.push_back(0);
    return here() - 1;
  }
  void patch(std::uint32_t at, std::uint32_t value) { code_[at] = value; }

  void intern(const std::string& name) { global_.add(name); }
  void ident(const std::string& name) {
    intern(name);
    idents_.emplace_back(here(), name);
    emit(0);
  }
  void string_operand(const std::string& s) {
    emit(in_function_ ? function_.add(s) : global_.add(s));
  }
  void float_operand(double v) {
    emit(in_function_ ? function_floats_.add(v) : global_floats_.add(v));
  }

  static std::uint32_t to_none(Type t) {
    return t == Type::uint ? Op::UINT_TO_NONE : t == Type::flt ? Op::FLT_TO_NONE : Op::STR_TO_NONE;
  }
  void convert(Type from, Type to) {
    if (from == to || from == Type::none) return;
    switch (from) {
      case Type::uint:
        emit(to == Type::flt ? Op::UINT_TO_FLT : to == Type::str ? Op::UINT_TO_STR : Op::UINT_TO_NONE);
        break;
      case Type::flt:
        emit(to == Type::uint ? Op::FLT_TO_UINT : to == Type::str ? Op::FLT_TO_STR : Op::FLT_TO_NONE);
        break;
      case Type::str:
        emit(to == Type::uint ? Op::STR_TO_UINT : to == Type::flt ? Op::STR_TO_FLT : Op::STR_TO_NONE);
        break;
      case Type::none: break;
    }
  }

  static bool float_op(BinOp op) {
    return op == BinOp::add || op == BinOp::sub || op == BinOp::mul || op == BinOp::div;
  }
  static bool compare_op(BinOp op) {
    return op == BinOp::eq || op == BinOp::ne || op == BinOp::lt || op == BinOp::le ||
           op == BinOp::gt || op == BinOp::ge;
  }
  static std::uint32_t opcode(BinOp op) {
    switch (op) {
      case BinOp::add: return Op::ADD;
      case BinOp::sub: return Op::SUB;
      case BinOp::mul: return Op::MUL;
      case BinOp::div: return Op::DIV;
      case BinOp::mod: return Op::MOD;
      case BinOp::bit_and: return Op::BITAND;
      case BinOp::bit_or: return Op::BITOR;
      case BinOp::bit_xor: return Op::XOR;
      case BinOp::shl: return Op::SHL;
      case BinOp::shr: return Op::SHR;
      case BinOp::eq: return Op::CMPEQ;
      case BinOp::ne: return Op::CMPNE;
      case BinOp::lt: return Op::CMPLT;
      case BinOp::le: return Op::CMPLE;
      case BinOp::gt: return Op::CMPGR;
      case BinOp::ge: return Op::CMPGE;
      case BinOp::none: break;
    }
    return Op::BREAK;
  }
  static BinOp compound(char c) {
    switch (c) {
      case '+': return BinOp::add;
      case '-': return BinOp::sub;
      case '*': return BinOp::mul;
      case '/': return BinOp::div;
      case '%': return BinOp::mod;
      case '&': return BinOp::bit_and;
      case '|': return BinOp::bit_or;
      case '^': return BinOp::bit_xor;
      case '<': return BinOp::shl;
      case '>': return BinOp::shr;
    }
    return BinOp::none;
  }

  Type natural(const Expr& e) const {
    switch (e.kind) {
      case ExprKind::int_lit: return Type::uint;
      case ExprKind::float_lit: return Type::flt;
      case ExprKind::str_lit:
      case ExprKind::ident:
      case ExprKind::call:
      case ExprKind::concat: return Type::str;
      case ExprKind::var:
      case ExprKind::field: return Type::none;
      case ExprKind::binary: return float_op(e.op) ? Type::flt : Type::uint;
      case ExprKind::str_eq:
      case ExprKind::logical: return Type::uint;
      case ExprKind::unary: return e.unary_op == '-' ? Type::flt : Type::uint;
      case ExprKind::assign: return assigned_type(e);
      case ExprKind::inc_dec: return Type::flt;
      case ExprKind::conditional: return natural(*e.b);
      case ExprKind::object: return Type::uint;
    }
    return Type::none;
  }

  Type assigned_type(const Expr& e) const {
    if (e.unary_op == 0) {
      const Type t = natural(*e.b);
      return t == Type::none ? Type::str : t;
    }
    return float_op(compound(e.unary_op)) ? Type::flt : Type::uint;
  }

  // Array subscripts as one comma-joined string: a, b -> "a,b".
  void subscript_string(const ExprList& idx) {
    for (std::size_t k = 0; k < idx.size(); ++k) {
      if (k) emit(Op::ADVANCE_STR_COMMA);
      expr(*idx[k], Type::str);
    }
    for (std::size_t k = 1; k < idx.size(); ++k) emit(Op::REWIND_STR);
  }

  // Selects variable e for loading (create false) or saving (create true).
  void select_var(const Expr& e, bool create) {
    if (e.indices.empty()) {
      emit(create ? Op::SETCURVAR_CREATE : Op::SETCURVAR);
      ident(e.text);
      return;
    }
    emit(Op::LOADIMMED_IDENT);
    ident(e.text);
    emit(Op::ADVANCE_STR);
    subscript_string(e.indices);
    emit(Op::REWIND_STR);
    emit(create ? Op::SETCURVAR_ARRAY_CREATE : Op::SETCURVAR_ARRAY);
  }

  // Selects field e of its object (or of the object being built when
  // e.a is null). Leaves the string stack as it found it.
  void select_field(const Expr* object, const std::string& name, const ExprList& idx) {
    if (!idx.empty()) {
      subscript_string(idx);
      emit(Op::ADVANCE_STR);
    }
    if (object) {
      expr(*object, Type::str);
      emit(Op::SETCUROBJECT);
    } else {
      emit(Op::SETCUROBJECT_NEW);
    }
    emit(Op::SETCURFIELD);
    ident(name);
    if (!idx.empty()) {
      emit(Op::TERMINATE_REWIND_STR);
      emit(Op::SETCURFIELD_ARRAY);
    }
  }

  static std::uint32_t load_var(Type t) {
    return t == Type::uint ? Op::LOADVAR_UINT : t == Type::flt ? Op::LOADVAR_FLT : Op::LOADVAR_STR;
  }
  static std::uint32_t save_var(Type t) {
    return t == Type::uint ? Op::SAVEVAR_UINT : t == Type::flt ? Op::SAVEVAR_FLT : Op::SAVEVAR_STR;
  }
  static std::uint32_t load_field(Type t) {
    return t == Type::uint ? Op::LOADFIELD_UINT : t == Type::flt ? Op::LOADFIELD_FLT : Op::LOADFIELD_STR;
  }
  static std::uint32_t save_field(Type t) {
    return t == Type::uint ? Op::SAVEFIELD_UINT : t == Type::flt ? Op::SAVEFIELD_FLT : Op::SAVEFIELD_STR;
  }

  // Stores the value already computed (type t) into target. A string value
  // is kept on the string stack while the target is selected.
  void store(const Expr& target, Type t) {
    if (target.kind == ExprKind::var) {
      const bool hold = t == Type::str && !target.indices.empty();
      if (hold) emit(Op::ADVANCE_STR);
      select_var(target, true);
      if (hold) emit(Op::TERMINATE_REWIND_STR);
      emit(save_var(t));
      return;
    }
    const bool hold = t == Type::str;
    if (hold) emit(Op::ADVANCE_STR);
    select_field(target.a.get(), target.text, target.indices);
    if (hold) emit(Op::TERMINATE_REWIND_STR);
    emit(save_field(t));
  }

  // target op= value, and ++/-- (value null: the constant 1).
  void read_modify_write(const Expr& target, BinOp op, const Expr* value, Type t) {
    if (value) expr(*value, t);
    else {
      emit(Op::LOADIMMED_FLT);
      float_operand(1.0);
    }
    if (target.kind == ExprKind::var) {
      select_var(target, true);
      emit(load_var(t));
      emit(opcode(op));
      emit(save_var(t));
    } else {
      select_field(target.a.get(), target.text, target.indices);
      emit(load_field(t));
      emit(opcode(op));
      emit(save_field(t));
    }
  }

  void condition(const Expr& c, std::uint32_t uint_jump, std::uint32_t float_jump) {
    if (natural(c) == Type::uint) {
      expr(c, Type::uint);
      emit(uint_jump);
    } else {
      expr(c, Type::flt);
      emit(float_jump);
    }
  }

  void expr(const Expr& e, Type want) {
    switch (e.kind) {
      case ExprKind::int_lit:
      case ExprKind::float_lit:
        if (want == Type::none) return;
        if (want == Type::uint) {
          emit(Op::LOADIMMED_UINT);
          emit(e.kind == ExprKind::int_lit ? e.number
                                           : static_cast<std::uint32_t>(static_cast<std::int64_t>(e.real)));
        } else if (want == Type::flt) {
          emit(Op::LOADIMMED_FLT);
          float_operand(e.real);
        } else {
          emit(Op::LOADIMMED_STR);
          string_operand(number_text(e));
        }
        return;
      case ExprKind::str_lit:
        if (want == Type::none) return;
        if (e.flag) {
          emit(Op::TAG_TO_STR);
          string_operand(e.text);
          convert(Type::str, want);
          return;
        }
        if (want == Type::uint) {
          emit(Op::LOADIMMED_UINT);
          emit(static_cast<std::uint32_t>(std::strtoll(e.text.c_str(), nullptr, 10)));
        } else if (want == Type::flt) {
          emit(Op::LOADIMMED_FLT);
          float_operand(std::strtod(e.text.c_str(), nullptr));
        } else {
          emit(Op::LOADIMMED_STR);
          string_operand(e.text);
        }
        return;
      case ExprKind::ident:
        if (want == Type::none) return;
        emit(Op::LOADIMMED_IDENT);
        ident(e.text);
        convert(Type::str, want);
        return;
      case ExprKind::var:
        if (want == Type::none) return;
        select_var(e, false);
        emit(load_var(want));
        return;
      case ExprKind::field:
        if (want == Type::none) return;
        select_field(e.a.get(), e.text, e.indices);
        emit(load_field(want));
        return;
      case ExprKind::call: {
        intern(e.text);
        if (!e.space.empty()) intern(e.space);
        emit(Op::PUSH_FRAME);
        for (const auto& a : e.args) {
          expr(*a, Type::str);
          emit(Op::PUSH);
        }
        emit(e.call_type == 0 ? Op::CALLFUNC_RESOLVE : Op::CALLFUNC);
        ident(e.text);
        if (e.space.empty()) emit(0);
        else ident(e.space);
        emit(static_cast<std::uint32_t>(e.call_type));
        convert(Type::str, want);
        return;
      }
      case ExprKind::binary: {
        const Type operand = float_op(e.op) || compare_op(e.op) ? Type::flt : Type::uint;
        expr(*e.b, operand);
        expr(*e.a, operand);
        emit(opcode(e.op));
        convert(float_op(e.op) ? Type::flt : Type::uint, want);
        return;
      }
      case ExprKind::str_eq:
        expr(*e.a, Type::str);
        emit(Op::ADVANCE_STR_NUL);
        expr(*e.b, Type::str);
        emit(Op::COMPARE_STR);
        if (e.flag) emit(Op::NOT);
        convert(Type::uint, want);
        return;
      case ExprKind::concat:
        expr(*e.a, Type::str);
        if (e.append_char) {
          emit(Op::ADVANCE_STR_APPENDCHAR);
          emit(static_cast<unsigned char>(e.append_char));
        } else {
          emit(Op::ADVANCE_STR);
        }
        expr(*e.b, Type::str);
        emit(Op::REWIND_STR);
        convert(Type::str, want);
        return;
      case ExprKind::logical: {
        expr(*e.a, Type::uint);
        emit(e.flag ? Op::JMPIF_NP : Op::JMPIFNOT_NP);
        const std::uint32_t hole = emit_hole();
        expr(*e.b, Type::uint);
        patch(hole, here());
        convert(Type::uint, want);
        return;
      }
      case ExprKind::unary:
        if (e.unary_op == '-') {
          expr(*e.a, Type::flt);
          emit(Op::NEG);
          convert(Type::flt, want);
        } else if (e.unary_op == '~') {
          expr(*e.a, Type::uint);
          emit(Op::ONESCOMPLEMENT);
          convert(Type::uint, want);
        } else {
          const Type t = natural(*e.a);
          if (t == Type::flt || t == Type::str) {
            expr(*e.a, Type::flt);
            emit(Op::NOTF);
          } else {
            expr(*e.a, Type::uint);
            emit(Op::NOT);
          }
          convert(Type::uint, want);
        }
        return;
      case ExprKind::assign: {
        const Type t = assigned_type(e);
        if (e.unary_op == 0) {
          expr(*e.b, t);
          store(*e.a, t);
        } else {
          read_modify_write(*e.a, compound(e.unary_op), e.b.get(), t);
        }
        convert(t, want);
        return;
      }
      case ExprKind::inc_dec:
        read_modify_write(*e.a, e.flag ? BinOp::add : BinOp::sub, nullptr, Type::flt);
        convert(Type::flt, want);
        return;
      case ExprKind::conditional: {
        condition(*e.a, Op::JMPIFNOT, Op::JMPIFFNOT);
        const std::uint32_t to_false = emit_hole();
        const Type t = want == Type::none ? Type::none : want;
        expr(*e.b, t);
        emit(Op::JMP);
        const std::uint32_t to_end = emit_hole();
        patch(to_false, here());
        expr(*e.c, t);
        patch(to_end, here());
        return;
      }
      case ExprKind::object:
        emit(Op::LOADIMMED_UINT);
        emit(0);
        object(*e.object, true);
        convert(Type::uint, want);
        return;
    }
  }

  void object(const ObjectDecl& o, bool root) {
    intern(o.parent);
    emit(Op::PUSH_FRAME);
    expr(*o.class_name, Type::str);
    emit(Op::PUSH);
    expr(*o.object_name, Type::str);
    emit(Op::PUSH);
    for (const auto& a : o.args) {
      expr(*a, Type::str);
      emit(Op::PUSH);
    }
    emit(Op::CREATE_OBJECT);
    ident(o.parent);
    emit(o.is_datablock ? 1 : 0);
    const std::uint32_t fail = emit_hole();
    for (const auto& slot : o.slots) {
      intern(slot.name);
      Type t = natural(*slot.value);
      if (t == Type::none) t = Type::str;
      expr(*slot.value, t);
      const bool hold = t == Type::str;
      if (hold) emit(Op::ADVANCE_STR);
      select_field(nullptr, slot.name, slot.indices);
      if (hold) emit(Op::TERMINATE_REWIND_STR);
      emit(save_field(t));
      emit(to_none(t));
    }
    emit(Op::ADD_OBJECT);
    emit(root ? 1 : 0);
    for (const auto& child : o.children) object(*child->object, false);
    emit(Op::END_OBJECT);
    emit(root ? 1 : 0);
    patch(fail, here());
  }

  void body(const StmtList& list) {
    for (const auto& s : list) statement(*s);
  }

  void statement(const Stmt& s) {
    if (in_function_) lines_.push_back({static_cast<std::uint32_t>(s.line), here()});
    switch (s.kind) {
      case StmtKind::expr:
        expr(*s.expr, Type::none);
        return;
      case StmtKind::if_: {
        condition(*s.expr, Op::JMPIFNOT, Op::JMPIFFNOT);
        const std::uint32_t to_else = emit_hole();
        body(s.body);
        if (s.else_body.empty()) {
          patch(to_else, here());
          return;
        }
        emit(Op::JMP);
        const std::uint32_t to_end = emit_hole();
        patch(to_else, here());
        body(s.else_body);
        patch(to_end, here());
        return;
      }
      case StmtKind::loop: {
        loops_.emplace_back();
        std::uint32_t skip = 0;
        if (s.init) {
          expr(*s.init, Type::none);
        }
        if (s.test_first) {
          condition(*s.expr, Op::JMPIFNOT, Op::JMPIFFNOT);
          skip = emit_hole();
        }
        const std::uint32_t top = here();
        body(s.body);
        const std::uint32_t next = here();
        if (s.step) {
          expr(*s.step, Type::none);
        }
        condition(*s.expr, Op::JMPIF, Op::JMPIFF);
        emit(top);
        const std::uint32_t end = here();
        if (s.test_first) patch(skip, end);
        for (auto at : loops_.back().breaks) patch(at, end);
        for (auto at : loops_.back().continues) patch(at, next);
        loops_.pop_back();
        return;
      }
      case StmtKind::brk:
      case StmtKind::cont:
        emit(Op::JMP);
        (s.kind == StmtKind::brk ? loops_.back().breaks : loops_.back().continues)
            .push_back(emit_hole());
        return;
      case StmtKind::ret:
        if (s.expr) expr(*s.expr, Type::str);
        emit(Op::RETURN);
        return;
      case StmtKind::function:
        function(*s.function);
        return;
    }
  }

  void function(const FunctionDecl& f) {
    emit(Op::FUNC_DECL);
    ident(f.name);
    if (f.space.empty()) emit(0);
    else ident(f.space);
    if (f.package.empty()) emit(0);
    else ident(f.package);
    emit(1);
    const std::uint32_t end = emit_hole();
    emit(static_cast<std::uint32_t>(f.args.size()));
    for (const auto& a : f.args) {
      params_.emplace_back(here(), a);
      emit(0);
    }
    in_function_ = true;
    body(f.body);
    emit(Op::RETURN);
    in_function_ = false;
    patch(end, here());
  }

  DsoBlock finish() {
    DsoBlock b;
    // A parameter keeps its name only when that name is in the global string
    // table; otherwise it points one past the table end (the "unused
    // parameter" sentinel of the published format notes).
    struct Site { std::uint32_t ip; std::uint32_t offset; bool unnamed; std::string name; };
    std::vector<Site> sites;
    for (const auto& id : idents_) {
      std::uint32_t at = 0;
      global_.find(id.second, at);
      sites.push_back({id.first, at, false, id.second});
    }
    const auto end = static_cast<std::uint32_t>(global_.bytes().size());
    for (const auto& p : params_) {
      std::uint32_t at = 0;
      if (global_.find(p.second, at)) sites.push_back({p.first, at, false, p.second});
      else sites.push_back({p.first, end, true, std::string()});
    }
    std::sort(sites.begin(), sites.end(), [](const Site& x, const Site& y) { return x.ip < y.ip; });
    // Groups are listed newest first (by first use); within a group the first
    // use leads and the later uses follow newest first.
    std::map<std::uint32_t, std::size_t> group_of;
    std::vector<DsoIdentifier> groups;
    for (const auto& s : sites) {
      auto it = group_of.find(s.offset);
      if (it == group_of.end()) {
        group_of.emplace(s.offset, groups.size());
        groups.push_back({s.offset, s.unnamed, s.name, {s.ip}});
      } else {
        auto& uses = groups[it->second].uses;
        uses.insert(uses.begin() + 1, s.ip);
      }
    }
    std::reverse(groups.begin(), groups.end());
    b.global_strings = global_.bytes();
    b.function_strings = function_.bytes();
    b.global_floats = global_floats_.values();
    b.function_floats = function_floats_.values();
    b.code = code_;
    b.lines = lines_;
    b.identifiers = std::move(groups);
    return b;
  }
};

void put32(std::vector<std::uint8_t>& out, std::uint32_t v) {
  for (int k = 0; k < 4; ++k) out.push_back(static_cast<std::uint8_t>(v >> (8 * k)));
}

void put_floats(std::vector<std::uint8_t>& out, const std::vector<double>& values, FloatOrder order) {
  put32(out, static_cast<std::uint32_t>(values.size()));
  for (double v : values) {
    std::uint64_t bits = 0;
    std::memcpy(&bits, &v, sizeof bits);
    for (int k = 0; k < 8; ++k) {
      const int shift = order == FloatOrder::little ? 8 * k : 8 * (7 - k);
      out.push_back(static_cast<std::uint8_t>(bits >> shift));
    }
  }
}

} // namespace

bool compile_script(const std::string& source, DsoBlock& output, CompileError& error) {
  StmtList script;
  ParseError parse_error;
  if (!parse_script(source, script, parse_error)) {
    error.line = parse_error.line;
    error.message = parse_error.message;
    return false;
  }
  Generator g;
  output = g.run(script);
  return true;
}

std::vector<std::uint8_t> write_dso(const DsoBlock& b, FloatOrder order) {
  std::vector<std::uint8_t> out;
  put32(out, 33);
  put32(out, static_cast<std::uint32_t>(b.global_strings.size()));
  out.insert(out.end(), b.global_strings.begin(), b.global_strings.end());
  put_floats(out, b.global_floats, order);
  put32(out, static_cast<std::uint32_t>(b.function_strings.size()));
  out.insert(out.end(), b.function_strings.begin(), b.function_strings.end());
  put_floats(out, b.function_floats, order);
  put32(out, static_cast<std::uint32_t>(b.code.size()));
  put32(out, static_cast<std::uint32_t>(b.lines.size()));
  for (std::uint32_t w : b.code) {
    if (w < 0xFF) out.push_back(static_cast<std::uint8_t>(w));
    else {
      out.push_back(0xFF);
      put32(out, w);
    }
  }
  for (const auto& l : b.lines) {
    put32(out, l.line);
    put32(out, l.ip);
  }
  put32(out, static_cast<std::uint32_t>(b.identifiers.size()));
  for (const auto& id : b.identifiers) {
    put32(out, id.string_offset);
    put32(out, static_cast<std::uint32_t>(id.uses.size()));
    for (std::uint32_t ip : id.uses) put32(out, ip);
  }
  return out;
}

} // namespace Torque
