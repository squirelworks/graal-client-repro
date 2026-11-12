#include "internal.hpp"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "../instructions.hpp"

namespace Torque {

// ---------------------------------------------------------------- values

std::string lower(const std::string& s) {
  std::string out = s;
  for (auto& c : out) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return out;
}

std::string format_int(std::uint32_t v) {
  return std::to_string(static_cast<std::int32_t>(v));
}

std::string format_float(double v) {
  char buffer[64];
  std::snprintf(buffer, sizeof buffer, "%g", v);
  return buffer;
}

std::uint32_t parse_int(const std::string& s) {
  // atoi-style: optional space and sign, decimal digits, stop at the first
  // other character. Out-of-range values clamp to 32 bits (policy).
  const char* p = s.c_str();
  errno = 0;
  long long v = std::strtoll(p, nullptr, 10);
  if (v > INT32_MAX) v = INT32_MAX;
  if (v < INT32_MIN) v = INT32_MIN;
  return static_cast<std::uint32_t>(static_cast<std::int32_t>(v));
}

double parse_float(const std::string& s) {
  return std::strtod(s.c_str(), nullptr);
}

static std::uint32_t float_to_u32(double f) {
  if (std::isnan(f)) return 0;
  if (f >= 4294967295.0) return 0xffffffffu;
  if (f <= -2147483648.0) return 0x80000000u;
  if (f < 0) return static_cast<std::uint32_t>(static_cast<std::int32_t>(f));
  return static_cast<std::uint32_t>(f);
}

Value Value::of_string(std::string s) { Value v; v.kind = Kind::string; v.text = std::move(s); return v; }
Value Value::of_int(std::uint32_t i) { Value v; v.kind = Kind::integer; v.integer = i; return v; }
Value Value::of_float(double f) { Value v; v.kind = Kind::floating; v.floating = f; return v; }

std::string Value::str() const {
  switch (kind) {
    case Kind::integer: return format_int(integer);
    case Kind::floating: return format_float(floating);
    default: return text;
  }
}
std::uint32_t Value::u32() const {
  switch (kind) {
    case Kind::integer: return integer;
    case Kind::floating: return float_to_u32(floating);
    default: return parse_int(text);
  }
}
double Value::f64() const {
  switch (kind) {
    case Kind::integer: return static_cast<double>(static_cast<std::int32_t>(integer));
    case Kind::floating: return floating;
    default: return parse_float(text);
  }
}

bool match_pattern(const std::string& pattern, const std::string& text) {
  // Iterative glob, case-insensitive; '*' also matches '/'.
  std::size_t p = 0, t = 0, star = std::string::npos, mark = 0;
  auto eq = [](char a, char b) {
    return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b));
  };
  while (t < text.size()) {
    if (p < pattern.size() && (pattern[p] == '?' || eq(pattern[p], text[t]))) { ++p; ++t; }
    else if (p < pattern.size() && pattern[p] == '*') { star = p++; mark = t; }
    else if (star != std::string::npos) { p = star + 1; t = ++mark; }
    else return false;
  }
  while (p < pattern.size() && pattern[p] == '*') ++p;
  return p == pattern.size();
}

std::string expand_escape(const std::string& s) {
  std::string out;
  for (unsigned char c : s) {
    switch (c) {
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      case '\\': out += "\\\\"; break;
      case '"': out += "\\\""; break;
      case '\'': out += "\\'"; break;
      default:
        if (c < 32) {
          char b[8];
          std::snprintf(b, sizeof b, "\\x%02x", c);
          out += b;
        } else {
          out += static_cast<char>(c);
        }
    }
  }
  return out;
}

// ---------------------------------------------------------------- code blocks

bool CodeBlock::ident(std::uint32_t ip, std::string& out) const {
  auto it = idents.find(ip);
  if (it == idents.end()) return false;
  out = it->second;
  return true;
}

std::string CodeBlock::string_at(bool function, std::uint32_t offset) const {
  const std::string& table = function ? dso.function_strings : dso.global_strings;
  if (offset >= table.size()) throw ScriptError{"string offset outside table"};
  const auto end = table.find('\0', offset);
  return table.substr(offset, end == std::string::npos ? std::string::npos : end - offset);
}

double CodeBlock::float_at(bool function, std::uint32_t index) const {
  const auto& table = function ? dso.function_floats : dso.global_floats;
  if (index >= table.size()) throw ScriptError{"float index outside table"};
  return table[index];
}

std::string CodeBlock::file_line(std::uint32_t ip) const {
  // The line of the last line/ip pair at or before ip.
  std::uint32_t line = 0, best_ip = 0;
  bool found = false;
  for (const auto& pair : dso.lines) {
    if (pair.ip <= ip && (!found || pair.ip >= best_ip)) {
      best_ip = pair.ip;
      line = pair.line;
      found = true;
    }
  }
  return name + " (" + std::to_string(found ? line : 0) + ")";
}

// ---------------------------------------------------------------- objects

std::string SimObject::field(const std::string& name) const {
  auto it = fields.find(lower(name));
  return it == fields.end() ? std::string() : it->second.second;
}

void SimObject::set_field(const std::string& name, const std::string& value) {
  auto key = lower(name);
  auto it = fields.find(key);
  if (it == fields.end()) fields.emplace(key, std::make_pair(name, value));
  else it->second.second = value;
}

// ---------------------------------------------------------------- files

namespace fs = std::filesystem;

static bool find_path(const std::string& base, const std::string& rel, fs::path& out) {
  if (base.empty()) return false;
  fs::path exact = fs::path(base) / rel;
  std::error_code ec;
  if (fs::is_regular_file(exact, ec)) { out = exact; return true; }
  // Case-insensitive fallback, one component at a time (rebuild policy).
  fs::path cur = base;
  std::stringstream ss(rel);
  std::string part;
  std::vector<std::string> parts;
  while (std::getline(ss, part, '/')) if (!part.empty() && part != ".") parts.push_back(part);
  for (std::size_t i = 0; i < parts.size(); ++i) {
    if (!fs::is_directory(cur, ec)) return false;
    bool hit = false;
    for (const auto& entry : fs::directory_iterator(cur, ec)) {
      if (lower(entry.path().filename().string()) == lower(parts[i])) {
        cur = entry.path();
        hit = true;
        break;
      }
    }
    if (!hit) return false;
  }
  if (!fs::is_regular_file(cur, ec)) return false;
  out = cur;
  return true;
}

bool FileSystem::read(const std::string& path, std::string& out) const {
  fs::path found;
  if (!find_path(prefs_dir, path, found) && !find_path(root, path, found)) return false;
  std::ifstream in(found, std::ios::binary);
  if (!in) return false;
  std::ostringstream buffer;
  buffer << in.rdbuf();
  out = buffer.str();
  return true;
}

bool FileSystem::exists(const std::string& path) const {
  fs::path found;
  return find_path(prefs_dir, path, found) || find_path(root, path, found);
}

bool FileSystem::in_prefs(const std::string& path) const {
  fs::path found;
  return find_path(prefs_dir, path, found);
}

bool FileSystem::write(const std::string& path, const std::string& data, bool append) const {
  const std::string& base = prefs_dir.empty() ? root : prefs_dir;
  if (base.empty()) return false;
  fs::path target = fs::path(base) / path;
  std::error_code ec;
  fs::create_directories(target.parent_path(), ec);
  std::ofstream out(target, std::ios::binary | (append ? std::ios::app : std::ios::trunc));
  if (!out) return false;
  out << data;
  return static_cast<bool>(out);
}

std::vector<std::string> FileSystem::list() const {
  std::vector<std::string> result;
  for (const auto* base : {&root, &prefs_dir}) {
    if (base->empty()) continue;
    std::error_code ec;
    if (!fs::is_directory(*base, ec)) continue;
    for (auto it = fs::recursive_directory_iterator(*base, ec);
         it != fs::recursive_directory_iterator(); it.increment(ec)) {
      if (ec) break;
      if (it->is_regular_file(ec))
        result.push_back(fs::relative(it->path(), *base, ec).generic_string());
    }
  }
  std::sort(result.begin(), result.end());
  result.erase(std::unique(result.begin(), result.end()), result.end());
  return result;
}

// ---------------------------------------------------------------- engine

Engine::Engine() {
  print = [](const std::string&) {};
  add_class({"SimObject", "", true, false, false});
  add_class({"SimSet", "SimObject", true, true, false});
  add_class({"SimGroup", "SimSet", true, true, true});
  auto root = std::make_unique<SimObject>();
  root->id = 0;
  root->class_name = "SimGroup";
  root->info = find_class("SimGroup");
  root->name = "RootGroup";
  objects[0] = std::move(root);
  names["rootgroup"] = 0;
  link_namespace(objects[0].get());
  space("", true);
  register_builtins(*this);
}

void Engine::warn(const std::string& line) { print(line); }

void Engine::add_class(ClassInfo info) {
  classes[lower(info.name)] = std::move(info);
}

const ClassInfo* Engine::find_class(const std::string& name) const {
  auto it = classes.find(lower(name));
  return it == classes.end() ? nullptr : &it->second;
}

Namespace* Engine::space(const std::string& name, bool create) {
  auto key = lower(name);
  auto it = spaces.find(key);
  if (it != spaces.end()) return it->second.get();
  if (!create) return nullptr;
  auto ns = std::make_unique<Namespace>();
  ns->name = name;
  auto* raw = ns.get();
  spaces[key] = std::move(ns);
  // A class namespace links to its parent class namespace when created.
  if (auto* info = find_class(name); info && !info->parent.empty())
    raw->parent = space(info->parent, true);
  return raw;
}

void Engine::add_function(const std::string& ns, const std::string& name, std::size_t min,
                          std::size_t max, const std::string& usage, NativeFn fn) {
  Function f;
  f.name = name;
  f.space = ns;
  f.native = std::move(fn);
  f.min = min;
  f.max = max;
  f.usage = usage;
  space(ns, true)->layers[""][lower(name)] = std::move(f);
}

Engine::Resolved Engine::resolve(Namespace* ns, const std::string& fn, std::size_t below,
                                 bool skip_base) const {
  // below: only packages activated before index `below` in the first
  // namespace (used by Parent::); 0 means all active packages.
  const auto key = lower(fn);
  bool first = true;
  for (Namespace* n = ns; n; n = n->parent) {
    std::size_t top = (first && below) ? below : active_packages.size();
    if (!(first && skip_base && below == 0)) {
      for (std::size_t i = top; i-- > 0;) {
        auto layer = n->layers.find(active_packages[i]);
        if (layer == n->layers.end()) continue;
        auto f = layer->second.find(key);
        if (f != layer->second.end()) return {n, active_packages[i], &f->second};
      }
    }
    if (!(first && skip_base)) {
      auto base = n->layers.find("");
      if (base != n->layers.end()) {
        auto f = base->second.find(key);
        if (f != base->second.end()) return {n, "", &f->second};
      }
    }
    first = false;
  }
  return {};
}

Engine::Resolved Engine::resolve_parent(const Function& current) const {
  auto it = spaces.find(lower(current.space));
  if (it == spaces.end()) return {};
  Namespace* ns = it->second.get();
  if (!current.package.empty()) {
    auto pos = std::find(active_packages.begin(), active_packages.end(), lower(current.package));
    if (pos != active_packages.end()) {
      std::size_t index = static_cast<std::size_t>(pos - active_packages.begin());
      if (index > 0) {
        auto r = resolve(ns, current.name, index, false);
        if (r.fn) return r;
      }
      // Only the base layer of this namespace, then its parents.
      auto base = ns->layers.find("");
      if (base != ns->layers.end()) {
        auto f = base->second.find(lower(current.name));
        if (f != base->second.end()) return {ns, "", &f->second};
      }
    }
  }
  return resolve(ns->parent, current.name);
}

bool Engine::is_package(const std::string& name) const {
  return package_names.count(lower(name)) != 0;
}

bool Engine::activate_package(const std::string& name) {
  const auto key = lower(name);
  if (!is_package(name)) return false;
  if (std::find(active_packages.begin(), active_packages.end(), key) != active_packages.end())
    return true;
  active_packages.push_back(key);
  return true;
}

bool Engine::deactivate_package(const std::string& name) {
  // Deactivating a package also deactivates every package activated after
  // it (rebuild policy; the 3.04 scripts never deactivate one).
  auto pos = std::find(active_packages.begin(), active_packages.end(), lower(name));
  if (pos == active_packages.end()) return false;
  active_packages.erase(pos, active_packages.end());
  return true;
}

// ---------------------------------------------------------------- variables

void Engine::bind_variable(const std::string& name, const std::string& value) {
  bound.insert(lower(name));
  set_global(name, Value::of_string(value));
}

void Engine::set_global(const std::string& name, Value v) {
  auto key = lower(name);
  if (bound.count(key) && v.kind != Value::Kind::string) v = Value::of_string(v.str());
  auto it = globals.find(key);
  if (it == globals.end()) globals.emplace(key, std::make_pair(name, std::move(v)));
  else it->second.second = std::move(v);
}

Value Engine::global(const std::string& name) const {
  auto it = globals.find(lower(name));
  return it == globals.end() ? Value{} : it->second.second;
}

bool Engine::has_global(const std::string& name) const {
  return globals.count(lower(name)) != 0;
}

std::vector<std::pair<std::string, Value>> Engine::globals_matching(const std::string& pattern) const {
  std::vector<std::pair<std::string, Value>> result;
  for (const auto& [key, entry] : globals)
    if (match_pattern(pattern, entry.first)) result.push_back(entry);
  return result;
}

// ---------------------------------------------------------------- objects

SimObject* Engine::object(std::uint32_t id) const {
  auto it = objects.find(id);
  return it == objects.end() ? nullptr : it->second.get();
}

SimObject* Engine::find_object(const std::string& ref) const {
  if (ref.empty()) return nullptr;
  std::size_t pos = 0;
  SimObject* obj = nullptr;
  if (std::isdigit(static_cast<unsigned char>(ref[0]))) {
    std::uint32_t id = 0;
    while (pos < ref.size() && std::isdigit(static_cast<unsigned char>(ref[pos])))
      id = id * 10 + static_cast<std::uint32_t>(ref[pos++] - '0');
    if (pos < ref.size() && ref[pos] != '/') return nullptr;
    obj = id == 0 ? nullptr : object(id);
  } else {
    pos = ref.find('/');
    auto it = names.find(lower(ref.substr(0, pos)));
    if (it == names.end()) return nullptr;
    obj = object(it->second);
    if (pos == std::string::npos) pos = ref.size();
  }
  while (obj && pos < ref.size()) {
    ++pos;  // '/'
    auto next = ref.find('/', pos);
    auto part = lower(ref.substr(pos, next == std::string::npos ? std::string::npos : next - pos));
    SimObject* child = nullptr;
    for (auto id : obj->members) {
      auto* m = object(id);
      if (m && lower(m->name) == part) { child = m; break; }
    }
    obj = child;
    pos = next == std::string::npos ? ref.size() : next;
  }
  return obj;
}

void Engine::link_namespace(SimObject* obj) {
  Namespace* cls = space(obj->class_name, true);
  if (obj->name.empty()) { obj->space = cls; return; }
  Namespace* own = space(obj->name, true);
  // A name namespace links to the first class it is given (rebuild policy
  // for a later object of another class with the same name).
  if (own != cls && !own->parent) {
    bool cycle = false;
    for (Namespace* n = cls; n; n = n->parent) if (n == own) cycle = true;
    if (!cycle) own->parent = cls;
  }
  obj->space = own;
}

void Engine::set_name(SimObject* obj, const std::string& name) {
  if (!obj->name.empty()) {
    auto it = names.find(lower(obj->name));
    if (it != names.end() && it->second == obj->id) names.erase(it);
  }
  obj->name = name;
  if (!name.empty()) names[lower(name)] = obj->id;
  link_namespace(obj);
}

std::uint32_t Engine::register_object(std::unique_ptr<SimObject> obj) {
  obj->id = next_id++;
  auto* raw = obj.get();
  objects[raw->id] = std::move(obj);
  set_name(raw, raw->name);
  return raw->id;
}

SimObject* Engine::create_object(const std::string& class_name, const std::string& name,
                                 bool add_to_root) {
  const ClassInfo* info = find_class(class_name);
  if (!info) return nullptr;
  auto obj = std::make_unique<SimObject>();
  obj->class_name = info->name;
  obj->info = info;
  obj->name = name;
  auto id = register_object(std::move(obj));
  auto* raw = object(id);
  if (add_to_root) add_to_set(root_group(), raw);
  return raw;
}

void Engine::add_to_set(SimObject* set, SimObject* obj) {
  if (!set || !obj || !set->info || !set->info->is_set || set == obj) return;
  if (set->info->is_group) {
    if (obj->group == set->id && std::find(set->members.begin(), set->members.end(), obj->id) != set->members.end())
      return;
    if (auto* old = object(obj->group); old && old != set) remove_from_set(old, obj);
    obj->group = set->id;
  }
  if (std::find(set->members.begin(), set->members.end(), obj->id) == set->members.end())
    set->members.push_back(obj->id);
}

void Engine::remove_from_set(SimObject* set, SimObject* obj) {
  if (!set || !obj) return;
  set->members.erase(std::remove(set->members.begin(), set->members.end(), obj->id), set->members.end());
  if (set->info && set->info->is_group && obj->group == set->id) obj->group = 0;
}

void Engine::delete_object(std::uint32_t id) {
  if (id == root_id) return;
  auto* obj = object(id);
  if (!obj) return;
  if (obj->info && obj->info->is_group) {
    auto members = obj->members;
    for (auto m : members) delete_object(m);
  }
  for (auto& [oid, other] : objects)
    if (other->info && other->info->is_set)
      other->members.erase(std::remove(other->members.begin(), other->members.end(), id), other->members.end());
  if (!obj->name.empty()) {
    auto it = names.find(lower(obj->name));
    if (it != names.end() && it->second == id) names.erase(it);
  }
  events.erase(std::remove_if(events.begin(), events.end(),
                              [&](const Event& e) { return e.object == id; }), events.end());
  // A deleted map is no longer pushed; a deleted dialog leaves the canvas.
  action_maps.erase(std::remove(action_maps.begin(), action_maps.end(), id), action_maps.end());
  dialogs.erase(std::remove_if(dialogs.begin(), dialogs.end(),
                               [&](const DialogLayer& d) { return d.control == id; }), dialogs.end());
  edits.erase(id);
  if (first_responder == id) first_responder = 0;
  objects.erase(id);
}

// ---------------------------------------------------------------- events

std::uint32_t Engine::schedule(std::uint32_t delay, std::uint32_t object_id, Args argv, bool method) {
  Event e{next_event++, time_ms + delay, object_id, std::move(argv), method};
  events.push_back(std::move(e));
  return events.back().id;
}

bool Engine::cancel(std::uint32_t event) {
  auto before = events.size();
  events.erase(std::remove_if(events.begin(), events.end(),
                              [&](const Event& e) { return e.id == event; }), events.end());
  return events.size() != before;
}

bool Engine::pending(std::uint32_t event) const {
  return std::any_of(events.begin(), events.end(), [&](const Event& e) { return e.id == event; });
}

void Engine::advance(std::uint32_t ms) {
  const std::uint32_t target = time_ms + ms;
  for (;;) {
    auto due = events.end();
    for (auto it = events.begin(); it != events.end(); ++it)
      if (it->when <= target && (due == events.end() || it->when < due->when)) due = it;
    if (due == events.end()) break;
    Event e = std::move(*due);
    events.erase(due);
    if (e.when > time_ms) time_ms = e.when;
    if (e.argv.empty()) continue;
    const std::string name = e.argv[0];
    Args args(e.argv.begin() + 1, e.argv.end());
    if (e.object && !object(e.object)) continue;
    if (e.method) call_method(object(e.object), name, args);
    else call_function(name, args);
  }
  time_ms = target;
}

// ---------------------------------------------------------------- paths

const CodeBlock* Engine::current_block() const {
  for (auto it = frames.rbegin(); it != frames.rend(); ++it)
    if ((*it)->block) return (*it)->block.get();
  return nullptr;
}

std::string Engine::expand_path(const std::string& path) const {
  const CodeBlock* block = current_block();
  return expand_path_from(block ? block->name : std::string(), path);
}

std::string Engine::expand_path_from(const std::string& script, const std::string& path) {
  std::string p = path;
  for (auto& c : p) if (c == '\\') c = '/';
  std::string base;
  {
    auto slash = script.rfind('/');
    base = slash == std::string::npos ? std::string() : script.substr(0, slash);
  }
  std::string result;
  if (p.rfind("./", 0) == 0) {
    result = base.empty() ? p.substr(2) : base + "/" + p.substr(2);
  } else if (p.rfind("~/", 0) == 0) {
    std::string mod = base.substr(0, base.find('/'));
    result = mod.empty() ? p.substr(2) : mod + "/" + p.substr(2);
  } else {
    result = p;
  }
  // Collapse "dir/../" pairs.
  std::vector<std::string> parts;
  std::stringstream ss(result);
  std::string part;
  while (std::getline(ss, part, '/')) {
    if (part.empty() || part == ".") continue;
    if (part == ".." && !parts.empty() && parts.back() != "..") parts.pop_back();
    else parts.push_back(part);
  }
  std::string joined;
  for (std::size_t i = 0; i < parts.size(); ++i) joined += (i ? "/" : "") + parts[i];
  return joined;
}

// ---------------------------------------------------------------- scripts

std::shared_ptr<CodeBlock> Engine::link(const std::string& name, DsoBlock dso, std::string& error) {
  std::vector<DsoInstruction> decoded;
  InstructionError ierr;
  if (!decode_instructions(dso.code, decoded, ierr)) {
    error = name + ": " + ierr.message + " at word " + std::to_string(ierr.ip);
    return nullptr;
  }
  auto block = std::make_shared<CodeBlock>();
  block->name = name;
  for (const auto& id : dso.identifiers) {
    for (auto use : id.uses) {
      if (use >= dso.code.size()) { error = name + ": identifier use outside code"; return nullptr; }
      if (id.unnamed) block->unnamed[use] = true;
      block->idents[use] = id.unnamed ? std::string() : id.name;
    }
  }
  block->dso = std::move(dso);
  return block;
}

bool Engine::run_block(std::shared_ptr<CodeBlock> block, std::string* result) {
  try {
    auto value = execute(block, 0, false, nullptr, nullptr, false);
    if (result) *result = value;
    return true;
  } catch (const ScriptError& e) {
    trace.push_back(block->name + ": " + e.message);
    return false;
  }
}

bool Engine::exec_file(const std::string& path, bool no_calls) {
  const std::string script = expand_path(path);
  // Which file runs (rebuild policy matching the stage 0 open order): a
  // plain script the game wrote into the prefs directory is compiled; else
  // a compiled .dso is loaded; else a shipped plain script is compiled.
  std::string source, bytes;
  DsoBlock dso;
  const bool compile = (files.in_prefs(script) || !files.exists(script + ".dso")) &&
                       files.read(script, source);
  if (compile) {
    std::string err;
    if (!compiler) {
      trace.push_back("exec " + script + ": plain script needs the compiler, which is not linked");
      return false;
    }
    if (!compiler(source, script, dso, err)) {
      trace.push_back("exec " + script + ": " + err);
      return false;
    }
  } else if (files.read(script + ".dso", bytes)) {
    DsoError derr;
    std::vector<std::uint8_t> raw(bytes.begin(), bytes.end());
    if (!load_dso(raw, float_order, dso, derr)) {
      trace.push_back("exec " + script + ".dso: " + derr.message);
      return false;
    }
  } else {
    trace.push_back("exec " + script + ": no such file");
    return false;
  }
  std::string err;
  auto block = link(script, std::move(dso), err);
  if (!block) { trace.push_back("exec " + err); return false; }
  trace.push_back("exec " + script);
  try {
    execute(block, 0, false, nullptr, nullptr, no_calls);
  } catch (const ScriptError& e) {
    trace.push_back(script + ": " + e.message);
    return false;
  }
  return true;
}

bool Engine::evaluate(const std::string& source, std::string* result) {
  if (!compiler) {
    trace.push_back("eval: needs the compiler, which is not linked");
    return false;
  }
  DsoBlock dso;
  std::string err;
  if (!compiler(source, "<input>", dso, err)) { trace.push_back("eval: " + err); return false; }
  auto block = link("<input>", std::move(dso), err);
  if (!block) { trace.push_back("eval: " + err); return false; }
  return run_block(block, result);
}

std::string Engine::invoke(const Resolved& r, Args& argv, SimObject* self, const std::string& where) {
  const Function& fn = *r.fn;
  if (fn.native) {
    if (argv.size() < fn.min || (fn.max && argv.size() > fn.max)) {
      warn(where + ": " + fn.space + "::" + fn.name + " - wrong number of arguments.");
      warn(where + ": usage: " + fn.usage);
      return {};
    }
    return fn.native(*this, self, argv);
  }
  if (frames.size() >= limits.call_depth) throw ScriptError{"call depth limit"};
  return execute(fn.code, fn.ip, true, &fn, &argv, false);
}

std::string Engine::call_function(const std::string& name, Args args) {
  Args argv;
  std::string fname = name, ns;
  auto sep = name.find("::");
  if (sep != std::string::npos) { ns = name.substr(0, sep); fname = name.substr(sep + 2); }
  argv.push_back(fname);
  argv.insert(argv.end(), args.begin(), args.end());
  Namespace* n = space(ns, false);
  auto r = n ? resolve(n, fname) : Resolved{};
  if (!r.fn) { trace.push_back("call " + name + ": unknown function"); return {}; }
  try {
    return invoke(r, argv, nullptr, "<engine>");
  } catch (const ScriptError& e) {
    trace.push_back("call " + name + ": " + e.message);
    return {};
  }
}

std::string Engine::call_method(SimObject* obj, const std::string& name, Args args) {
  if (!obj) return {};
  Args argv;
  argv.push_back(name);
  argv.push_back(std::to_string(obj->id));
  argv.insert(argv.end(), args.begin(), args.end());
  auto r = resolve(obj->space, name);
  if (!r.fn) return {};
  try {
    return invoke(r, argv, obj, "<engine>");
  } catch (const ScriptError& e) {
    trace.push_back("call " + name + ": " + e.message);
    return {};
  }
}

} // namespace Torque
