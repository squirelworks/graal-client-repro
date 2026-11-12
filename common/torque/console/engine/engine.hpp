#pragma once

// TorqueScript console engine for the Linux 3.04 rebuild (#172, #109 stage 1).
// Executes DSO v33 code blocks with Graal's opcode table, and keeps the
// console state the shipped scripts rely on: variables, functions in
// namespaces, packages, SimObjects with names and dynamic fields, SimSet and
// SimGroup, ActionMap data, FileObject and scheduled events. README.md says
// which behaviour is observed, which is rebuild policy and which is open.

#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

#include "../dso.hpp"

namespace Torque {

class Engine;
struct SimObject;

// A console variable keeps the type it was last stored with. export()
// writes string-typed values quoted and numeric ones bare (observed in the
// 3.04 prefs.cs the original wrote).
struct Value {
  enum class Kind { string, integer, floating };
  Kind kind = Kind::string;
  std::string text;
  std::uint32_t integer = 0;
  double floating = 0;

  static Value of_string(std::string s);
  static Value of_int(std::uint32_t v);
  static Value of_float(double v);
  std::string str() const;
  std::uint32_t u32() const;
  double f64() const;
};

std::string format_int(std::uint32_t v);   // signed decimal
std::string format_float(double v);        // %g
std::uint32_t parse_int(const std::string& s);
double parse_float(const std::string& s);
std::string lower(const std::string& s);
bool match_pattern(const std::string& pattern, const std::string& text);  // * and ?, no case
std::string expand_escape(const std::string& s);

using Args = std::vector<std::string>;
// Native callback. argv[0] is the command name; on a method argv[1] is the
// object id and self is that object. The result is the call's string value.
using NativeFn = std::function<std::string(Engine&, SimObject* self, Args& argv)>;

struct CodeBlock {
  std::string name;        // script path without ".dso", used in messages
  DsoBlock dso;
  std::map<std::uint32_t, std::string> idents;  // patched operand words
  std::map<std::uint32_t, bool> unnamed;         // unused-argument sentinels
  bool ident(std::uint32_t ip, std::string& out) const;
  std::string string_at(bool function, std::uint32_t offset) const;
  double float_at(bool function, std::uint32_t index) const;
  std::string file_line(std::uint32_t ip) const;
};

struct Function {
  std::string name, space, package;
  std::shared_ptr<CodeBlock> code;   // script body, or null for a native
  std::uint32_t ip = 0;
  std::vector<std::string> args;     // "%name"; empty for an unused slot
  NativeFn native;
  std::size_t min = 0, max = 0;      // counts include argv[0] (and the object)
  std::string usage;
};

struct Namespace {
  std::string name;
  Namespace* parent = nullptr;
  // package (lower case, "" = no package) -> function (lower case)
  std::map<std::string, std::map<std::string, Function>> layers;
};

struct ClassInfo {
  std::string name, parent;
  bool creatable = true;
  bool is_set = false, is_group = false;
};

struct ActionBinding {
  std::string device, action, command, make, brk;
  bool is_cmd = false;
};

struct SimObject {
  std::uint32_t id = 0;
  std::string name, class_name;
  std::string source;  // script that created it; its fields' "./" paths are relative to it
  const ClassInfo* info = nullptr;
  Namespace* space = nullptr;
  std::map<std::string, std::pair<std::string, std::string>> fields;  // lower -> (name, value)
  // SimSet / SimGroup membership, in insertion order.
  std::vector<std::uint32_t> members;
  std::uint32_t group = 0;            // owning SimGroup (0 = none)
  std::vector<ActionBinding> binds;   // ActionMap
  std::vector<std::pair<std::string, std::string>> rows;  // pop-up menu entries (text, id)
  bool awake = false;
  std::vector<std::string> lines;     // FileObject read buffer
  std::size_t line_pos = 0;
  std::string write_path;
  bool writing = false;
  std::string field(const std::string& name) const;
  void set_field(const std::string& name, const std::string& value);
};

// Where scripts and prefs live. Reads look in prefs_dir first, then root;
// writes go to prefs_dir. Paths are mod-relative with '/' separators.
struct FileSystem {
  std::string root, prefs_dir;
  bool read(const std::string& path, std::string& out) const;
  bool exists(const std::string& path) const;
  bool in_prefs(const std::string& path) const;
  bool write(const std::string& path, const std::string& data, bool append) const;
  std::vector<std::string> list() const;  // every file, sorted, root and prefs
};

struct EngineLimits {
  std::size_t call_depth = 512;
  std::size_t steps = 50'000'000;   // per top-level exec or call
  std::size_t stack = 4096;
};

class Engine {
 public:
  Engine();
  Engine(const Engine&) = delete;
  Engine& operator=(const Engine&) = delete;

  FileSystem files;
  FloatOrder float_order = FloatOrder::little;
  EngineLimits limits;
  // Console output: one call per echo/warn/error, before line splitting.
  std::function<void(const std::string&)> print;
  // Optional TorqueScript compiler for plain .cs files and eval(). Not part
  // of this engine; the boot runner leaves it empty until one is merged.
  std::function<bool(const std::string& source, const std::string& name,
                     DsoBlock& out, std::string& error)> compiler;
  // Diagnostics that are not console output (engine policy failures).
  std::vector<std::string> trace;

  // Registration.
  void add_class(ClassInfo info);
  void add_function(const std::string& space, const std::string& name, std::size_t min,
                    std::size_t max, const std::string& usage, NativeFn fn);
  const ClassInfo* find_class(const std::string& name) const;

  // Scripts.
  bool exec_file(const std::string& path, bool no_calls = false);
  bool run_block(std::shared_ptr<CodeBlock> block, std::string* result = nullptr);
  std::shared_ptr<CodeBlock> link(const std::string& name, DsoBlock dso, std::string& error);
  std::string call_function(const std::string& name, Args args);   // args exclude name
  std::string call_method(SimObject* obj, const std::string& name, Args args);
  bool evaluate(const std::string& source, std::string* result = nullptr);

  // Variables.
  void set_global(const std::string& name, Value v);
  Value global(const std::string& name) const;
  bool has_global(const std::string& name) const;
  // An engine-owned variable: stores are kept as strings, so export quotes it.
  void bind_variable(const std::string& name, const std::string& value);
  bool is_bound(const std::string& name) const { return bound.count(lower(name)) != 0; }
  std::vector<std::pair<std::string, Value>> globals_matching(const std::string& pattern) const;

  // Objects.
  SimObject* find_object(const std::string& ref) const;
  SimObject* object(std::uint32_t id) const;
  SimObject* create_object(const std::string& class_name, const std::string& name,
                           bool add_to_root = true);
  void delete_object(std::uint32_t id);
  void add_to_set(SimObject* set, SimObject* obj);
  void remove_from_set(SimObject* set, SimObject* obj);
  void set_name(SimObject* obj, const std::string& name);
  SimObject* root_group() const { return object(root_id); }

  // Packages.
  bool activate_package(const std::string& name);
  bool deactivate_package(const std::string& name);
  bool is_package(const std::string& name) const;

  // Events.
  // object != 0 cancels the event when that object is deleted; method calls
  // argv[0] on the object, otherwise argv[0] is a function.
  std::uint32_t schedule(std::uint32_t delay, std::uint32_t object, Args argv, bool method);
  bool cancel(std::uint32_t event);
  bool pending(std::uint32_t event) const;
  void advance(std::uint32_t ms);
  std::uint32_t sim_time() const { return time_ms; }

  // Paths, relative to the code block running now.
  std::string expand_path(const std::string& path) const;
  // The same rules relative to a given script (e.g. SimObject::source).
  static std::string expand_path_from(const std::string& script, const std::string& path);
  const CodeBlock* current_block() const;

  bool quit_requested = false;
  // Called after GuiCanvas::setContent stores the new content (for a renderer).
  std::function<void(SimObject* canvas, SimObject* content)> on_set_content;
  std::vector<std::uint32_t> action_maps;   // pushed ActionMaps, bottom first
  std::vector<std::string> file_search;     // findFirstFile results
  std::size_t file_search_pos = 0;
  std::uint32_t random_state = 1;
  int log_mode = 0;
  std::string mod_paths;

 private:
  struct Frame;
  struct Event { std::uint32_t id, when, object; Args argv; bool method; };
  struct Resolved { Namespace* space = nullptr; std::string package; Function* fn = nullptr; };

  Namespace* space(const std::string& name, bool create);
  Resolved resolve(Namespace* ns, const std::string& fn, std::size_t below = 0,
                   bool skip_base = false) const;
  Resolved resolve_parent(const Function& current) const;
  std::string invoke(const Resolved& r, Args& argv, SimObject* self, const std::string& where);
  std::string execute(std::shared_ptr<CodeBlock> block, std::uint32_t ip, bool in_function,
                      const Function* fn, Args* argv, bool no_calls);
  void link_namespace(SimObject* obj);
  std::uint32_t register_object(std::unique_ptr<SimObject> obj);
  void warn(const std::string& line);

  std::map<std::string, ClassInfo> classes;           // lower name
  std::map<std::string, std::unique_ptr<Namespace>> spaces;  // lower name
  std::vector<std::string> active_packages;           // lower, activation order
  std::map<std::string, std::string> package_names;   // lower -> declared
  std::map<std::string, std::pair<std::string, Value>> globals;  // lower -> (name, value)
  std::set<std::string> bound;                        // lower names
  std::map<std::uint32_t, std::unique_ptr<SimObject>> objects;
  std::map<std::string, std::uint32_t> names;         // lower -> id
  std::uint32_t next_id = 1027;
  std::uint32_t root_id = 0;
  std::vector<Frame*> frames;
  std::vector<Event> events;
  std::uint32_t next_event = 1, time_ms = 0;
  friend struct Interpreter;
};

void register_builtins(Engine& engine);
void register_classes_304(Engine& engine);
void register_engine_prefs_304(Engine& engine);
void register_text_list_304(Engine& engine);   // GuiTextListCtrl rows (textlist304.cpp)

} // namespace Torque
