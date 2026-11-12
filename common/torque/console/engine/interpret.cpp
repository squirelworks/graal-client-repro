// The DSO v33 interpreter. Opcode numbers and operand shapes are Graal's
// table in Graal_analysis torque/scripting.md. How each opcode moves the
// string, integer and float stacks was read from the operand order in the
// shipped 3.04 scripts (README.md, "Stack behaviour").

#include "internal.hpp"

#include <algorithm>
#include <cmath>

namespace Torque {
namespace {
enum Op : std::uint32_t {
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

std::uint32_t to_u32(double f) { return Value::of_float(f).u32(); }

bool iequal(const std::string& a, const std::string& b) {
  return a.size() == b.size() && lower(a) == lower(b);
}
} // namespace

std::string Engine::execute(std::shared_ptr<CodeBlock> block, std::uint32_t start, bool in_function,
                            const Function* fn, Args* argv, bool no_calls) {
  Frame frame;
  frame.block = block;
  frame.fn = fn;
  if (fn && argv) {
    for (std::size_t i = 0; i < fn->args.size() && i + 1 < argv->size(); ++i) {
      if (fn->args[i].empty()) continue;
      frame.locals[lower(fn->args[i])] = {fn->args[i], Value::of_string((*argv)[i + 1])};
    }
  }
  frames.push_back(&frame);
  struct Pop { std::vector<Frame*>& f; ~Pop() { f.pop_back(); } } pop{frames};

  const auto& code = block->dso.code;
  std::vector<std::string> str{std::string()};
  std::vector<std::uint32_t> ints;
  std::vector<double> flts;
  std::vector<Args> arg_frames;
  struct NewObject { std::unique_ptr<SimObject> owned; std::uint32_t id = 0; std::uint32_t fail = 0; };
  std::vector<NewObject> creation;
  Value* var = nullptr;
  bool var_bound = false;
  std::uint32_t obj_id = 0;
  SimObject* obj_new = nullptr;  // current object before it is registered
  std::string field, field_index;
  std::size_t steps = 0;

  auto fail = [&](const std::string& what, std::uint32_t at) -> ScriptError {
    return ScriptError{what + " at word " + std::to_string(at)};
  };
  auto need = [&](std::uint32_t at, std::size_t count) {
    if (at + count >= code.size()) throw fail("truncated instruction", at);
  };
  auto ident = [&](std::uint32_t at) {
    std::string s;
    block->ident(at, s);
    return s;
  };
  auto pop_u = [&](std::uint32_t at) {
    if (ints.empty()) throw fail("integer stack underflow", at);
    auto v = ints.back(); ints.pop_back(); return v;
  };
  auto pop_f = [&](std::uint32_t at) {
    if (flts.empty()) throw fail("float stack underflow", at);
    auto v = flts.back(); flts.pop_back(); return v;
  };
  auto push_u = [&](std::uint32_t v, std::uint32_t at) {
    if (ints.size() >= limits.stack) throw fail("integer stack limit", at);
    ints.push_back(v);
  };
  auto push_f = [&](double v, std::uint32_t at) {
    if (flts.size() >= limits.stack) throw fail("float stack limit", at);
    flts.push_back(v);
  };
  auto cur_object = [&]() -> SimObject* {
    if (obj_new) return obj_new;
    return obj_id ? object(obj_id) : nullptr;
  };
  auto lookup_var = [&](const std::string& name, bool create) -> Value* {
    var_bound = false;
    if (name.empty()) return nullptr;
    if (name[0] == '%') {
      if (!in_function) {
        warn("Accessing local variable in global scope... failed: " + name);
        return nullptr;
      }
      auto key = lower(name);
      auto it = frame.locals.find(key);
      if (it == frame.locals.end()) {
        if (!create) return nullptr;
        it = frame.locals.emplace(key, std::make_pair(name, Value{})).first;
      }
      return &it->second.second;
    }
    auto key = lower(name);
    auto it = globals.find(key);
    if (it == globals.end()) {
      if (!create) return nullptr;
      it = globals.emplace(key, std::make_pair(name, Value{})).first;
    }
    var_bound = bound.count(key) != 0;
    return &it->second.second;
  };
  auto field_key = [&]() { return field + field_index; };

  std::uint32_t ip = start;
  for (;;) {
    if (ip >= code.size()) throw fail("fell off the end of the code", ip);
    if (++steps > limits.steps) throw fail("step limit", ip);
    const std::uint32_t at = ip;
    const std::uint32_t op = code[ip++];
    switch (op) {
      case FUNC_DECL: {
        need(at, 6);
        const std::uint32_t argc = code[at + 6];
        need(at, 6 + argc);
        const bool has_body = code[at + 4] != 0;
        const std::uint32_t end = code[at + 5];
        if (has_body) {
          Function f;
          f.name = ident(at + 1);
          f.space = ident(at + 2);
          f.package = ident(at + 3);
          f.code = block;
          f.ip = at + 7 + argc;
          for (std::uint32_t i = 0; i < argc; ++i) f.args.push_back(ident(at + 7 + i));
          if (!f.package.empty()) package_names[lower(f.package)] = f.package;
          auto* ns = space(f.space, true);
          ns->layers[lower(f.package)][lower(f.name)] = f;
          ip = end;
        } else {
          ip = at + 7 + argc;
        }
        break;
      }
      case CREATE_OBJECT: {
        need(at, 3);
        std::string parent;
        const bool has_parent = block->ident(at + 1, parent) && !parent.empty();
        const bool datablock = code[at + 2] != 0;
        const std::uint32_t fail_ip = code[at + 3];
        ip = at + 4;
        if (arg_frames.empty()) throw fail("no argument frame", at);
        Args args = std::move(arg_frames.back());
        arg_frames.pop_back();
        if (no_calls) { ip = fail_ip; break; }
        const std::string cls = args.empty() ? std::string() : args[0];
        const ClassInfo* info = find_class(cls);
        const std::string where = block->file_line(at);
        if (!info || !info->creatable) {
          warn(where + ": Unable to instantiate non-conobject class " + cls + ".");
          ip = fail_ip;
          break;
        }
        if (datablock) {
          warn(where + ": Unable to instantiate non-datablock class " + cls + ".");
          ip = fail_ip;
          break;
        }
        auto o = std::make_unique<SimObject>();
        o->class_name = info->name;
        o->info = info;
        o->name = args.size() > 1 ? args[1] : std::string();
        if (has_parent) {
          SimObject* p = find_object(parent);
          if (!p) {
            warn(where + ": Unable to find parent object " + parent + " for " + cls + ".");
            ip = fail_ip;
            break;
          }
          o->fields = p->fields;
        }
        obj_new = o.get();
        creation.push_back({std::move(o), 0, fail_ip});
        break;
      }
      case ADD_OBJECT: {
        need(at, 1);
        const bool root = code[at + 1] != 0;
        ip = at + 2;
        if (creation.empty() || !creation.back().owned) throw fail("no object to add", at);
        const std::uint32_t id = register_object(std::move(creation.back().owned));
        creation.back().id = id;
        SimObject* o = object(id);
        obj_new = nullptr;
        obj_id = id;
        if (!root) {
          if (ints.empty()) throw fail("integer stack underflow", at);
          if (SimObject* parent = object(ints.back())) add_to_set(parent, o);
        } else {
          SimObject* group = find_object(global("$instantGroup").str());
          if (!group || !group->info || !group->info->is_group) group = root_group();
          add_to_set(group, o);
        }
        push_u(id, at);
        break;
      }
      case END_OBJECT: {
        need(at, 1);
        const bool root = code[at + 1] != 0;
        ip = at + 2;
        if (root) {
          const auto v = pop_u(at);
          if (ints.empty()) throw fail("integer stack underflow", at);
          ints.back() = v;
        } else {
          pop_u(at);
        }
        if (creation.empty()) throw fail("no object to end", at);
        creation.pop_back();
        obj_new = nullptr;
        if (!creation.empty()) {
          if (creation.back().owned) obj_new = creation.back().owned.get();
          else obj_id = creation.back().id;
        }
        break;
      }
      case JMPIFFNOT: case JMPIFNOT: case JMPIFF: case JMPIF: case JMPIFNOT_NP:
      case JMPIF_NP: case JMP: {
        need(at, 1);
        const std::uint32_t target = code[at + 1];
        if (target >= code.size()) throw fail("jump outside code", at);
        bool jump = true;
        if (op == JMPIFFNOT) jump = pop_f(at) == 0;
        else if (op == JMPIFF) jump = pop_f(at) != 0;
        else if (op == JMPIFNOT) jump = pop_u(at) == 0;
        else if (op == JMPIF) jump = pop_u(at) != 0;
        else if (op == JMPIFNOT_NP || op == JMPIF_NP) {
          if (ints.empty()) throw fail("integer stack underflow", at);
          const bool value = ints.back() != 0;
          jump = op == JMPIF_NP ? value : !value;
          if (!jump) ints.pop_back();
        }
        ip = jump ? target : at + 2;
        break;
      }
      case RETURN:
        return str.back();
      case CMPEQ: case CMPGR: case CMPGE: case CMPLT: case CMPLE: case CMPNE: {
        const double a = pop_f(at), b = pop_f(at);
        bool r = false;
        switch (op) {
          case CMPEQ: r = a == b; break;
          case CMPGR: r = a > b; break;
          case CMPGE: r = a >= b; break;
          case CMPLT: r = a < b; break;
          case CMPLE: r = a <= b; break;
          default: r = a != b; break;
        }
        push_u(r ? 1 : 0, at);
        break;
      }
      case XOR: case MOD: case BITAND: case BITOR: case SHR: case SHL: case AND: case OR: {
        const std::uint32_t a = pop_u(at), b = pop_u(at);
        std::uint32_t r = 0;
        switch (op) {
          case XOR: r = a ^ b; break;
          case MOD: {
            const auto sa = static_cast<std::int32_t>(a), sb = static_cast<std::int32_t>(b);
            r = (sb == 0 || (sa == INT32_MIN && sb == -1)) ? 0 : static_cast<std::uint32_t>(sa % sb);
            break;
          }
          case BITAND: r = a & b; break;
          case BITOR: r = a | b; break;
          case SHR: r = b >= 32 ? 0 : a >> b; break;
          case SHL: r = b >= 32 ? 0 : a << b; break;
          case AND: r = (a && b) ? 1 : 0; break;
          default: r = (a || b) ? 1 : 0; break;
        }
        push_u(r, at);
        break;
      }
      case NOT: push_u(pop_u(at) == 0 ? 1 : 0, at); break;
      case NOTF: push_u(pop_f(at) == 0 ? 1 : 0, at); break;
      case ONESCOMPLEMENT: push_u(~pop_u(at), at); break;
      case ADD: case SUB: case MUL: case DIV: {
        const double a = pop_f(at), b = pop_f(at);
        double r = 0;
        if (op == ADD) r = a + b;
        else if (op == SUB) r = a - b;
        else if (op == MUL) r = a * b;
        else r = a / b;
        push_f(r, at);
        break;
      }
      case NEG: push_f(-pop_f(at), at); break;
      case SETCURVAR: case SETCURVAR_CREATE:
        need(at, 1);
        var = lookup_var(ident(at + 1), op == SETCURVAR_CREATE);
        ip = at + 2;
        break;
      case SETCURVAR_ARRAY: case SETCURVAR_ARRAY_CREATE:
        var = lookup_var(str.back(), op == SETCURVAR_ARRAY_CREATE);
        break;
      case LOADVAR_UINT: push_u(var ? var->u32() : 0, at); break;
      case LOADVAR_FLT: push_f(var ? var->f64() : 0, at); break;
      case LOADVAR_STR: str.back() = var ? var->str() : std::string(); break;
      case SAVEVAR_UINT:
        if (ints.empty()) throw fail("integer stack underflow", at);
        if (var) *var = var_bound ? Value::of_string(format_int(ints.back())) : Value::of_int(ints.back());
        break;
      case SAVEVAR_FLT:
        if (flts.empty()) throw fail("float stack underflow", at);
        if (var) *var = var_bound ? Value::of_string(format_float(flts.back())) : Value::of_float(flts.back());
        break;
      case SAVEVAR_STR:
        if (var) *var = Value::of_string(str.back());
        break;
      case SETCUROBJECT: {
        SimObject* o = find_object(str.back());
        obj_new = nullptr;
        obj_id = o ? o->id : 0;
        break;
      }
      case SETCUROBJECT_NEW:
        obj_new = nullptr;
        obj_id = 0;
        if (!creation.empty()) {
          if (creation.back().owned) obj_new = creation.back().owned.get();
          else obj_id = creation.back().id;
        }
        break;
      case SETCURFIELD:
        need(at, 1);
        field = ident(at + 1);
        field_index.clear();
        ip = at + 2;
        break;
      case SETCURFIELD_ARRAY: field_index = str.back(); break;
      case LOADFIELD_UINT: case LOADFIELD_FLT: case LOADFIELD_STR: {
        SimObject* o = cur_object();
        const std::string value = o ? o->field(field_key()) : std::string();
        if (op == LOADFIELD_UINT) push_u(parse_int(value), at);
        else if (op == LOADFIELD_FLT) push_f(parse_float(value), at);
        else str.back() = value;
        break;
      }
      case SAVEFIELD_UINT: case SAVEFIELD_FLT: case SAVEFIELD_STR: {
        std::string value;
        if (op == SAVEFIELD_UINT) {
          if (ints.empty()) throw fail("integer stack underflow", at);
          value = format_int(ints.back());
        } else if (op == SAVEFIELD_FLT) {
          if (flts.empty()) throw fail("float stack underflow", at);
          value = format_float(flts.back());
        } else {
          value = str.back();
        }
        if (SimObject* o = cur_object()) o->set_field(field_key(), value);
        break;
      }
      case STR_TO_UINT: push_u(parse_int(str.back()), at); break;
      case STR_TO_FLT: push_f(parse_float(str.back()), at); break;
      case STR_TO_NONE: break;
      case FLT_TO_UINT: push_u(to_u32(pop_f(at)), at); break;
      case FLT_TO_STR: str.back() = format_float(pop_f(at)); break;
      case FLT_TO_NONE: pop_f(at); break;
      case UINT_TO_FLT: push_f(static_cast<double>(static_cast<std::int32_t>(pop_u(at))), at); break;
      case UINT_TO_STR: str.back() = format_int(pop_u(at)); break;
      case UINT_TO_NONE: pop_u(at); break;
      case LOADIMMED_UINT: need(at, 1); push_u(code[at + 1], at); ip = at + 2; break;
      case LOADIMMED_FLT: need(at, 1); push_f(block->float_at(in_function, code[at + 1]), at); ip = at + 2; break;
      case LOADIMMED_STR: need(at, 1); str.back() = block->string_at(in_function, code[at + 1]); ip = at + 2; break;
      case LOADIMMED_IDENT: need(at, 1); str.back() = ident(at + 1); ip = at + 2; break;
      case CALLFUNC_RESOLVE: case CALLFUNC: {
        need(at, 3);
        const std::string name = ident(at + 1);
        std::string ns_name;
        const bool has_ns = block->ident(at + 2, ns_name) && !ns_name.empty();
        const std::uint32_t type = code[at + 3];
        ip = at + 4;
        if (arg_frames.empty()) throw fail("no argument frame", at);
        Args args;
        args.reserve(arg_frames.back().size() + 1);
        args.push_back(name);
        for (auto& a : arg_frames.back()) args.push_back(std::move(a));
        arg_frames.pop_back();
        if (no_calls) { str.back().clear(); break; }
        const std::string where = block->file_line(at);
        Resolved r;
        SimObject* self = nullptr;
        if (type == 0) {
          Namespace* ns = space(has_ns ? ns_name : std::string(), false);
          if (ns) r = resolve(ns, name);
          if (!r.fn) {
            warn(where + ": Unable to find function " + (has_ns ? ns_name + "::" : std::string()) + name);
            str.back().clear();
            break;
          }
          if (r.fn->native && args.size() > 1 && r.space && !r.space->name.empty())
            self = find_object(args[1]);
        } else if (type == 1) {
          self = args.size() > 1 ? find_object(args[1]) : nullptr;
          if (!self) {
            warn(where + ": Unable to find object: '" + (args.size() > 1 ? args[1] : std::string()) +
                 "' attempting to call function '" + name + "'");
            str.back().clear();
            break;
          }
          args[1] = std::to_string(self->id);
          r = resolve(self->space, name);
          if (!r.fn) {
            warn(where + ": Unknown command " + name + ".");
            std::string chain;
            for (Namespace* n = self->space; n; n = n->parent)
              chain += (chain.empty() ? "" : " -> ") + n->name;
            warn("  Object " + self->name + "(" + std::to_string(self->id) + ") " + chain);
            str.back().clear();
            break;
          }
        } else {
          if (fn) r = resolve_parent(*fn);
          if (!r.fn) {
            trace.push_back(where + ": Parent::" + name + " has no parent");
            str.back().clear();
            break;
          }
          if (r.fn->native && args.size() > 1) self = find_object(args[1]);
        }
        std::string result = invoke(r, args, self, where);
        str.back() = std::move(result);
        break;
      }
      case ADVANCE_STR: str.emplace_back(); break;
      case ADVANCE_STR_APPENDCHAR:
        need(at, 1);
        str.back().push_back(static_cast<char>(code[at + 1]));
        str.emplace_back();
        ip = at + 2;
        break;
      case ADVANCE_STR_COMMA: str.back().push_back('_'); str.emplace_back(); break;
      case ADVANCE_STR_NUL: str.emplace_back(); break;
      case REWIND_STR: {
        if (str.size() < 2) throw fail("string stack underflow", at);
        std::string top = std::move(str.back());
        str.pop_back();
        str.back() += top;
        break;
      }
      case TERMINATE_REWIND_STR:
        if (str.size() < 2) throw fail("string stack underflow", at);
        str.pop_back();
        break;
      case COMPARE_STR: {
        if (str.size() < 2) throw fail("string stack underflow", at);
        std::string right = std::move(str.back());
        str.pop_back();
        push_u(iequal(str.back(), right) ? 1 : 0, at);
        break;
      }
      case PUSH:
        if (arg_frames.empty()) throw fail("no argument frame", at);
        if (arg_frames.back().size() >= 1024) throw fail("argument limit", at);
        arg_frames.back().push_back(str.back());
        break;
      case PUSH_FRAME:
        if (arg_frames.size() >= limits.stack) throw fail("argument frame limit", at);
        arg_frames.emplace_back();
        break;
      default:
        // TAG_TO_STR and BREAK are not used by any shipped 3.x script; their
        // runtime behaviour is unread, so they fail instead of guessing.
        throw fail("unsupported opcode " + std::to_string(op), at);
    }
    if (str.size() > limits.stack) throw fail("string stack limit", at);
  }
}

} // namespace Torque
