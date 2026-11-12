#pragma once

// The GS2 script machine the 4.x, 5.x and 6.x engines share
// (TScriptExecutionSpace on a TGraalVar). Written from Graal_analysis
// `client-internals/gs2-vm-from-engines.md`; see README.md for which
// behaviour comes from that read and which is still refused.

#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace gs2 {

// Which engine's opcode set a script is run with.
enum class Profile { Engine42, Engine50, Engine600 };

const char* profileName(Profile p);
bool opcodeInProfile(int op, Profile p);
// Whether this machine runs the opcode (the rest are refused with an error).
bool opcodeImplemented(int op);

// ---------------------------------------------------------------- bytecode

struct Instruction {
  enum class Kind { None, Number, String };
  int op = 0;
  int loadedOp = 0;  // the opcode as it was in the file, before fusion
  Kind kind = Kind::None;
  std::string str;
  double num = 0;
};

struct Function {
  std::string name;  // without the "public." prefix
  std::uint32_t index = 0;
  bool isPublic = false;
};

struct Script {
  std::uint32_t gs1EventMask = 0;
  std::vector<Function> functions;
  std::vector<std::string> strings;
  std::vector<Instruction> code;
  int fusedPairs = 0;  // how many load-time fusions were made

  const Function* findFunction(const std::string& name) const;  // case-insensitive
};

struct LoadResult {
  std::shared_ptr<Script> script;  // null when the bytes are not a script
  std::string error;
  bool ok() const { return script != nullptr; }
};

// Read the four big-endian segments and the opcode stream, then apply the
// engine's load-time pair fusions.
// The 6.00 engines fold more pairs (234 to 242) than 4.2 and 5.0.
LoadResult load(const std::uint8_t* data, std::size_t size, Profile profile = Profile::Engine42);
LoadResult load(const std::string& bytes, Profile profile = Profile::Engine42);

std::string opcodeName(int op);
std::string disassemble(const Script& s);

// ----------------------------------------------------------------- objects

class Var;
using VarPtr = std::shared_ptr<Var>;

// A slot that names a variable: an owner and a key, or an array element.
struct Ref {
  VarPtr var;  // a variable already resolved (makeprop, makeoldscriptvar); owner and key unused
  VarPtr owner;
  std::string ownerName;  // what the script called the owner, kept when it did not resolve
  std::string key;
  long index = -1;  // >= 0 for an array element of owner
};

// A value on the machine's stack. The tags are the engines' numbers.
struct Value {
  enum class Tag { Marker = 0, Number = 1, String = 2, Object = 3, Name = 4, Ref = 5 };
  Tag tag = Tag::Number;
  double num = 0;
  std::string str;  // String text, or the Name
  VarPtr obj;       // Object
  Ref ref;          // Ref

  static Value marker() { Value v; v.tag = Tag::Marker; return v; }
  static Value number(double d) { Value v; v.num = d; return v; }
  static Value string(std::string s) { Value v; v.tag = Tag::String; v.str = std::move(s); return v; }
  static Value object(VarPtr o) { Value v; v.tag = Tag::Object; v.obj = std::move(o); return v; }
  static Value name(std::string s) { Value v; v.tag = Tag::Name; v.str = std::move(s); return v; }
  static Value reference(Ref r) { Value v; v.tag = Tag::Ref; v.ref = std::move(r); return v; }
};

// A TGraalVar: a value of its own (number, string, object link or array)
// plus named child variables.
class Var : public std::enable_shared_from_this<Var> {
 public:
  enum class Kind { Number, String, Object, Array };

  explicit Var(std::string name = "", std::string type = "") : name_(std::move(name)), type_(std::move(type)) {}
  virtual ~Var() = default;

  const std::string& name() const { return name_; }
  void setName(const std::string& n) { name_ = n; }
  // The class an object was created as (`new T(...)`), empty for plain variables.
  const std::string& type() const { return type_; }

  // Whether an assignment to `key` inside `with` (or on `thiso`) lands on this
  // object rather than on a global. The engines' typed objects answer from
  // their property set; a plain object made by `new` takes every name until
  // its class gives the real list.
  virtual bool acceptsProperty(const std::string& key) const;
  void setAcceptsAllProperties(bool b) { acceptsAll_ = b; }

  Kind kind() const { return kind_; }
  double number() const;
  std::string string() const;
  VarPtr object() const { return kind_ == Kind::Object ? link_.lock() : nullptr; }
  std::vector<VarPtr>& elements() { return elems_; }

  void setNumber(double d);
  void setString(const std::string& s);
  void setObject(const VarPtr& o);
  void setArray(std::size_t n);
  void assignFrom(const Var& other);

  VarPtr child(const std::string& key) const;  // case-insensitive, null if absent
  VarPtr childOrCreate(const std::string& key);
  const std::map<std::string, VarPtr>& children() const { return children_; }

 private:
  std::string name_;
  Kind kind_ = Kind::Number;
  double num_ = 0;
  std::string str_;
  std::weak_ptr<Var> link_;
  std::vector<VarPtr> elems_;
  std::map<std::string, VarPtr> children_;  // keys lower-cased
  std::string type_;
  bool acceptsAll_ = false;
};

// ----------------------------------------------------------------- machine

class Machine;
using Command = std::function<Value(Machine&, Var& self, std::vector<Value>& args)>;

class Machine {
 public:
  explicit Machine(Profile profile = Profile::Engine42);
  ~Machine();
  Machine(const Machine&) = delete;
  Machine& operator=(const Machine&) = delete;

  Profile profile() const { return profile_; }

  // The universe: globals live here, and new named variables are its children.
  VarPtr universe() const { return universe_; }
  VarPtr newVar(const std::string& name);  // a child of the universe

  // Attach bytecode to a variable. A non-empty script queues `created`.
  // An empty or unreadable script clears the variable's script.
  bool setScript(const VarPtr& var, const std::string& bytes, std::string* error = nullptr);
  bool setScript(const VarPtr& var, std::shared_ptr<const Script> script);
  bool hasScript(const VarPtr& var) const;

  // Classes: a script stored by name (`addClassScript`, packet 133; a gani's
  // is `gani.` plus its name, packet 134) that objects join. A joined
  // class's functions and events are found after the object's own.
  bool addClassScript(const std::string& name, const std::string& bytes, std::string* error = nullptr);
  std::shared_ptr<const Script> classScript(const std::string& name) const;
  bool joinClass(const VarPtr& var, const std::string& name);
  void leaveClass(const VarPtr& var, const std::string& name);

  // Events are run by runScripts, in queue order.
  bool queueEvent(const VarPtr& var, const std::string& name, std::vector<Value> args = {});
  void invokeInitialized(const VarPtr& var);
  void scheduleEvent(const VarPtr& var, double delay, const std::string& name, std::vector<Value> args = {});
  void cancelEvents(const VarPtr& var, const std::string& name);

  // catchevent: when `event` is queued on the variable named `objectName`
  // (`universe`, or a child of it), `function` is queued on `catcher`.
  void catchEvent(const std::string& objectName, const std::string& event, const VarPtr& catcher,
                  const std::string& function);

  // Run a function now, outside the queue. Returns its result.
  Value callFunction(const VarPtr& var, const std::string& name, std::vector<Value> args = {});

  // Built-in commands. `signature`'s length is the minimum argument count.
  void addCommand(const std::string& name, const std::string& signature, Command fn);

  // The script clock. 2D steps by 0.05 a pass once the clock is non-zero;
  // 3D sets it from elapsed seconds.
  double clock() const { return clock_; }
  void setClock(double seconds) { clock_ = seconds; }
  void runScripts();  // one 2D pass: step the clock, wake sleepers, run queued events
  void runDue();      // wake and run without stepping the clock

  // The `with`-independent objects the reserved names resolve to.
  void setPlayer(const VarPtr& p) { player_ = p; }
  void setPlayerObject(const VarPtr& p) { playero_ = p; }
  void setLevel(const VarPtr& l) { level_ = l; }

  // Errors, as the engines' recorder keeps them: at most 20 distinct texts.
  const std::vector<std::string>& errors() const { return errors_; }
  void clearErrors() { errors_.clear(); }
  bool logMissingFunctions = true;

  // `new T(name)`: makes the object. The default makes a plain Var of type T
  // that accepts every property. The machine keeps every object it made.
  using Factory = std::function<VarPtr(Machine&, const std::string& type, const std::string& name)>;
  void setObjectFactory(Factory f) { factory_ = std::move(f); }
  const std::vector<VarPtr>& objects() const { return objects_; }

  // `_(text)` (opcode 119). The default returns the text unchanged.
  std::function<std::string(const std::string&)> translate;

  // Conversions shared with commands.
  double toNumber(const Value& v) const;
  std::string toString(const Value& v) const;
  VarPtr toObject(const Value& v) const;
  static std::string numberText(double d);

  void seedRandom(std::uint32_t seed) { rng_ = seed; }
  double random01();

  // How many instructions have run in total (for tests and the profiler).
  std::uint64_t instructionsRun() const { return executed_; }

  struct Space;
  struct Frame;
  struct Exec;

 private:
  friend struct Exec;
  Space* space(const VarPtr& var, bool create);
  void runAction(Space& sp, const std::string& name, std::vector<Value> args);
  Value execute(Exec& ex);
  void error(const std::string& text, const Space* sp);
  VarPtr resolveName(Exec& ex, const std::string& name, bool create);
  const Function* findFunction(const Space* sp, const std::string& name, std::shared_ptr<const Script>* piece) const;
  bool hasCode(const Space* sp) const;

  Profile profile_;
  VarPtr universe_;
  VarPtr player_, playero_, level_;
  std::map<const Var*, std::unique_ptr<Space>> spaces_;
  std::vector<Space*> order_;  // spaces in creation order
  struct CommandEntry { std::string signature; Command fn; };
  std::map<std::string, CommandEntry> commands_;  // lower-cased names
  std::vector<std::string> errors_;
  Factory factory_;
  struct Catch { std::string object, event; std::weak_ptr<Var> catcher; std::string function; };
  std::vector<Catch> catches_;
  std::map<std::string, std::shared_ptr<const Script>> classes_;  // lower-cased names
  std::vector<VarPtr> objects_;
  double clock_ = 0;
  std::uint64_t executed_ = 0;
  std::uint32_t rng_ = 1;
};

}  // namespace gs2
