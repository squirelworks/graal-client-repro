// Stock console functions and methods the 3.04 scripts call (Graal_analysis
// torque/study-torque-clients.md section 5 and 5.1). Argument counts include
// the command name, and the object on a method; max 0 means no upper bound.
// Usage strings are this rebuild's own wording.

#include "internal.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstring>
#include <sstream>

namespace Torque {
namespace {

const char* const word_set = " \t\n";
const char* const field_set = "\t\n";
const char* const record_set = "\n";

bool is_sep(char c, const char* set) { return c && std::strchr(set, c) != nullptr; }

// Units are split by every separator character; consecutive separators make
// empty units (rebuild policy, to compare against the original).
std::vector<std::pair<std::size_t, std::size_t>> units(const std::string& s, const char* set) {
  std::vector<std::pair<std::size_t, std::size_t>> out;  // (start, length)
  if (s.empty()) return out;
  std::size_t start = 0;
  for (std::size_t i = 0; i < s.size(); ++i) {
    if (is_sep(s[i], set)) {
      out.push_back({start, i - start});
      start = i + 1;
    }
  }
  if (start < s.size()) out.push_back({start, s.size() - start});
  return out;
}

std::string get_unit(const std::string& s, std::size_t index, const char* set) {
  auto u = units(s, set);
  if (index >= u.size()) return {};
  return s.substr(u[index].first, u[index].second);
}

std::string get_units(const std::string& s, std::size_t first, std::size_t last, const char* set) {
  auto u = units(s, set);
  if (first >= u.size() || last < first) return {};
  if (last >= u.size()) last = u.size() - 1;
  const auto begin = u[first].first;
  const auto end = u[last].first + u[last].second;
  return s.substr(begin, end - begin);
}

std::string set_unit(const std::string& s, std::size_t index, const std::string& value, const char* set) {
  auto u = units(s, set);
  std::string out;
  const char sep = set[0];
  const std::size_t count = std::max(u.size(), index + 1);
  for (std::size_t i = 0; i < count; ++i) {
    if (i) out += i < u.size() ? s[u[i].first - 1] : sep;
    if (i == index) out += value;
    else if (i < u.size()) out += s.substr(u[i].first, u[i].second);
  }
  return out;
}

std::string remove_unit(const std::string& s, std::size_t index, const char* set) {
  auto u = units(s, set);
  if (index >= u.size()) return s;
  std::string out;
  bool first = true;
  for (std::size_t i = 0; i < u.size(); ++i) {
    if (i == index) continue;
    if (!first) out += set[0];
    out += s.substr(u[i].first, u[i].second);
    first = false;
  }
  return out;
}

std::size_t index_arg(const std::string& s) {
  const auto v = static_cast<std::int32_t>(parse_int(s));
  return v < 0 ? static_cast<std::size_t>(-1) : static_cast<std::size_t>(v);
}

std::string b(bool v) { return v ? "1" : "0"; }

std::string canonical_device(const std::string& d) {
  std::string l = lower(d);
  while (!l.empty() && std::isdigit(static_cast<unsigned char>(l.back()))) l.pop_back();
  return l;
}

// A bound action string: lower case, and "enter" stored as Torque's key name
// "return" (lab, 3.04: GlobalActionMap.save() prints "alt return" for the
// "alt enter" default.bind.cs binds).
std::string canonical_action(const std::string& action) {
  std::string l = lower(action);
  const auto start = l.find_last_of(' ') == std::string::npos ? 0 : l.find_last_of(' ') + 1;
  if (l.compare(start, std::string::npos, "enter") == 0) l.replace(start, std::string::npos, "return");
  return l;
}

std::uint32_t next_random(Engine& e) {
  // 32-bit LCG (rebuild policy; the original generator is not read).
  e.random_state = e.random_state * 1664525u + 1013904223u;
  return e.random_state;
}

std::string object_ref(const SimObject* o) {
  return o->name.empty() ? std::to_string(o->id) : o->name;
}

} // namespace

void register_builtins(Engine& e) {
  using A = Args;
  auto fn = [&](const char* name, std::size_t min, std::size_t max, const char* usage, NativeFn f) {
    e.add_function("", name, min, max, usage, std::move(f));
  };
  auto method = [&](const char* cls, const char* name, std::size_t min, std::size_t max,
                    const char* usage, NativeFn f) {
    e.add_function(cls, name, min, max, usage,
                   [f = std::move(f)](Engine& en, SimObject* self, A& a) -> std::string {
                     if (!self) self = a.size() > 1 ? en.find_object(a[1]) : nullptr;
                     if (!self) return {};
                     return f(en, self, a);
                   });
  };

  e.add_class({"ScriptObject", "SimObject", true, false, false});
  e.add_class({"FileObject", "SimObject", true, false, false});
  e.add_class({"ActionMap", "SimObject", true, false, false});

  // ------------------------------------------------------------ console
  auto join = [](const A& a, std::size_t from) {
    std::string s;
    for (std::size_t i = from; i < a.size(); ++i) s += a[i];
    return s;
  };
  fn("echo", 2, 0, "echo(text [, ... ])", [join](Engine& en, SimObject*, A& a) { en.print(join(a, 1)); return std::string(); });
  fn("warn", 2, 0, "warn(text [, ...])", [join](Engine& en, SimObject*, A& a) { en.print(join(a, 1)); return std::string(); });
  fn("error", 2, 0, "error(text [, ...])", [join](Engine& en, SimObject*, A& a) { en.print(join(a, 1)); return std::string(); });
  fn("setLogMode", 2, 2, "setLogMode(mode)", [](Engine& en, SimObject*, A& a) {
    en.log_mode = static_cast<int>(parse_int(a[1]));
    return std::string();
  });
  fn("setModPaths", 2, 2, "setModPaths(paths)", [](Engine& en, SimObject*, A& a) { en.mod_paths = a[1]; return std::string(); });
  fn("getModPaths", 1, 1, "getModPaths()", [](Engine& en, SimObject*, A&) { return en.mod_paths; });
  fn("exec", 2, 4, "exec(fileName [, nocalls [, journalScript]])", [](Engine& en, SimObject*, A& a) {
    const bool no_calls = a.size() > 2 && parse_int(a[2]) != 0;
    return b(en.exec_file(a[1], no_calls));
  });
  fn("eval", 2, 2, "eval(consoleString)", [](Engine& en, SimObject*, A& a) {
    std::string result;
    en.evaluate(a[1], &result);
    return result;
  });
  fn("export", 2, 4, "export(searchString [, path [, append]])", [](Engine& en, SimObject*, A& a) {
    std::string out;
    std::vector<std::string> lines;
    for (const auto& [name, value] : en.globals_matching(a[1])) {
      const std::string text = value.kind == Value::Kind::string
                                   ? "\"" + expand_escape(value.str()) + "\""
                                   : value.str();
      lines.push_back(name + " = " + text + ";");
    }
    if (a.size() > 2 && !a[2].empty()) {
      for (const auto& l : lines) out += l + "\r\n";
      const bool append = a.size() > 3 && parse_int(a[3]) != 0;
      if (!en.files.write(en.expand_path(a[2]), out, append))
        en.trace.push_back("export: cannot write " + en.expand_path(a[2]));
    } else {
      for (const auto& l : lines) en.print(l);
    }
    return std::string();
  });
  fn("deleteVariables", 2, 2, "deleteVariables(wildCard)", [](Engine& en, SimObject*, A& a) {
    for (const auto& [name, value] : en.globals_matching(a[1])) en.set_global(name, Value{});
    return std::string();
  });
  fn("quit", 1, 1, "quit()", [](Engine& en, SimObject*, A&) { en.quit_requested = true; return std::string(); });

  // ------------------------------------------------------------ packages
  fn("activatePackage", 2, 2, "activatePackage(package)", [](Engine& en, SimObject*, A& a) {
    en.activate_package(a[1]);
    return std::string();
  });
  fn("deactivatePackage", 2, 2, "deactivatePackage(package)", [](Engine& en, SimObject*, A& a) {
    en.deactivate_package(a[1]);
    return std::string();
  });
  fn("isPackage", 2, 2, "isPackage(package)", [](Engine& en, SimObject*, A& a) { return b(en.is_package(a[1])); });

  // ------------------------------------------------------------ objects
  fn("isObject", 2, 2, "isObject(object)", [](Engine& en, SimObject*, A& a) { return b(en.find_object(a[1]) != nullptr); });
  fn("nameToID", 2, 2, "nameToID(object)", [](Engine& en, SimObject*, A& a) {
    auto* o = en.find_object(a[1]);
    return o ? std::to_string(o->id) : std::string("-1");
  });

  // ------------------------------------------------------------ events
  fn("schedule", 4, 0, "schedule(time, refobject|0, command, <arg1...argN>)", [](Engine& en, SimObject*, A& a) {
    SimObject* ref = en.find_object(a[2]);
    A argv(a.begin() + 3, a.end());
    return std::to_string(en.schedule(parse_int(a[1]), ref ? ref->id : 0, argv, false));
  });
  fn("cancel", 2, 2, "cancel(eventId)", [](Engine& en, SimObject*, A& a) { en.cancel(parse_int(a[1])); return std::string(); });
  fn("isEventPending", 2, 2, "isEventPending(eventId)", [](Engine& en, SimObject*, A& a) { return b(en.pending(parse_int(a[1]))); });
  fn("getSimTime", 1, 1, "getSimTime()", [](Engine& en, SimObject*, A&) { return std::to_string(en.sim_time()); });

  // ------------------------------------------------------------ files
  fn("isFile", 2, 2, "isFile(fileName)", [](Engine& en, SimObject*, A& a) { return b(en.files.exists(en.expand_path(a[1]))); });
  fn("ExpandFilename", 2, 2, "ExpandFilename(filename)", [](Engine& en, SimObject*, A& a) { return en.expand_path(a[1]); });
  fn("fileBase", 2, 2, "fileBase(fileName)", [](Engine&, SimObject*, A& a) {
    auto n = a[1].substr(a[1].find_last_of("/\\") == std::string::npos ? 0 : a[1].find_last_of("/\\") + 1);
    auto dot = n.rfind('.');
    return dot == std::string::npos ? n : n.substr(0, dot);
  });
  fn("fileName", 2, 2, "fileName(fileName)", [](Engine&, SimObject*, A& a) {
    auto slash = a[1].find_last_of("/\\");
    return slash == std::string::npos ? a[1] : a[1].substr(slash + 1);
  });
  fn("filePath", 2, 2, "filePath(fileName)", [](Engine&, SimObject*, A& a) {
    auto slash = a[1].find_last_of("/\\");
    return slash == std::string::npos ? std::string() : a[1].substr(0, slash);
  });
  fn("fileExt", 2, 2, "fileExt(fileName)", [](Engine&, SimObject*, A& a) {
    auto slash = a[1].find_last_of("/\\");
    auto dot = a[1].rfind('.');
    return (dot == std::string::npos || (slash != std::string::npos && dot < slash)) ? std::string() : a[1].substr(dot);
  });
  fn("findFirstFile", 2, 2, "findFirstFile(pattern)", [](Engine& en, SimObject*, A& a) {
    en.file_search.clear();
    en.file_search_pos = 0;
    const std::string pattern = en.expand_path(a[1]);
    for (const auto& f : en.files.list())
      if (match_pattern(pattern, f)) en.file_search.push_back(f);
    return en.file_search.empty() ? std::string() : en.file_search[en.file_search_pos++];
  });
  fn("findNextFile", 1, 2, "findNextFile(pattern)", [](Engine& en, SimObject*, A&) {
    return en.file_search_pos < en.file_search.size() ? en.file_search[en.file_search_pos++] : std::string();
  });
  fn("getFileCount", 2, 2, "getFileCount(pattern)", [](Engine& en, SimObject*, A& a) {
    std::size_t n = 0;
    const std::string pattern = en.expand_path(a[1]);
    for (const auto& f : en.files.list()) n += match_pattern(pattern, f) ? 1 : 0;
    return std::to_string(n);
  });

  // ------------------------------------------------------------ strings
  fn("strlen", 2, 2, "strlen(string)", [](Engine&, SimObject*, A& a) { return std::to_string(a[1].size()); });
  fn("strstr", 3, 3, "strstr(string, substring)", [](Engine&, SimObject*, A& a) {
    auto p = a[1].find(a[2]);
    return p == std::string::npos ? std::string("-1") : std::to_string(p);
  });
  fn("strpos", 3, 4, "strpos(string, substring [, offset])", [](Engine&, SimObject*, A& a) {
    std::size_t off = a.size() > 3 ? index_arg(a[3]) : 0;
    if (off > a[1].size()) return std::string("-1");
    auto p = a[1].find(a[2], off);
    return p == std::string::npos ? std::string("-1") : std::to_string(p);
  });
  fn("strcmp", 3, 3, "strcmp(one, two)", [](Engine&, SimObject*, A& a) {
    int c = a[1].compare(a[2]);
    return std::to_string(c < 0 ? -1 : c > 0 ? 1 : 0);
  });
  fn("stricmp", 3, 3, "stricmp(one, two)", [](Engine&, SimObject*, A& a) {
    int c = lower(a[1]).compare(lower(a[2]));
    return std::to_string(c < 0 ? -1 : c > 0 ? 1 : 0);
  });
  fn("strupr", 2, 2, "strupr(string)", [](Engine&, SimObject*, A& a) {
    std::string s = a[1];
    for (auto& c : s) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    return s;
  });
  fn("strlwr", 2, 2, "strlwr(string)", [](Engine&, SimObject*, A& a) { return lower(a[1]); });
  fn("strreplace", 4, 4, "strreplace(string, from, to)", [](Engine&, SimObject*, A& a) {
    if (a[2].empty()) return a[1];
    std::string out;
    std::size_t pos = 0;
    for (;;) {
      auto hit = a[1].find(a[2], pos);
      if (hit == std::string::npos) { out += a[1].substr(pos); break; }
      out += a[1].substr(pos, hit - pos) + a[3];
      pos = hit + a[2].size();
    }
    return out;
  });
  auto trim_left = [](const std::string& s) {
    std::size_t i = 0;
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i;
    return s.substr(i);
  };
  auto trim_right = [](const std::string& s) {
    std::size_t i = s.size();
    while (i > 0 && (s[i - 1] == ' ' || s[i - 1] == '\t' || s[i - 1] == '\n' || s[i - 1] == '\r')) --i;
    return s.substr(0, i);
  };
  fn("ltrim", 2, 2, "ltrim(string)", [trim_left](Engine&, SimObject*, A& a) { return trim_left(a[1]); });
  fn("rtrim", 2, 2, "rtrim(string)", [trim_right](Engine&, SimObject*, A& a) { return trim_right(a[1]); });
  fn("trim", 2, 2, "trim(string)", [trim_left, trim_right](Engine&, SimObject*, A& a) { return trim_right(trim_left(a[1])); });
  fn("stripChars", 3, 3, "stripChars(string, chars)", [](Engine&, SimObject*, A& a) {
    std::string out;
    for (char c : a[1]) if (a[2].find(c) == std::string::npos) out += c;
    return out;
  });
  fn("stripMLControlChars", 2, 2, "stripMLControlChars(string)", [](Engine&, SimObject*, A& a) {
    std::string out;
    bool tag = false;
    for (char c : a[1]) {
      if (c == '<') tag = true;
      else if (c == '>' && tag) tag = false;
      else if (!tag) out += c;
    }
    return out;
  });
  fn("getSubStr", 4, 4, "getSubStr(string, start, numChars)", [](Engine&, SimObject*, A& a) {
    const auto start = static_cast<std::int32_t>(parse_int(a[2]));
    const auto count = static_cast<std::int32_t>(parse_int(a[3]));
    if (start < 0 || count <= 0 || static_cast<std::size_t>(start) >= a[1].size()) return std::string();
    return a[1].substr(static_cast<std::size_t>(start), static_cast<std::size_t>(count));
  });
  fn("expandEscape", 2, 2, "expandEscape(string)", [](Engine&, SimObject*, A& a) { return expand_escape(a[1]); });

  struct UnitSet { const char* get; const char* gets; const char* count; const char* set; const char* remove; const char* chars; };
  for (const UnitSet& u : {UnitSet{"getWord", "getWords", "getWordCount", "setWord", "removeWord", word_set},
                           UnitSet{"getField", "getFields", "getFieldCount", "setField", "removeField", field_set},
                           UnitSet{"getRecord", "getRecords", "getRecordCount", "setRecord", "removeRecord", record_set}}) {
    const char* chars = u.chars;
    fn(u.get, 3, 3, "(text, index)", [chars](Engine&, SimObject*, A& a) { return get_unit(a[1], index_arg(a[2]), chars); });
    fn(u.gets, 3, 4, "(text, first [, last])", [chars](Engine&, SimObject*, A& a) {
      return get_units(a[1], index_arg(a[2]), a.size() > 3 ? index_arg(a[3]) : static_cast<std::size_t>(-2), chars);
    });
    fn(u.count, 2, 2, "(text)", [chars](Engine&, SimObject*, A& a) { return std::to_string(units(a[1], chars).size()); });
    fn(u.set, 4, 4, "(text, index, replace)", [chars](Engine&, SimObject*, A& a) { return set_unit(a[1], index_arg(a[2]), a[3], chars); });
    fn(u.remove, 3, 3, "(text, index)", [chars](Engine&, SimObject*, A& a) { return remove_unit(a[1], index_arg(a[2]), chars); });
  }
  fn("firstWord", 2, 2, "firstWord(text)", [](Engine&, SimObject*, A& a) { return get_unit(a[1], 0, word_set); });
  fn("restWords", 2, 2, "restWords(text)", [](Engine&, SimObject*, A& a) {
    auto p = a[1].find_first_of(word_set);
    return p == std::string::npos ? std::string() : a[1].substr(p + 1);
  });

  // ------------------------------------------------------------ numbers
  fn("setRandomSeed", 1, 2, "setRandomSeed([seed])", [](Engine& en, SimObject*, A& a) {
    en.random_state = a.size() > 1 ? parse_int(a[1]) : en.sim_time() + 1;
    return std::string();
  });
  fn("getRandomSeed", 1, 1, "getRandomSeed()", [](Engine& en, SimObject*, A&) { return format_int(en.random_state); });
  fn("getRandom", 1, 3, "getRandom([min [, max]])", [](Engine& en, SimObject*, A& a) {
    const auto r = next_random(en);
    if (a.size() == 1) return format_float((r >> 8) / 16777216.0);
    std::int64_t lo = 0, hi = static_cast<std::int32_t>(parse_int(a[1]));
    if (a.size() > 2) { lo = hi; hi = static_cast<std::int32_t>(parse_int(a[2])); }
    if (hi < lo) std::swap(lo, hi);
    return std::to_string(lo + static_cast<std::int64_t>(r % static_cast<std::uint64_t>(hi - lo + 1)));
  });
  auto math1 = [&](const char* name, double (*f)(double)) {
    fn(name, 2, 2, "(value)", [f](Engine&, SimObject*, A& a) { return format_float(f(parse_float(a[1]))); });
  };
  math1("mFloor", [](double v) { return std::floor(v); });
  math1("mCeil", [](double v) { return std::ceil(v); });
  math1("mAbs", [](double v) { return std::fabs(v); });
  math1("mSqrt", [](double v) { return std::sqrt(v); });
  fn("mPow", 3, 3, "mPow(base, exponent)", [](Engine&, SimObject*, A& a) {
    return format_float(std::pow(parse_float(a[1]), parse_float(a[2])));
  });

  // ------------------------------------------------------------ SimObject
  method("SimObject", "getId", 2, 2, "obj.getId()", [](Engine&, SimObject* o, A&) { return std::to_string(o->id); });
  method("SimObject", "getName", 2, 2, "obj.getName()", [](Engine&, SimObject* o, A&) { return o->name; });
  method("SimObject", "setName", 3, 3, "obj.setName(newName)", [](Engine& en, SimObject* o, A& a) {
    en.set_name(o, a[2]);
    return std::string();
  });
  method("SimObject", "getClassName", 2, 2, "obj.getClassName()", [](Engine&, SimObject* o, A&) { return o->class_name; });
  method("SimObject", "getGroup", 2, 2, "obj.getGroup()", [](Engine&, SimObject* o, A&) {
    return o->group || o->id ? std::to_string(o->group) : std::string("-1");
  });
  method("SimObject", "delete", 2, 2, "obj.delete()", [](Engine& en, SimObject* o, A&) {
    en.delete_object(o->id);
    return std::string();
  });
  method("SimObject", "schedule", 4, 0, "obj.schedule(time, command, <arg1...argN>)", [](Engine& en, SimObject* o, A& a) {
    A argv(a.begin() + 3, a.end());
    return std::to_string(en.schedule(parse_int(a[2]), o->id, argv, true));
  });

  // ------------------------------------------------------------ SimSet
  method("SimSet", "add", 3, 0, "set.add(obj1, ...)", [](Engine& en, SimObject* s, A& a) {
    for (std::size_t i = 2; i < a.size(); ++i) {
      if (auto* o = en.find_object(a[i])) en.add_to_set(s, o);
      else en.trace.push_back("SimSet::add: no object " + a[i]);
    }
    return std::string();
  });
  method("SimSet", "remove", 3, 0, "set.remove(obj1, ...)", [](Engine& en, SimObject* s, A& a) {
    for (std::size_t i = 2; i < a.size(); ++i)
      if (auto* o = en.find_object(a[i])) en.remove_from_set(s, o);
    return std::string();
  });
  method("SimSet", "clear", 2, 2, "set.clear()", [](Engine& en, SimObject* s, A&) {
    auto members = s->members;
    for (auto id : members) en.remove_from_set(s, en.object(id));
    return std::string();
  });
  method("SimSet", "getCount", 2, 2, "set.getCount()", [](Engine&, SimObject* s, A&) { return std::to_string(s->members.size()); });
  method("SimSet", "getObject", 3, 3, "set.getObject(index)", [](Engine&, SimObject* s, A& a) {
    auto i = index_arg(a[2]);
    return i < s->members.size() ? std::to_string(s->members[i]) : std::string("-1");
  });
  method("SimSet", "isMember", 3, 3, "set.isMember(object)", [](Engine& en, SimObject* s, A& a) {
    auto* o = en.find_object(a[2]);
    return b(o && std::find(s->members.begin(), s->members.end(), o->id) != s->members.end());
  });
  method("SimSet", "bringToFront", 3, 3, "set.bringToFront(object)", [](Engine& en, SimObject* s, A& a) {
    auto* o = en.find_object(a[2]);
    auto it = o ? std::find(s->members.begin(), s->members.end(), o->id) : s->members.end();
    if (it != s->members.end()) { s->members.erase(it); s->members.insert(s->members.begin(), o->id); }
    return std::string();
  });
  method("SimSet", "pushToBack", 3, 3, "set.pushToBack(object)", [](Engine& en, SimObject* s, A& a) {
    auto* o = en.find_object(a[2]);
    auto it = o ? std::find(s->members.begin(), s->members.end(), o->id) : s->members.end();
    if (it != s->members.end()) { s->members.erase(it); s->members.push_back(o->id); }
    return std::string();
  });
  method("SimSet", "listObjects", 2, 2, "set.listObjects()", [](Engine& en, SimObject* s, A&) {
    for (auto id : s->members)
      if (auto* o = en.object(id))
        en.print("   " + std::to_string(o->id) + ",\"" + o->name + "\": " + o->class_name);
    return std::string();
  });

  // ------------------------------------------------------------ FileObject
  auto open = [](Engine& en, SimObject* o, const std::string& path, bool write, bool append) {
    o->lines.clear();
    o->line_pos = 0;
    o->writing = false;
    const std::string p = en.expand_path(path);
    if (!write) {
      std::string data;
      if (!en.files.read(p, data)) return false;
      std::string line;
      std::istringstream in(data);
      while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        o->lines.push_back(line);
      }
      return true;
    }
    o->writing = true;
    o->write_path = p;
    return en.files.write(p, "", append);
  };
  method("FileObject", "openForRead", 3, 3, "file.openForRead(filename)", [open](Engine& en, SimObject* o, A& a) { return b(open(en, o, a[2], false, false)); });
  method("FileObject", "openForWrite", 3, 3, "file.openForWrite(filename)", [open](Engine& en, SimObject* o, A& a) { return b(open(en, o, a[2], true, false)); });
  method("FileObject", "openForAppend", 3, 3, "file.openForAppend(filename)", [open](Engine& en, SimObject* o, A& a) { return b(open(en, o, a[2], true, true)); });
  method("FileObject", "isEOF", 2, 2, "file.isEOF()", [](Engine&, SimObject* o, A&) { return b(o->writing || o->line_pos >= o->lines.size()); });
  method("FileObject", "readLine", 2, 2, "file.readLine()", [](Engine&, SimObject* o, A&) {
    return o->line_pos < o->lines.size() ? o->lines[o->line_pos++] : std::string();
  });
  method("FileObject", "writeLine", 3, 3, "file.writeLine(text)", [](Engine& en, SimObject* o, A& a) {
    if (o->writing) en.files.write(o->write_path, a[2] + "\r\n", true);
    return std::string();
  });
  method("FileObject", "close", 2, 2, "file.close()", [](Engine&, SimObject* o, A&) {
    o->lines.clear();
    o->line_pos = 0;
    o->writing = false;
    return std::string();
  });

  // ------------------------------------------------------------ ActionMap
  // Binding data and the saved map file. Routing a key press is stage 3.
  method("ActionMap", "bind", 5, 0, "map.bind(device, action, [modifier spec, mod...], command)", [](Engine&, SimObject* m, A& a) {
    ActionBinding bind;
    bind.device = canonical_device(a[2]);
    bind.action = canonical_action(a[3]);
    bind.command = a.back();
    // Binding a function moves it: its old key is unbound (lab, 3.04: the
    // remap dialog binding K to moveUp drops "up" from the saved config.cs).
    m->binds.erase(std::remove_if(m->binds.begin(), m->binds.end(), [&](const ActionBinding& x) {
      return (x.device == bind.device && x.action == bind.action) ||
             (!x.is_cmd && !bind.command.empty() && lower(x.command) == lower(bind.command));
    }), m->binds.end());
    m->binds.push_back(bind);
    return std::string();
  });
  method("ActionMap", "bindCmd", 6, 6, "map.bindCmd(device, action, makeCmd, breakCmd)", [](Engine&, SimObject* m, A& a) {
    ActionBinding bind;
    bind.device = canonical_device(a[2]);
    bind.action = canonical_action(a[3]);
    bind.make = a[4];
    bind.brk = a[5];
    bind.is_cmd = true;
    m->binds.erase(std::remove_if(m->binds.begin(), m->binds.end(), [&](const ActionBinding& x) {
      return x.device == bind.device && x.action == bind.action;
    }), m->binds.end());
    m->binds.push_back(bind);
    return std::string();
  });
  method("ActionMap", "unbind", 4, 4, "map.unbind(device, action)", [](Engine&, SimObject* m, A& a) {
    const auto device = canonical_device(a[2]), action = canonical_action(a[3]);
    m->binds.erase(std::remove_if(m->binds.begin(), m->binds.end(), [&](const ActionBinding& x) {
      return x.device == device && x.action == action;
    }), m->binds.end());
    return std::string();
  });
  method("ActionMap", "getBinding", 3, 3, "map.getBinding(command)", [](Engine&, SimObject* m, A& a) {
    for (const auto& x : m->binds)
      if (!x.is_cmd && lower(x.command) == lower(a[2])) return x.device + "\t" + x.action;
    return std::string();
  });
  method("ActionMap", "getCommand", 4, 4, "map.getCommand(device, action)", [](Engine&, SimObject* m, A& a) {
    const auto device = canonical_device(a[2]), action = canonical_action(a[3]);
    for (const auto& x : m->binds)
      if (x.device == device && x.action == action) return x.is_cmd ? x.make : x.command;
    return std::string();
  });
  method("ActionMap", "save", 2, 4, "map.save([fileName [, append]])", [](Engine& en, SimObject* m, A& a) {
    const std::string name = object_ref(m);
    // To a file: the header, delete and new lines, then the binds. To the
    // console: the binds only (lab, 3.04).
    const bool to_file = a.size() > 2 && !a[2].empty();
    std::vector<std::string> lines;
    if (to_file) {
      lines.push_back("// Torque Input Map File");
      lines.push_back(name + ".delete();");
      lines.push_back("new ActionMap(" + name + ");");
    }
    for (const auto& x : m->binds) {
      if (x.is_cmd)
        lines.push_back(name + ".bindCmd(" + x.device + ", \"" + expand_escape(x.action) + "\", \"" +
                        expand_escape(x.make) + "\", \"" + expand_escape(x.brk) + "\");");
      else
        lines.push_back(name + ".bind(" + x.device + ", \"" + expand_escape(x.action) + "\", " + x.command + ");");
    }
    if (to_file) {
      std::string out;
      for (const auto& l : lines) out += l + "\n";
      const bool append = a.size() > 3 && parse_int(a[3]) != 0;
      if (!en.files.write(en.expand_path(a[2]), out, append))
        en.trace.push_back("ActionMap::save: cannot write " + en.expand_path(a[2]));
    } else {
      for (const auto& l : lines) en.print(l);
    }
    return std::string();
  });
  method("ActionMap", "push", 2, 2, "map.push()", [](Engine& en, SimObject* m, A&) {
    en.action_maps.erase(std::remove(en.action_maps.begin(), en.action_maps.end(), m->id), en.action_maps.end());
    en.action_maps.push_back(m->id);
    return std::string();
  });
  method("ActionMap", "pop", 2, 2, "map.pop()", [](Engine& en, SimObject* m, A&) {
    en.action_maps.erase(std::remove(en.action_maps.begin(), en.action_maps.end(), m->id), en.action_maps.end());
    return std::string();
  });

  // The engine's own global map exists before any script runs.
  e.create_object("ActionMap", "GlobalActionMap");
}

} // namespace Torque
