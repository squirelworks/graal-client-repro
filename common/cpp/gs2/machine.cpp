// The GS2 executor: TScriptExecutionSpace as Graal_analysis
// `client-internals/gs2-vm-from-engines.md` reads it in the 4.2.0.8, 5.0.0.7
// and 6.00 engines. Opcodes whose effect that read did not open are refused
// with an error instead of guessed (README.md lists them).

#include <algorithm>
#include <climits>
#include <cstdint>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>

#include "gs2.hpp"

namespace gs2 {

namespace {

constexpr std::size_t kStackCap = 10000;      // the value stack refuses to pass 10000
constexpr std::size_t kMaxFrames = 9999;      // more than 9999 stacked frames: overrun
constexpr std::size_t kMaxActions = 9999;     // more than 9999 queued actions: overrun
constexpr int kLoopLimit = 10000;             // the 10001st loop check stops the script
constexpr std::size_t kMaxErrors = 20;        // distinct error texts kept
constexpr std::size_t kSlots = 1024;          // frame slots 0..1023
constexpr double kDue = 0.0001;               // a timeout is due below this
constexpr double kStep2D = 0.05;              // one 2D script pass

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

bool startsWithCi(const std::string& s, const std::string& prefix) {
  return s.size() >= prefix.size() && lower(s.substr(0, prefix.size())) == prefix;
}

// Floor toward negative infinity: the conversion the engines use for the
// direction index and the fused remainder.
long floorInt(double d) { return static_cast<long>(std::floor(d)); }

std::int32_t toInt32(double d) {
  if (!std::isfinite(d)) return 0;
  const double t = std::trunc(d);
  if (t >= 2147483648.0 || t < -2147483648.0) {
    const double m = std::fmod(t, 4294967296.0);
    return static_cast<std::int32_t>(static_cast<std::uint32_t>(static_cast<std::int64_t>(m)));
  }
  return static_cast<std::int32_t>(t);
}

}  // namespace

bool opcodeImplemented(int op) {
  if (op >= 1 && op <= 10) return true;
  if (op >= 20 && op <= 27) return true;
  if (op >= 30 && op <= 37) return true;
  if (op >= 60 && op <= 79) return true;
  if (op >= 200 && op <= 240) return true;
  switch (op) {
    case 40: case 42: case 43: case 47: case 48: case 49: case 121: case 115: case 119:
    case 163: case 242:
    case 44: case 45: case 46: case 50: case 51: case 52: case 53:
    case 85: case 86: case 87: case 88: case 89: case 90: case 91: case 93: case 94:
    case 97: case 98: case 101: case 102: case 103:
    case 110: case 111: case 112: case 113: case 114: case 116: case 117:
    case 130: case 131: case 132: case 150: case 151:
    case 180: case 181: case 182: case 183: case 184: case 189: case 190:
      return true;
    default:
      return false;
  }
}

// ------------------------------------------------------------ the state

struct Machine::Frame {
  std::shared_ptr<const Script> script;
  VarPtr thiso;
  std::size_t returnPc = 0;
  std::size_t stackBase = 0;  // stack height at the call, arguments already taken
  std::size_t savedStack = 0;
  VarPtr locals;              // temp
  VarPtr params;
  std::vector<Value> args;
  std::vector<Value> slots;
};

struct Machine::Exec {
  Machine::Space* sp = nullptr;
  std::vector<Value> stack;
  std::vector<Frame> frames;
  std::vector<VarPtr> with;
  std::size_t pc = 0;
  int loops = 0;
  bool stopped = false;
  bool suspended = false;
  double wake = 0;
  Value result;
};

struct Machine::Space {
  VarPtr var;
  std::shared_ptr<const Script> script;
  bool initialized = false;
  struct Action { std::string name; std::vector<Value> args; };
  std::deque<Action> actions;
  struct Scheduled { double deadline; std::string name; std::vector<Value> args; };
  std::vector<Scheduled> scheduled;
  std::vector<std::unique_ptr<Exec>> sleeping;
};

Machine::Machine(Profile profile) : profile_(profile), universe_(std::make_shared<Var>("universe")) {}
Machine::~Machine() = default;

VarPtr Machine::newVar(const std::string& name) { return universe_->childOrCreate(name); }

Machine::Space* Machine::space(const VarPtr& var, bool create) {
  if (!var) return nullptr;
  auto it = spaces_.find(var.get());
  if (it != spaces_.end()) return it->second.get();
  if (!create) return nullptr;
  auto sp = std::make_unique<Space>();
  sp->var = var;
  Space* raw = sp.get();
  spaces_[var.get()] = std::move(sp);
  order_.push_back(raw);
  return raw;
}

bool Machine::hasScript(const VarPtr& var) const {
  auto it = spaces_.find(var.get());
  return it != spaces_.end() && it->second->script != nullptr;
}

bool Machine::setScript(const VarPtr& var, const std::string& bytes, std::string* error) {
  auto r = load(bytes, profile_);
  if (!r.ok()) {
    if (error) *error = r.error;
    if (Space* sp = space(var, false)) { sp->script.reset(); sp->initialized = false; }
    return false;
  }
  return setScript(var, std::shared_ptr<const Script>(r.script));
}

bool Machine::setScript(const VarPtr& var, std::shared_ptr<const Script> script) {
  Space* sp = space(var, true);
  if (!sp) return false;
  sp->sleeping.clear();
  if (!script || script->code.empty()) {
    sp->script.reset();
    sp->initialized = false;
    return script != nullptr;
  }
  sp->script = std::move(script);
  queueEvent(var, "created");
  return true;
}

bool Machine::queueEvent(const VarPtr& var, const std::string& name, std::vector<Value> args) {
  Space* sp = space(var, false);
  if (!sp || !sp->script) return false;
  if (sp->actions.size() >= kMaxActions) {
    error("Events number overrun for " + name, sp);
    return false;
  }
  sp->actions.push_back({lower(name), std::move(args)});
  return true;
}

void Machine::invokeInitialized(const VarPtr& var) {
  Space* sp = space(var, false);
  if (!sp || !sp->script) return;
  sp->initialized = true;
  sp->actions.erase(std::remove_if(sp->actions.begin(), sp->actions.end(),
                                   [](const Space::Action& a) { return a.name == "created"; }),
                    sp->actions.end());
  queueEvent(var, "initialized");
}

void Machine::scheduleEvent(const VarPtr& var, double delay, const std::string& name, std::vector<Value> args) {
  Space* sp = space(var, false);
  if (!sp || !sp->script) return;
  sp->scheduled.push_back({clock_ + delay, lower(name), std::move(args)});
}

void Machine::cancelEvents(const VarPtr& var, const std::string& name) {
  Space* sp = space(var, false);
  if (!sp) return;
  const std::string n = lower(name);
  sp->scheduled.erase(std::remove_if(sp->scheduled.begin(), sp->scheduled.end(),
                                     [&](const Space::Scheduled& s) { return s.name == n; }),
                      sp->scheduled.end());
  sp->actions.erase(std::remove_if(sp->actions.begin(), sp->actions.end(),
                                   [&](const Space::Action& a) { return a.name == n; }),
                    sp->actions.end());
}

void Machine::addCommand(const std::string& name, const std::string& signature, Command fn) {
  commands_[lower(name)] = {signature, std::move(fn)};
}

double Machine::random01() {
  rng_ = rng_ * 1103515245u + 12345u;
  return static_cast<double>((rng_ >> 8) & 0xFFFFFF) / 16777216.0;
}

void Machine::error(const std::string& text, const Space* sp) {
  std::string full = "GraalScript: " + text;
  if (sp && sp->var) full += " in script of " + sp->var->name();
  if (std::find(errors_.begin(), errors_.end(), full) != errors_.end()) return;
  if (errors_.size() >= kMaxErrors) return;
  errors_.push_back(full);
}

std::string Machine::numberText(double d) {
  char buf[64];
  if (std::isfinite(d) && d == std::floor(d) && std::fabs(d) < 1e15) {
    std::snprintf(buf, sizeof buf, "%.0f", d);
    if (std::string(buf) == "-0") return "0";
  } else {
    std::snprintf(buf, sizeof buf, "%.15g", d);
  }
  return buf;
}

// ------------------------------------------------------- conversions

namespace {

VarPtr refTarget(const Ref& r, bool create) {
  if (r.var) return r.var;
  if (!r.owner) return nullptr;
  if (r.index >= 0) {
    auto& el = r.owner->elements();
    if (static_cast<std::size_t>(r.index) < el.size()) return el[static_cast<std::size_t>(r.index)];
    return nullptr;
  }
  return create ? r.owner->childOrCreate(r.key) : r.owner->child(r.key);
}

}  // namespace

VarPtr Machine::resolveName(Exec& ex, const std::string& name, bool create) {
  const std::string n = lower(name);
  Frame* fr = ex.frames.empty() ? nullptr : &ex.frames.back();
  VarPtr thiso = fr ? fr->thiso : (ex.sp ? ex.sp->var : nullptr);
  if (n == "temp") return fr ? fr->locals : universe_;
  if (n == "params") return fr ? fr->params : nullptr;
  if (n == "this") return ex.with.empty() ? thiso : ex.with.back();
  if (n == "thiso") return thiso;
  if (n == "player") return player_;
  if (n == "playero" || n == "client" || n == "clientr" || n == "serverr") return playero_;
  if (n == "level") return level_;

  for (auto it = ex.with.rbegin(); it != ex.with.rend(); ++it)
    if (*it) {
      if (auto v = (*it)->child(name)) return v;
      if (create && (*it)->acceptsProperty(name)) return (*it)->childOrCreate(name);
    }
  if (fr && fr->locals)
    if (auto v = fr->locals->child(name)) return v;
  if (thiso) {
    if (auto v = thiso->child(name)) return v;
    if (create && thiso->acceptsProperty(name)) return thiso->childOrCreate(name);
  }
  if (level_)
    if (auto v = level_->child(name)) return v;
  if (auto v = universe_->child(name)) return v;
  if (create) return universe_->childOrCreate(name);
  if (playero_)
    if (auto v = playero_->child(name)) return v;
  return nullptr;
}

double Machine::toNumber(const Value& v) const {
  switch (v.tag) {
    case Value::Tag::Number: return v.num;
    case Value::Tag::String: return std::strtod(v.str.c_str(), nullptr);
    case Value::Tag::Ref: {
      auto t = refTarget(v.ref, false);
      return t ? t->number() : 0;
    }
    case Value::Tag::Name: {
      auto t = universe_->child(v.str);
      return t ? t->number() : 0;
    }
    default: return 0;
  }
}

std::string Machine::toString(const Value& v) const {
  switch (v.tag) {
    case Value::Tag::Number: return numberText(v.num);
    case Value::Tag::String: return v.str;
    case Value::Tag::Object: return v.obj ? v.obj->name() : std::string();
    case Value::Tag::Ref: {
      auto t = refTarget(v.ref, false);
      return t ? t->string() : std::string();
    }
    case Value::Tag::Name: {
      auto t = universe_->child(v.str);
      return t ? t->string() : std::string();
    }
    default: return std::string();
  }
}

VarPtr Machine::toObject(const Value& v) const {
  VarPtr t;
  switch (v.tag) {
    case Value::Tag::Object: return v.obj;
    case Value::Tag::Ref: t = refTarget(v.ref, false); break;
    case Value::Tag::Name: t = universe_->child(v.str); break;
    case Value::Tag::String: return universe_->child(v.str);
    default: return nullptr;
  }
  if (t && t->kind() == Var::Kind::Object) return t->object();
  return t;
}

// ------------------------------------------------------------ running

void Machine::runAction(Space& sp, const std::string& name, std::vector<Value> args) {
  if (!sp.script) return;
  const Function* f = sp.script->findFunction("on" + name);
  if (!f) return;
  auto ex = std::make_unique<Exec>();
  ex->sp = &sp;
  Frame fr;
  fr.script = sp.script;
  fr.thiso = sp.var;
  fr.returnPc = SIZE_MAX;
  fr.locals = std::make_shared<Var>("temp");
  fr.params = std::make_shared<Var>("params");
  fr.params->setArray(args.size());
  for (std::size_t i = 0; i < args.size(); ++i) {
    auto& el = fr.params->elements()[i];
    if (args[i].tag == Value::Tag::String) el->setString(args[i].str);
    else if (args[i].tag == Value::Tag::Object) el->setObject(args[i].obj);
    else el->setNumber(toNumber(args[i]));
  }
  fr.args = std::move(args);
  ex->frames.push_back(std::move(fr));
  ex->pc = f->index;
  execute(*ex);
  if (ex->suspended) sp.sleeping.push_back(std::move(ex));
}

Value Machine::callFunction(const VarPtr& var, const std::string& name, std::vector<Value> args) {
  Space* sp = space(var, false);
  if (!sp || !sp->script) return Value::number(0);
  const Function* f = sp->script->findFunction(name);
  if (!f) {
    if (logMissingFunctions) error("Function " + var->name() + " " + name + " not found", sp);
    return Value::number(0);
  }
  auto ex = std::make_unique<Exec>();
  ex->sp = sp;
  Frame fr;
  fr.script = sp->script;
  fr.thiso = var;
  fr.returnPc = SIZE_MAX;
  fr.locals = std::make_shared<Var>("temp");
  fr.params = std::make_shared<Var>("params");
  fr.args = std::move(args);
  ex->frames.push_back(std::move(fr));
  ex->pc = f->index;
  Value v = execute(*ex);
  if (ex->suspended) {
    sp->sleeping.push_back(std::move(ex));
    return Value::number(0);
  }
  return v;
}

void Machine::runDue() {
  // Sleepers and scheduled events first, then the queued actions. Work
  // queued while this pass runs waits for the next one.
  const std::vector<Space*> spaces = order_;
  for (Space* sp : spaces) {
    for (std::size_t i = 0; i < sp->sleeping.size();) {
      if (sp->sleeping[i]->wake - clock_ < kDue) {
        std::unique_ptr<Exec> ex = std::move(sp->sleeping[i]);
        sp->sleeping.erase(sp->sleeping.begin() + static_cast<long>(i));
        ex->suspended = false;
        ex->loops = 0;
        execute(*ex);
        if (ex->suspended) sp->sleeping.push_back(std::move(ex));
      } else {
        ++i;
      }
    }
    for (std::size_t i = 0; i < sp->scheduled.size();) {
      if (sp->scheduled[i].deadline - clock_ < kDue) {
        auto s = std::move(sp->scheduled[i]);
        sp->scheduled.erase(sp->scheduled.begin() + static_cast<long>(i));
        queueEvent(sp->var, s.name, std::move(s.args));
      } else {
        ++i;
      }
    }
  }
  for (Space* sp : spaces) {
    std::size_t n = sp->actions.size();
    while (n-- > 0 && !sp->actions.empty()) {
      auto a = std::move(sp->actions.front());
      sp->actions.pop_front();
      runAction(*sp, a.name, std::move(a.args));
    }
  }
}

void Machine::runScripts() {
  clock_ += kStep2D;
  runDue();
}

// ------------------------------------------------------------ executor

namespace {

int compare3(const Machine& m, const Value& x, const Value& y) {
  using T = Value::Tag;
  auto cmpNum = [](double a, double b) { return std::fabs(a - b) < 0.0001 ? 0 : (a < b ? -1 : 1); };
  if (x.tag == T::String && y.tag == T::String) {
    const std::string a = lower(x.str), b = lower(y.str);
    return a == b ? 0 : (a < b ? -1 : 1);
  }
  if (x.tag == T::Object && y.tag == T::Object) {
    const auto a = reinterpret_cast<std::uintptr_t>(x.obj.get()), b = reinterpret_cast<std::uintptr_t>(y.obj.get());
    return a == b ? 0 : (a < b ? -1 : 1);
  }
  if (x.tag == T::Object || y.tag == T::Object) {
    const Value& o = x.tag == T::Object ? x : y;
    const Value& other = x.tag == T::Object ? y : x;
    if (other.tag == T::String && o.obj) {
      const std::string a = lower(o.obj->name()), b = lower(other.str);
      const int r = a == b ? 0 : (a < b ? -1 : 1);
      return x.tag == T::Object ? r : -r;
    }
    if (other.tag == T::Number) {
      const double p = static_cast<double>(reinterpret_cast<std::uintptr_t>(o.obj.get()));
      const int r = cmpNum(p, other.num);
      return x.tag == T::Object ? r : -r;
    }
    return 0;
  }
  return cmpNum(m.toNumber(x), m.toNumber(y));
}

}  // namespace

Value Machine::execute(Exec& ex) {
  Space* sp = ex.sp;
  auto fail = [&](const std::string& text) {
    error(text, sp);
    ex.stopped = true;
  };
  auto push = [&](Value v) {
    if (ex.stack.size() >= kStackCap) { fail("Stack overflow"); return; }
    ex.stack.push_back(std::move(v));
  };
  auto pop = [&](Value& out) -> bool {
    if (ex.stack.empty()) { fail("Stack underflow"); return false; }
    out = std::move(ex.stack.back());
    ex.stack.pop_back();
    return true;
  };
  auto frame = [&]() -> Frame& { return ex.frames.back(); };

  // A name or reference on the stack, as the variable it names.
  auto varOf = [&](const Value& v, bool create) -> VarPtr {
    if (v.tag == Value::Tag::Ref) return refTarget(v.ref, create);
    if (v.tag == Value::Tag::Name) return resolveName(ex, v.str, create);
    return nullptr;
  };
  // A stack value read out to a plain number, string or object.
  auto deref = [&](const Value& v) -> Value {
    if (v.tag != Value::Tag::Ref && v.tag != Value::Tag::Name) return v;
    auto t = varOf(v, false);
    if (!t) return Value::number(0);
    switch (t->kind()) {
      case Var::Kind::Number: return Value::number(t->number());
      case Var::Kind::String: return Value::string(t->string());
      case Var::Kind::Object: return Value::object(t->object());
      default: return Value::object(t);
    }
  };
  auto num = [&](const Value& v) { return toNumber(deref(v)); };
  auto str = [&](const Value& v) { return toString(deref(v)); };
  auto obj = [&](const Value& v) -> VarPtr {
    if (v.tag == Value::Tag::Ref || v.tag == Value::Tag::Name) {
      auto t = varOf(v, false);
      if (t && t->kind() == Var::Kind::Object) return t->object();
      return t;
    }
    return toObject(v);
  };
  auto assign = [&](const Value& target, const Value& value) {
    auto t = varOf(target, true);
    if (!t) return;  // a constant or a missing element: nothing to store into
    if (value.tag == Value::Tag::Ref || value.tag == Value::Tag::Name) {
      auto s = varOf(value, false);
      if (s) t->assignFrom(*s);
      else t->setNumber(0);
      return;
    }
    switch (value.tag) {
      case Value::Tag::String: t->setString(value.str); break;
      case Value::Tag::Object:
        if (value.obj && value.obj->kind() == Var::Kind::Array) t->assignFrom(*value.obj);
        else t->setObject(value.obj);
        break;
      default: t->setNumber(value.num); break;
    }
  };
  auto slot = [&](std::size_t i) -> Value& {
    auto& s = frame().slots;
    if (s.size() <= i) s.resize(i + 1);
    return s[i];
  };
  auto binop = [&](int op, double a, double b, bool fused) -> double {
    switch (op) {
      case 60: return a + b;
      case 61: return a - b;
      case 62: return a * b;
      case 63: return (fused && b == 0) ? 0 : (b == 0 ? 0 : a / b);
      case 64: return b == 0 ? 0 : a - b * static_cast<double>(floorInt(a / b));
      case 65: return std::pow(a, b);
      case 66: return (a != 0 && b != 0) ? 1 : 0;
      default: return (a != 0 || b != 0) ? 1 : 0;  // 67
    }
  };
  auto compare = [&](int op, const Value& a, const Value& b) -> double {
    const int c = compare3(*this, deref(a), deref(b));
    switch (op) {
      case 72: return c < 0;
      case 73: return c > 0;
      case 74: return c <= 0;
      default: return c >= 0;  // 75
    }
  };
  bool runUnfused = false;
  // The object conversion that creates a missing name (36, 230, 238).
  auto objCreate = [&](const Value& v) -> VarPtr {
    if (v.tag == Value::Tag::Ref || v.tag == Value::Tag::Name) {
      auto t = varOf(v, true);
      if (t && t->kind() == Var::Kind::Object) return t->object();
      return t;
    }
    return toObject(v);
  };
  auto newObject = [&](const std::string& type, const std::string& name) -> VarPtr {
    VarPtr o = factory_ ? factory_(*this, type, name) : nullptr;
    if (!o) {
      o = std::make_shared<Var>(name, type);
      o->setAcceptsAllProperties(true);
    }
    objects_.push_back(o);
    return o;
  };
  // A count on the stack, truncated toward zero (48 adds 0.0001 first).
  auto count = [&](double d) -> long {
    long n = static_cast<long>(std::trunc(d));
    if (d < 0 && static_cast<double>(n) != d) n -= 1;
    return n;
  };
  auto unimplemented = [&](int op) {
    fail("opcode " + std::to_string(op) + " (" + opcodeName(op) + ") is not implemented");
  };

  while (!ex.stopped && !ex.suspended) {
    if (ex.frames.empty()) { ex.stopped = true; break; }
    const Script& s = *frame().script;
    if (ex.pc >= s.code.size()) { ex.stopped = true; break; }
    const Instruction& in = s.code[ex.pc];
    const int op = runUnfused ? in.loadedOp : in.op;
    runUnfused = false;
    ++executed_;
    std::size_t next = ex.pc + 1;
    const auto target = static_cast<std::size_t>(std::max(0.0, std::trunc(in.num)));

    if (!opcodeInProfile(op, profile_)) {
      fail("unknown opcode " + std::to_string(op) + " for engine " + profileName(profile_));
      break;
    }

    Value a, b, c;
    switch (op) {
      case 1: next = target; break;
      case 2:
        if (!pop(a)) break;
        if (num(a) != 0) next = target;
        break;
      case 3:  // or: true keeps the value and jumps
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        if (num(ex.stack.back()) != 0) next = target;
        else ex.stack.pop_back();
        break;
      case 4:  // if: false jumps
        if (!pop(a)) break;
        if (num(a) == 0) next = target;
        break;
      case 5:  // and: false keeps the value and jumps
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        if (num(ex.stack.back()) == 0) next = target;
        else ex.stack.pop_back();
        break;
      case 6: {  // call
        if (!pop(a)) break;
        std::vector<Value> args;
        bool marked = false;
        while (!ex.stack.empty()) {
          Value v = std::move(ex.stack.back());
          ex.stack.pop_back();
          if (v.tag == Value::Tag::Marker) { marked = true; break; }
          args.push_back(std::move(v));
        }
        if (!marked) { fail("call without an argument marker"); break; }
        std::string fname;
        VarPtr owner;
        std::string ownerName;
        if (a.tag == Value::Tag::Ref) {
          fname = a.ref.key;
          owner = a.ref.owner;
          ownerName = a.ref.ownerName;
        } else if (a.tag == Value::Tag::String || a.tag == Value::Tag::Name) {
          fname = a.str;
        } else {
          fname = str(a);
        }
        VarPtr thiso = frame().thiso;
        std::shared_ptr<const Script> callee;
        VarPtr calleeThis;
        if (!owner || owner == thiso) {
          callee = frame().script;
          calleeThis = thiso;
        } else if (Space* osp = space(owner, false); osp && osp->script) {
          callee = osp->script;
          calleeThis = owner;
        }
        const Function* f = callee ? callee->findFunction(fname) : nullptr;
        if (f) {
          if (ex.frames.size() > kMaxFrames) { error("Callstack overrun", sp); push(Value::number(0)); break; }
          Frame fr;
          fr.script = callee;
          fr.thiso = calleeThis;
          fr.returnPc = next;
          fr.stackBase = ex.stack.size();
          fr.locals = std::make_shared<Var>("temp");
          fr.params = std::make_shared<Var>("params");
          fr.params->setArray(args.size());
          for (std::size_t i = 0; i < args.size(); ++i) {
            Value d = deref(args[i]);
            auto& el = fr.params->elements()[i];
            if (d.tag == Value::Tag::String) el->setString(d.str);
            else if (d.tag == Value::Tag::Object) el->setObject(d.obj);
            else el->setNumber(d.num);
          }
          fr.args = std::move(args);
          ex.frames.push_back(std::move(fr));
          next = f->index;
          break;
        }
        std::string cname = fname;
        auto cmd = commands_.end();
        if (!ownerName.empty()) cmd = commands_.find(lower(ownerName + "." + fname));
        if (cmd != commands_.end()) cname = ownerName + "." + fname;
        if (cmd == commands_.end() && owner && !owner->type().empty()) {
          cmd = commands_.find(lower(owner->type() + "." + fname));
          if (cmd != commands_.end()) cname = owner->type() + "." + fname;
        }
        if (cmd == commands_.end()) cmd = commands_.find(lower(fname));
        if (cmd != commands_.end()) {
          if (startsWithCi(cname, "adventure.") && !(thiso && startsWithCi(thiso->name(), "login"))) {
            error("Unauthorized call of " + cname, sp);
            push(Value::number(0));
            break;
          }
          if (args.size() < cmd->second.signature.size()) {
            error("Not enough parameters for " + cname + " (" + std::to_string(cmd->second.signature.size()) +
                      " needed, " + std::to_string(args.size()) + " given)",
                  sp);
            push(Value::number(0));
            break;
          }
          std::vector<Value> plain;
          for (const auto& v : args) plain.push_back(deref(v));
          Var& self = owner ? *owner : (thiso ? *thiso : *universe_);
          Value r = cmd->second.fn(*this, self, plain);
          push(std::move(r));
          break;
        }
        if (logMissingFunctions)
          error("Function " + (sp && sp->script ? sp->var->name() : std::string()) + " " + fname + " not found", sp);
        push(Value::number(0));
        break;
      }
      case 7: {  // return
        Frame& fr = frame();
        Value r = Value::number(0);
        if (ex.stack.size() > fr.stackBase) r = deref(ex.stack.back());
        ex.stack.resize(std::min(ex.stack.size(), fr.stackBase));
        const std::size_t back = fr.returnPc;
        ex.frames.pop_back();
        if (back == SIZE_MAX || ex.frames.empty()) {
          ex.result = r;
          ex.stopped = true;
          break;
        }
        push(std::move(r));
        next = back;
        break;
      }
      case 8: {  // sleep
        if (!pop(a)) break;
        const double t = num(a);
        if (t > 0) {  // anything else does not sleep
          ex.wake = clock_ + t;
          ex.suspended = true;
        }
        break;
      }
      case 9:
        if (++ex.loops > kLoopLimit) fail("Loop limit exceeded");
        break;
      case 10: frame().savedStack = ex.stack.size(); break;
      case 20: push(Value::number(in.num)); break;
      case 21: push(Value::string(in.str)); break;
      case 22: push(Value::name(in.str)); break;
      case 23: push(Value::marker()); break;
      case 24: push(Value::number(1)); break;
      case 25: push(Value::number(0)); break;
      case 26: push(Value::string("")); break;
      case 27: push(Value::number(3.14159265358979323846)); break;
      case 30:
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        push(ex.stack.back());
        break;
      case 31:
        if (ex.stack.size() < 2) { fail("Stack underflow"); break; }
        std::swap(ex.stack[ex.stack.size() - 1], ex.stack[ex.stack.size() - 2]);
        break;
      case 32: pop(a); break;
      case 33: if (pop(a)) push(Value::number(num(a))); break;
      case 34: if (pop(a)) push(Value::string(str(a))); break;
      case 35: {  // member
        if (!pop(b) || !pop(a)) break;
        Ref r;
        r.key = (b.tag == Value::Tag::Name || b.tag == Value::Tag::String) ? b.str : str(b);
        r.owner = obj(a);
        if (a.tag == Value::Tag::Name) r.ownerName = a.str;
        else if (r.owner) r.ownerName = r.owner->name();
        else if (a.tag == Value::Tag::Ref) r.ownerName = a.ref.key;
        push(Value::reference(std::move(r)));
        break;
      }
      case 36: if (pop(a)) push(Value::object(obj(a))); break;
      case 37: {  // array literal: the values above the marker, in push order
        std::vector<Value> items;
        bool marked = false;
        while (!ex.stack.empty()) {
          Value v = std::move(ex.stack.back());
          ex.stack.pop_back();
          if (v.tag == Value::Tag::Marker) { marked = true; break; }
          items.push_back(std::move(v));
        }
        if (!marked) { fail("array without a marker"); break; }
        auto arr = std::make_shared<Var>();
        arr->setArray(items.size());
        for (std::size_t i = 0; i < items.size(); ++i)
          if (auto el = arr->elements()[i]) {
            Value d = deref(items[items.size() - 1 - i]);
            if (d.tag == Value::Tag::String) el->setString(d.str);
            else if (d.tag == Value::Tag::Object) {
              if (d.obj && d.obj->kind() == Var::Kind::Array) el->assignFrom(*d.obj);
              else el->setObject(d.obj);
            } else el->setNumber(d.num);
          }
        push(Value::object(arr));
        break;
      }
      case 40:  // the name of `new T(name)` becomes a variable name
        if (!pop(a)) break;
        push(Value::name(a.tag == Value::Tag::Name ? a.str : str(a)));
        break;
      case 42: {  // new T(...): the type on top, the name under it
        if (!pop(b) || !pop(a)) break;
        const std::string name = (a.tag == Value::Tag::Name || a.tag == Value::Tag::String) ? a.str : str(a);
        push(Value::object(newObject(str(b), name)));
        break;
      }
      case 43: {  // makeoldscriptvar: a dotted path, resolved and created
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        Value& top = ex.stack.back();
        const std::string path = str(top);
        VarPtr o;
        std::size_t p = 0;
        bool first = true, bad = path.empty();
        while (!bad && p <= path.size()) {
          const std::size_t dot = path.find('.', p);
          const std::string piece = path.substr(p, dot == std::string::npos ? std::string::npos : dot - p);
          if (piece.empty()) { bad = true; break; }
          if (first) {
            const std::string l = lower(piece);
            VarPtr thiso = frame().thiso;
            if (l == "this") o = ex.with.empty() ? thiso : ex.with.back();
            else if (l == "thiso") o = thiso;
            else if (l == "player") o = player_;
            else if (l == "playero") o = playero_;
            else if (l == "client" || l == "clientr" || l == "serverr") o = playero_ ? playero_->childOrCreate(piece) : nullptr;
            else o = player_ ? player_->childOrCreate(piece) : nullptr;
            first = false;
          } else {
            o = o ? o->childOrCreate(piece) : nullptr;
          }
          if (dot == std::string::npos) break;
          p = dot + 1;
        }
        top = Value::object(bad ? nullptr : o);
        break;
      }
      case 47: {  // makeprop: the top value as a resolved variable
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        Value& top = ex.stack.back();
        Ref r;
        if (top.tag == Value::Tag::Object) r.var = top.obj;
        else if (top.tag == Value::Tag::Name || top.tag == Value::Tag::String) r.var = resolveName(ex, top.str, true);
        else if (top.tag == Value::Tag::Ref) r.var = refTarget(top.ref, true);
        top = Value::reference(std::move(r));
        break;
      }
      case 48: {  // 5.0: an anonymous object from name/value pairs
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        auto o = newObject("", "");
        long n = count(num(ex.stack.back()) + 0.0001);
        if (n > 0 && ex.stack.size() >= 3) {
          ex.stack.pop_back();  // the count
          while (ex.stack.size() >= 3) {
            Value val = std::move(ex.stack.back());
            ex.stack.pop_back();
            const std::string key = str(ex.stack.back());
            ex.stack.pop_back();
            auto c = o->childOrCreate(key);
            Value d = deref(val);
            if (d.tag == Value::Tag::String) c->setString(d.str);
            else if (d.tag == Value::Tag::Object) c->setObject(d.obj);
            else c->setNumber(d.num);
          }
        }
        if (ex.stack.empty()) push(Value::object(o));
        else ex.stack.back() = Value::object(o);
        break;
      }
      case 49: {  // 5.0: an array of the numbers under the count
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        long n = std::min(10000L, std::max(0L, count(num(ex.stack.back()))));
        auto arr = std::make_shared<Var>();
        arr->setArray(0);
        // The count goes, then the numbers under it; the array takes the
        // place of the last one read.
        std::vector<double> vals;
        if (n > 0) ex.stack.pop_back();
        while (n-- > 0 && !ex.stack.empty()) {
          vals.push_back(num(ex.stack.back()));
          if (n == 0 || ex.stack.size() == 1) break;
          ex.stack.pop_back();
        }
        auto& el = arr->elements();
        for (double d : vals) {
          auto e = std::make_shared<Var>();
          e->setNumber(d);
          el.push_back(e);
        }
        if (ex.stack.empty()) push(Value::object(arr));
        else ex.stack.back() = Value::object(arr);
        break;
      }
      case 44: if (pop(a)) push(Value::number(num(a) != 0 ? 1 : 0)); break;
      case 45:
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        if (in.num >= 0 && target < kSlots) slot(target) = ex.stack.back();  // out of range: no write
        break;
      case 46:
        push(in.num >= 0 && target < kSlots ? slot(target) : Value::number(0));
        break;
      case 50:
        if (!pop(b) || !pop(a)) break;
        assign(a, b);
        break;
      case 51: {  // bind parameters
        std::vector<std::string> names;
        bool marked = false;
        while (!ex.stack.empty()) {
          Value v = std::move(ex.stack.back());
          ex.stack.pop_back();
          if (v.tag == Value::Tag::Marker) { marked = true; break; }
          names.push_back(v.str);
        }
        if (!marked) { fail("parameter list without a marker"); break; }
        Frame& fr = frame();
        for (std::size_t i = 0; i < names.size(); ++i) {
          auto v = fr.locals->childOrCreate(names[i]);
          Value d = i < fr.args.size() ? deref(fr.args[i]) : Value::number(0);
          if (d.tag == Value::Tag::String) v->setString(d.str);
          else if (d.tag == Value::Tag::Object) {
            if (d.obj && d.obj->kind() == Var::Kind::Array) v->assignFrom(*d.obj);
            else v->setObject(d.obj);
          } else v->setNumber(d.num);
        }
        break;
      }
      case 52:
      case 53: {
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        Value& top = ex.stack.back();
        const double d = op == 52 ? 1 : -1;
        if (auto t = varOf(top, true)) t->setNumber(t->number() + d);
        else top = Value::number(num(top) + d);
        break;
      }
      case 60: case 61: case 62: case 63: case 64: case 65: case 66: case 67:
        if (!pop(b) || !pop(a)) break;
        push(Value::number(binop(op, num(a), num(b), false)));
        break;
      case 68: if (pop(a)) push(Value::number(num(a) == 0 ? 1 : 0)); break;
      case 69: if (pop(a)) push(Value::number(-num(a))); break;
      case 70:
      case 71: {
        if (!pop(b) || !pop(a)) break;
        const bool eq = compare3(*this, deref(a), deref(b)) == 0;
        push(Value::number((op == 70) == eq ? 1 : 0));
        break;
      }
      case 72: case 73: case 74: case 75:
        if (!pop(b) || !pop(a)) break;
        push(Value::number(compare(op, a, b)));
        break;
      case 76: case 77: case 78: case 101: case 102: {
        if (!pop(b) || !pop(a)) break;
        const std::int32_t x = toInt32(num(a)), y = toInt32(num(b));
        std::int32_t r = 0;
        if (op == 76) r = x | y;
        else if (op == 77) r = x & y;
        else if (op == 78) r = x ^ y;
        else if (op == 101) r = static_cast<std::int32_t>(static_cast<std::uint32_t>(x) << (y & 31));
        else r = x >> (y & 31);
        push(Value::number(r));
        break;
      }
      case 79: if (pop(a)) push(Value::number(~toInt32(num(a)))); break;
      case 85: if (pop(a)) push(Value::number(static_cast<double>(floorInt(num(a))))); break;
      case 86: if (pop(a)) push(Value::number(std::fabs(num(a)))); break;
      case 87: {
        if (!pop(b) || !pop(a)) break;
        const double lo = num(a), hi = num(b);
        push(Value::number(lo + (hi - lo) * random01()));
        break;
      }
      case 88: if (pop(a)) push(Value::number(std::sin(num(a)))); break;
      case 89: if (pop(a)) push(Value::number(std::cos(num(a)))); break;
      case 90: if (pop(a)) push(Value::number(std::atan(num(a)))); break;
      case 91: if (pop(a)) push(Value::number(std::exp(num(a)))); break;
      case 93: case 94: {
        if (!pop(b) || !pop(a)) break;
        const double x = num(a), y = num(b);
        push(Value::number(op == 93 ? std::min(x, y) : std::max(x, y)));
        break;
      }
      case 97: case 98: {
        if (!pop(a)) break;
        static const double vx[4] = {0, -1, 0, 1}, vy[4] = {-1, 0, 1, 0};
        long d = floorInt(num(a)) % 4;
        if (d < 0) d += 4;
        push(Value::number(op == 97 ? vx[d] : vy[d]));
        break;
      }
      case 103: {
        if (!pop(a)) break;
        push(Value::string(std::string(1, static_cast<char>(toInt32(num(a)) & 0xFF))));
        break;
      }
      case 110: {
        if (!pop(a)) break;
        std::string t = str(a);
        const auto first = t.find_first_not_of(" \t\r\n");
        const auto last = t.find_last_not_of(" \t\r\n");
        push(Value::string(first == std::string::npos ? "" : t.substr(first, last - first + 1)));
        break;
      }
      case 111: if (pop(a)) push(Value::number(static_cast<double>(str(a).size()))); break;
      case 112: {
        if (!pop(b) || !pop(a)) break;
        const auto p = str(a).find(str(b));
        push(Value::number(p == std::string::npos ? -1 : static_cast<double>(p)));
        break;
      }
      case 113:
        if (!pop(b) || !pop(a)) break;
        push(Value::string(str(a) + str(b)));
        break;
      case 114: {
        if (!pop(b) || !pop(a)) break;
        const std::string t = str(a);
        const long i = floorInt(num(b));
        push(Value::string(i >= 0 && static_cast<std::size_t>(i) < t.size() ? t.substr(static_cast<std::size_t>(i), 1) : ""));
        break;
      }
      case 116: case 117: {
        if (!pop(b) || !pop(a)) break;
        const std::string t = str(a), x = str(b);
        bool r = x.size() <= t.size() &&
                 (op == 116 ? t.compare(0, x.size(), x) == 0 : t.compare(t.size() - x.size(), x.size(), x) == 0);
        push(Value::number(r ? 1 : 0));
        break;
      }
      case 115: {  // substring(text, start, length); a negative length runs to the end
        if (!pop(c) || !pop(b) || !pop(a)) break;
        const std::string t = str(a);
        long st = floorInt(num(b)), len = floorInt(num(c));
        if (st < 0) st = 0;
        if (static_cast<std::size_t>(st) >= t.size()) { push(Value::string("")); break; }
        push(Value::string(len < 0 ? t.substr(static_cast<std::size_t>(st))
                                   : t.substr(static_cast<std::size_t>(st), static_cast<std::size_t>(len))));
        break;
      }
      case 119:
        if (!pop(a)) break;
        push(Value::string(translate ? translate(str(a)) : str(a)));
        break;
      case 121: {  // 5.0 and 6.00: add, or append when either side is a string
        if (!pop(b) || !pop(a)) break;
        const Value x = deref(a), y = deref(b);
        if (x.tag == Value::Tag::String || y.tag == Value::Tag::String) push(Value::string(str(x) + str(y)));
        else push(Value::number(toNumber(x) + toNumber(y)));
        break;
      }
      case 163: {  // foreach: variable, array, index stay on the stack
        if (ex.stack.size() < 3) { fail("Stack underflow"); break; }
        const Value& idx = ex.stack[ex.stack.size() - 1];
        auto arr = obj(ex.stack[ex.stack.size() - 2]);
        const long i = floorInt(num(idx));
        if (arr && arr->kind() == Var::Kind::Array && i >= 0 && static_cast<std::size_t>(i) < arr->elements().size()) {
          Ref r;
          r.var = arr->elements()[static_cast<std::size_t>(i)];
          assign(ex.stack[ex.stack.size() - 3], Value::reference(std::move(r)));
        } else {
          next = target;
        }
        break;
      }
      case 130: {
        if (!pop(a)) break;
        auto o = obj(a);
        push(Value::number(o && o->kind() == Var::Kind::Array ? static_cast<double>(o->elements().size()) : 0));
        break;
      }
      case 131: {
        if (!pop(b) || !pop(a)) break;
        Ref r;
        r.owner = obj(a);
        r.index = floorInt(num(b));
        if (r.index < 0) r.index = LONG_MAX;  // reads as 0, stores nowhere
        push(Value::reference(std::move(r)));
        break;
      }
      case 132: {
        if (!pop(c) || !pop(b) || !pop(a)) break;
        Ref r;
        r.owner = obj(a);
        r.index = floorInt(num(b));
        if (r.index >= 0) assign(Value::reference(std::move(r)), c);
        break;
      }
      case 150: {
        if (!pop(a)) break;
        auto o = obj(a);
        if (!o) next = target;
        else ex.with.push_back(o);
        break;
      }
      case 151:
        if (!ex.with.empty()) ex.with.pop_back();
        break;
      case 180: push(Value::object(ex.with.empty() ? frame().thiso : ex.with.back())); break;
      case 181: push(Value::object(frame().thiso)); break;
      case 182: push(Value::object(player_)); break;
      case 183: push(Value::object(playero_)); break;
      case 184: push(Value::object(level_)); break;
      case 189: push(Value::object(frame().locals)); break;
      case 190: push(Value::object(frame().params)); break;

      // Load-time fusions.
      case 200: case 201: case 202: case 203: case 204: case 205: case 206: case 207:
        if (!pop(a)) break;
        push(Value::number(binop(op - 200 + 60, num(a), in.num, true)));
        next = ex.pc + 2;
        break;
      case 208: case 209: case 210: case 211: case 212: case 213: case 214: case 215: {
        if (!pop(b) || !pop(a) || !pop(c)) break;
        assign(c, Value::number(binop(op - 208 + 60, num(a), num(b), true)));
        next = ex.pc + 2;
        break;
      }
      case 216: case 217: case 218: case 219: case 220: case 221: case 222: case 223: {
        if (!pop(a) || !pop(c)) break;
        assign(c, Value::number(binop(op - 216 + 60, num(a), in.num, true)));
        next = ex.pc + 3;
        break;
      }
      case 224: case 225: case 226: case 227:
        if (!pop(a)) break;
        push(Value::number(compare(op - 224 + 72, a, Value::number(in.num))));
        next = ex.pc + 2;
        break;
      case 228: case 229: case 230: case 233: {
        const Value v = in.num >= 0 && target < kSlots ? slot(target) : Value::number(0);
        if (op == 233) { push(v); push(v); }
        else if (op == 228) push(Value::number(num(v)));
        else if (op == 229) push(Value::string(str(v)));
        else push(Value::object(objCreate(v)));
        next = ex.pc + 2;
        break;
      }
      case 231: case 232: {
        if (in.num >= 0 && target < kSlots) {
          Value& v = slot(target);
          const double d = op == 231 ? 1 : -1;
          if (auto t = varOf(v, true)) t->setNumber(t->number() + d);
          else v = Value::number(num(v) + d);
        }
        next = ex.pc + 3;
        break;
      }

      // 6.00's extra folds run as the instructions they replaced, which stay
      // in the list. 242 stores the register without the makeprop.
      case 234: case 235: case 236: case 237: case 238: case 239: case 240:
        next = ex.pc;
        runUnfused = true;
        break;
      case 242: {
        if (ex.stack.empty()) { fail("Stack underflow"); break; }
        const double n = ex.pc + 1 < s.code.size() ? s.code[ex.pc + 1].num : -1;
        const auto i = static_cast<std::size_t>(std::max(0.0, std::trunc(n)));
        if (n >= 0 && i < kSlots) slot(i) = ex.stack.back();
        next = ex.pc + 2;
        break;
      }
      default:
        unimplemented(op);
        break;
    }
    if (ex.stopped) break;
    ex.pc = next;
  }
  return ex.result;
}

}  // namespace gs2
