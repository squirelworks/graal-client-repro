#include "scripts.hpp"

#include "../net/gtypes.hpp"

#include <algorithm>
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
  machine_.addCommand("echo", "s", [this](gs2::Machine& m, gs2::Var&, std::vector<gs2::Value>& args) {
    note("echo: " + m.toString(args[0]));
    return gs2::Value::number(0);
  });
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
      std::string name(body);
      weapons_.erase(lower(name));
      return true;
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
