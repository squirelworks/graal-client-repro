#include "scripts.hpp"

#include "../net/gtypes.hpp"
#include "../../gs2/engine_commands.hpp"

#include <algorithm>
#include <cmath>
#include <vector>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <iterator>

namespace Quattro::Shell {

namespace {

std::string lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

// The first three comma fields of `s`; `rest` gets what follows the third.
bool three_fields(std::string_view s, std::string& a, std::string& b, std::string& c, std::string_view& rest) {
  size_t p1 = s.find(',');
  if (p1 == std::string_view::npos) return false;
  size_t p2 = s.find(',', p1 + 1);
  if (p2 == std::string_view::npos) return false;
  size_t p3 = s.find(',', p2 + 1);
  a = std::string(s.substr(0, p1));
  b = std::string(s.substr(p1 + 1, p2 - p1 - 1));
  c = std::string(p3 == std::string_view::npos ? s.substr(p2 + 1) : s.substr(p2 + 1, p3 - p2 - 1));
  rest = p3 == std::string_view::npos ? std::string_view() : s.substr(p3 + 1);
  return true;
}

// GINT5 bytes are 32..159, so a comma (44) can be one of them: the values
// are read at fixed widths, either packed (5 bytes each) or with one comma
// between them, told apart by the length. Anything else is refused.
bool read_i5s(std::string_view rest, uint64_t* out, int count) {
  const size_t n = static_cast<size_t>(count);
  size_t stride;
  if (rest.size() == 5 * n) stride = 5;
  else if (rest.size() == 6 * n - 1) stride = 6;
  else return false;
  for (size_t i = 0; i < n; ++i) {
    if (stride == 6 && i > 0 && rest[i * 6 - 1] != ',') return false;
    Net::Reader r(rest.substr(i * stride, 5));
    out[i] = r.gint5();
  }
  return true;
}

// The same values as CSV fields, as gs2lib-style servers write the header
// (Seihai's gserver: `toCSV`, which quotes a field holding a byte past 126,
// a comma, a quote or a backslash and doubles the quotes and backslashes in
// it). The fields' bytes, unquoted and joined, are the GINT5s back to back:
// the DES key's two may be one field of 10 bytes.
bool read_i5s_csv(std::string_view rest, uint64_t* out, int count) {
  std::vector<std::string> fields;
  size_t i = 0;
  while (i <= rest.size()) {
    std::string f;
    if (i < rest.size() && rest[i] == '"') {
      ++i;
      bool closed = false;
      while (i < rest.size()) {
        char c = rest[i];
        if ((c == '"' || c == '\\') && i + 1 < rest.size() && rest[i + 1] == c) {
          f += c;
          i += 2;
        } else if (c == '"') {
          ++i;
          closed = true;
          break;
        } else {
          f += c;
          ++i;
        }
      }
      if (!closed) return false;
      if (i < rest.size() && rest[i] != ',') return false;
    } else {
      size_t e = rest.find(',', i);
      if (e == std::string_view::npos) e = rest.size();
      f.assign(rest.substr(i, e - i));
      i = e;
    }
    fields.push_back(std::move(f));
    ++i;  // the comma
  }
  // A last field of decimal digits that is not a whole GINT5 is the value
  // as text: the lab's gserver build sent the CRC so ("0").
  uint64_t last = 0;
  bool decimalLast = false;
  if (fields.size() >= 2) {
    const std::string& f = fields.back();
    if (!f.empty() && f.size() <= 10 && f.size() != 5 &&
        std::all_of(f.begin(), f.end(), [](char c) { return c >= '0' && c <= '9'; })) {
      decimalLast = true;
      last = std::stoull(f);
      fields.pop_back();
    }
  }
  std::string bytes;
  for (const auto& f : fields) bytes += f;
  const size_t want = static_cast<size_t>(count - (decimalLast ? 1 : 0));
  if (bytes.size() != 5 * want) return false;
  for (size_t k = 0; k < want; ++k) {
    Net::Reader r(std::string_view(bytes).substr(k * 5, 5));
    out[k] = r.gint5();
  }
  if (decimalLast) out[count - 1] = last;
  return true;
}

int to_int(const std::string& s) {
  if (s.empty() || !std::all_of(s.begin(), s.end(), [](char c) { return std::isdigit(static_cast<unsigned char>(c)); }))
    return -1;
  return std::atoi(s.c_str());
}

}  // namespace

std::string to_csv(const std::vector<std::string>& fields) {
  std::string out;
  for (size_t i = 0; i < fields.size(); ++i) {
    if (i) out += ',';
    const std::string& f = fields[i];
    bool quote = false;
    for (unsigned char c : f)
      if (c == ',' || c == '"' || c == '\\' || c > 126) quote = true;
    if (!quote) {
      out += f;
      continue;
    }
    out += '"';
    for (char c : f) {
      if (c == '"' || c == '\\') out += c;
      out += c;
    }
    out += '"';
  }
  return out;
}

std::vector<std::string> from_csv(std::string_view text) {
  std::vector<std::string> fields;
  if (text.empty()) return fields;
  size_t i = 0;
  while (i <= text.size()) {
    std::string f;
    if (i < text.size() && text[i] == '"') {
      ++i;
      while (i < text.size()) {
        char c = text[i];
        if ((c == '"' || c == '\\') && i + 1 < text.size() && text[i + 1] == c) {
          f += c;
          i += 2;
        } else if (c == '"') {
          ++i;
          break;
        } else {
          f += c;
          ++i;
        }
      }
      // Anything up to the comma after a closing quote is kept.
      size_t e = text.find(',', i);
      if (e == std::string_view::npos) e = text.size();
      f.append(text.substr(i, e - i));
      i = e;
    } else {
      size_t e = text.find(',', i);
      if (e == std::string_view::npos) e = text.size();
      f.assign(text.substr(i, e - i));
      i = e;
    }
    fields.push_back(std::move(f));
    ++i;
  }
  return fields;
}

bool parse_script_packet(std::string_view payload, ScriptDescriptor& d, std::string& body) {
  Net::Reader r(payload);
  unsigned h = r.gshort();
  if (!r.ok() || payload.size() < 2 + static_cast<size_t>(h)) return false;
  std::string_view desc = payload.substr(2, h);
  body = std::string(payload.substr(2 + h));
  std::string flag;
  std::string_view rest;
  if (!three_fields(desc, d.type, d.name, flag, rest)) return false;
  d.cache_flag = to_int(flag);
  d.key.reset();
  uint64_t k[2];
  if (read_i5s(rest, k, 2) || read_i5s_csv(rest, k, 2)) d.key = Cache::ScriptKey{static_cast<uint32_t>(k[0]), static_cast<uint32_t>(k[1])};
  return !d.type.empty() && !d.name.empty();
}

bool parse_load_script(std::string_view payload, ScriptDescriptor& d) {
  std::string flag;
  std::string_view rest;
  if (!three_fields(payload, d.type, d.name, flag, rest)) return false;
  d.cache_flag = to_int(flag);
  uint64_t v[3];
  if (!read_i5s(rest, v, 3) && !read_i5s_csv(rest, v, 3)) return false;
  d.key = Cache::ScriptKey{static_cast<uint32_t>(v[0]), static_cast<uint32_t>(v[1])};
  d.crc = static_cast<uint32_t>(v[2]);
  return !d.type.empty() && !d.name.empty();
}

std::string make_script_packet(const ScriptDescriptor& d, std::string_view body) {
  std::string desc = d.type + "," + d.name + "," + std::to_string(d.cache_flag) + ",";
  if (d.key) desc += Net::gint5(d.key->lo) + "," + Net::gint5(d.key->hi);
  return Net::gshort(static_cast<unsigned>(desc.size())) + desc + std::string(body);
}

std::string make_load_script(const ScriptDescriptor& d) {
  Cache::ScriptKey k = d.key.value_or(Cache::ScriptKey{});
  return d.type + "," + d.name + "," + std::to_string(d.cache_flag) + "," + Net::gint5(k.lo) + "," +
         Net::gint5(k.hi) + "," + Net::gint5(d.crc);
}

ScriptHost::ScriptHost() : machine_(gs2::Profile::Engine600) {
  player_ = std::make_shared<gs2::Var>("player");
  player_->setAcceptsAllProperties(true);
  machine_.setPlayer(player_);
  // setTimer, catchevent, join, scheduleevent, cancelevents, trigger,
  // destroy, md5, echo and the file-name helpers (common/cpp/gs2).
  gs2::EngineHost h;
  h.log = [this](const std::string& s) { note("echo: " + s); };
  gs2::addEngineCommands(machine_, std::move(h));
  // findweapon(name): the weapon's object, so a call on it runs that
  // script's function (set B's main use: another weapon's public function).
  machine_.addCommand("findweapon", "s", [this](gs2::Machine& m, gs2::Var&, std::vector<gs2::Value>& a) {
    gs2::VarPtr w = weapon(m.toString(a[0]));
    return w ? gs2::Value::object(w) : gs2::Value::number(0);
  });
  // triggerserver(kind, weapon, params...): "serverside,<weapon>,<params>".
  machine_.addCommand("triggerserver", "ss", [this](gs2::Machine& m, gs2::Var&, std::vector<gs2::Value>& a) {
    std::vector<std::string> f{"serverside"};
    for (size_t i = 1; i < a.size(); ++i) f.push_back(m.toString(a[i]));
    if (send_) send_(38, trigger_body(0, 0, to_csv(f)));
    return gs2::Value::number(0);
  });
  // triggeraction(x, y, action, params...).
  machine_.addCommand("triggeraction", "nns", [this](gs2::Machine& m, gs2::Var&, std::vector<gs2::Value>& a) {
    std::vector<std::string> f;
    for (size_t i = 2; i < a.size(); ++i) f.push_back(m.toString(a[i]));
    if (send_) send_(38, trigger_body(m.toNumber(a[0]), m.toNumber(a[1]), to_csv(f)));
    return gs2::Value::number(0);
  });
}

std::string ScriptHost::trigger_body(double x, double y, const std::string& csv) {
  auto half = [](double v) { return static_cast<unsigned>(std::clamp(static_cast<long>(std::lround(v * 2)), 0L, 223L)); };
  return Net::gint3(0) + Net::gchar(half(x)) + Net::gchar(half(y)) + csv;
}

void ScriptHost::queue_all(const std::string& event, std::vector<gs2::Value> args) {
  for (auto& [n, w] : weapons_)
    if (machine_.hasScript(w)) machine_.queueEvent(w, event, args);
}

std::string ScriptHost::weapon_name(const gs2::Var* v) const {
  for (const auto& [n, w] : weapons_)
    if (w.get() == v) return w->name();
  return {};
}

void ScriptHost::remove_weapon(const std::string& name) {
  auto it = weapons_.find(lower(name));
  if (it == weapons_.end()) return;
  gs2::VarPtr w = it->second;
  weapons_.erase(it);
  if (machine_.hasScript(w)) machine_.setScript(w, std::shared_ptr<const gs2::Script>());
}

std::vector<gs2::VarPtr> ScriptHost::weapon_objects() const {
  std::vector<gs2::VarPtr> out;
  for (const auto& [n, w] : weapons_) out.push_back(w);
  return out;
}

void ScriptHost::note(const std::string& s) {
  log_.push_back(s);
  if (on_log) on_log(s);
}

gs2::VarPtr ScriptHost::weapon(const std::string& name) const {
  auto it = weapons_.find(lower(name));
  return it == weapons_.end() ? nullptr : it->second;
}

bool ScriptHost::fire(const std::string& name) {
  gs2::VarPtr w = weapon(name);
  if (!w || !machine_.hasScript(w)) return false;
  machine_.queueEvent(w, "WeaponFired");  // runs onWeaponFired
  return true;
}

int ScriptHost::keycode(const std::string& key, int ch) {
  static const std::map<std::string, int> kNamed = {
      {"backspace", 8}, {"tab", 9}, {"enter", 13}, {"return", 13}, {"shift", 16}, {"ctrl", 17}, {"alt", 18},
      {"escape", 27}, {"space", 32}, {"pageup", 33}, {"pagedown", 34}, {"end", 35}, {"home", 36},
      {"left", 37}, {"up", 38}, {"right", 39}, {"down", 40}, {"insert", 45}, {"delete", 46},
  };
  if (auto it = kNamed.find(lower(key)); it != kNamed.end()) return it->second;
  if (key.size() == 1) return std::toupper(static_cast<unsigned char>(key[0]));
  if (key.size() >= 2 && (key[0] == 'f' || key[0] == 'F') && std::isdigit(static_cast<unsigned char>(key[1])))
    return 111 + std::atoi(key.c_str() + 1);  // F1 is 112
  return ch;
}

void ScriptHost::key_pressed(const std::string& key, int ch) {
  int code = keycode(key, ch);
  std::string text = ch > 0 && ch < 256 ? std::string(1, static_cast<char>(ch)) : std::string();
  for (auto& [n, w] : weapons_)
    if (machine_.hasScript(w))
      machine_.queueEvent(w, "KeyPressed", {gs2::Value::number(code), gs2::Value::string(text)});
}

std::string ScriptHost::cache_path(const ScriptDescriptor& d) const {
  if (cache_dir_.empty()) return {};
  // Path separators and dots in the name are kept out of the path.
  std::string safe;
  for (char c : d.name) safe.push_back((c == '/' || c == '\\' || c == ':' || c == '.') ? '_' : c);
  return cache_dir_ + (d.type == "class" ? "/classes/" : "/weapons/") + safe + ".code";
}

void ScriptHost::load(const ScriptDescriptor& d, const std::string& body) {
  if (d.type == "class") {
    classes_[d.name] = body;
    note("class " + d.name + " loaded");
    return;
  }
  gs2::VarPtr w = weapon(d.name);
  if (!w) {
    w = machine_.newVar(d.name);
    weapons_[lower(d.name)] = w;
  }
  std::string err;
  if (!machine_.setScript(w, body, &err))
    note("weapon " + d.name + ": " + err);
  else
    note("weapon " + d.name + " loaded");
}

bool ScriptHost::on_message(int id, std::string_view body) {
  switch (id) {
    case 33: {  // weapon add: the name
      Net::Reader r(body);
      std::string name = r.gstring();
      if (!r.ok() || name.empty()) name = std::string(body);
      if (!weapon(name)) weapons_[lower(name)] = machine_.newVar(name);
      return true;
    }
    case 34: {  // weapon delete
      remove_weapon(std::string(body));
      return true;
    }
    case 48: {  // PLO_TRIGGERACTION: GSHORT player, GINT3 NPC, GCHAR x, GCHAR y, "action,params"
      Net::Reader r(body);
      r.gshort();
      r.gint3();
      r.gchar();
      r.gchar();
      if (!r.ok()) return false;
      std::vector<std::string> f = from_csv(r.rest());
      if (f.empty()) return false;
      std::string action = lower(f[0]);
      while (!action.empty() && action.back() == ' ') action.pop_back();
      if (action == "clientside") {
        if (f.size() < 2) return true;
        gs2::VarPtr w = weapon(f[1]);
        if (!w || !machine_.hasScript(w)) {
          note("clientside action for " + f[1] + ", which has no script");
          return true;
        }
        std::vector<gs2::Value> params;
        for (size_t i = 2; i < f.size(); ++i) params.push_back(gs2::Value::string(f[i]));
        machine_.queueEvent(w, "ActionClientSide", std::move(params));
        return true;
      }
      std::vector<gs2::Value> params;
      for (size_t i = 1; i < f.size(); ++i) params.push_back(gs2::Value::string(f[i]));
      queue_all("Action" + action, std::move(params));
      return false;  // the program may want it too
    }
    case 140: {
      ScriptDescriptor d;
      std::string b;
      if (!parse_script_packet(body, d, b)) {
        note("bad script packet");
        return true;
      }
      std::string path = cache_path(d);
      if (d.cache_flag == 1 && d.key && !path.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(std::filesystem::path(path).parent_path(), ec);
        std::ofstream(path, std::ios::binary) << Cache::write_grescr(b, *d.key);
      }
      load(d, b);
      return true;
    }
    case 197: {
      ScriptDescriptor d;
      if (!parse_load_script(body, d)) {
        note("bad load-script packet");
        return true;
      }
      std::string path = cache_path(d), file;
      if (!path.empty()) {
        std::ifstream in(path, std::ios::binary);
        if (in) file.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
      }
      Cache::GrescrResult r = Cache::read_grescr(file, d.cache_flag, d.key, d.crc);
      if (r.success) {
        load(d, r.body);
      } else {
        note(d.type + " " + d.name + ": not cached, asking again");
        if (send_) send_(d.type == "class" ? 161 : Cache::kPliUpdateScript, d.name);
      }
      return true;
    }
    case 190:  // onServerListerConnect, to every loaded script
      for (auto& [n, w] : weapons_)
        if (machine_.hasScript(w)) machine_.queueEvent(w, "ServerListerConnect");  // runs onServerListerConnect
      return true;
    default:
      return false;
  }
}

}  // namespace Quattro::Shell
