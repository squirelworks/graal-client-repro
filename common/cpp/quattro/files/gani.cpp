#include "gani.hpp"

#include <cctype>
#include <cstdlib>

namespace Quattro::Files {

namespace {

std::string lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

std::vector<std::string> words(std::string_view s) {
  std::vector<std::string> out;
  size_t i = 0;
  while (i < s.size()) {
    while (i < s.size() && static_cast<unsigned char>(s[i]) <= ' ') ++i;
    size_t st = i;
    while (i < s.size() && static_cast<unsigned char>(s[i]) > ' ') ++i;
    if (i > st) out.emplace_back(s.substr(st, i - st));
  }
  return out;
}

bool to_int(const std::string& s, int& v) {
  if (s.empty()) return false;
  char* end = nullptr;
  long n = std::strtol(s.c_str(), &end, 10);
  if (*end) return false;
  v = static_cast<int>(n);
  return true;
}

int int_or(const std::string& s, int def) {
  int v;
  return to_int(s, v) ? v : def;
}

// "id x y, id x y, PARAM1 x y"
bool parse_row(std::string_view row, std::vector<GaniPart>& parts) {
  parts.clear();
  size_t st = 0;
  for (size_t i = 0; i <= row.size(); ++i) {
    if (i < row.size() && row[i] != ',') continue;
    auto w = words(row.substr(st, i - st));
    st = i + 1;
    if (w.empty()) continue;
    if (w.size() < 3) return false;
    GaniPart p;
    std::string k = lower(w[0]);
    int n = 0;
    if (k.compare(0, 5, "param") == 0 && to_int(k.substr(5), n) && n >= 1) {
      p.sprite = kParamSprite - n;
    } else if (!to_int(w[0], p.sprite) || p.sprite < 0) {
      return false;
    }
    p.x = int_or(w[1], 0);
    p.y = int_or(w[2], 0);
    parts.push_back(p);
  }
  return true;
}

struct Attach {
  int parent, child, dx, dy;
  bool under;
};

void put(const std::vector<Attach>& at, int sprite, int x, int y, int depth, std::vector<GaniPart>& out) {
  // Under, the sprite, over; a chain stops 4 deep.
  if (depth < 4)
    for (const auto& a : at)
      if (a.under && a.parent == sprite) put(at, a.child, x + a.dx, y + a.dy, depth + 1, out);
  out.push_back({sprite, x, y});
  if (depth < 4)
    for (const auto& a : at)
      if (!a.under && a.parent == sprite) put(at, a.child, x + a.dx, y + a.dy, depth + 1, out);
}

}  // namespace

const GaniSprite* Gani::sprite(int id) const {
  for (const auto& s : sprites)
    if (s.id == id) return &s;
  return nullptr;
}

int Gani::total_ticks() const {
  int t = 0;
  for (const auto& s : steps) t += s.ticks;
  return t;
}

size_t Gani::step_at(int tick) const {
  if (steps.empty()) return 0;
  int total = total_ticks();
  if (tick < 0) tick = 0;
  if (loop && total > 0) {
    tick %= total;
  } else if (tick >= total) {
    return steps.size() - 1;
  }
  size_t i = 0;
  while (i + 1 < steps.size() && tick >= steps[i].ticks) tick -= steps[i++].ticks;
  return i;
}

bool read_gani(std::string_view text, Gani& g) {
  g = Gani{};
  std::vector<Attach> attach;
  bool in_ani = false, in_script = false, in_movie = false;
  GaniStep step;
  int d = 0;
  auto finish = [&]() {
    if (d > 0) g.steps.push_back(step);
    d = 0;
    step = GaniStep{};
  };
  size_t pos = 0;
  while (pos <= text.size()) {
    size_t nl = text.find('\n', pos);
    if (nl == std::string_view::npos) nl = text.size();
    std::string_view line = text.substr(pos, nl - pos);
    pos = nl + 1;
    if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
    auto w = words(line);
    std::string key = w.empty() ? "" : lower(w[0]);
    if (in_script) {
      if (key == "scriptend" && w.size() == 1) in_script = false;
      continue;
    }
    if (in_movie) {
      if (key == "movieend") in_movie = false;
      continue;
    }
    if (!in_ani && key == "script" && w.size() == 1) {
      in_script = true;
      continue;
    }
    if (w.empty()) {
      if (in_ani && d > 0) finish();
      continue;
    }
    if (!in_ani) {
      if (key == "sprite" && w.size() >= 7) {
        GaniSprite s;
        s.id = int_or(w[1], -1);
        s.sheet = w[2];
        s.x = int_or(w[3], 0);
        s.y = int_or(w[4], 0);
        s.w = int_or(w[5], 0);
        s.h = int_or(w[6], 0);
        g.sprites.push_back(s);
      } else if ((key == "attachsprite" || key == "attachsprite2") && w.size() >= 5) {
        attach.push_back({int_or(w[1], -1), int_or(w[2], -1), int_or(w[3], 0), int_or(w[4], 0), key == "attachsprite2"});
      } else if (key == "loop") {
        g.loop = true;
      } else if (key == "continuous") {
        g.continuous = true;
      } else if (key == "singledirection") {
        g.single_direction = true;
      } else if (key == "setbackto" && w.size() > 1) {
        g.set_back_to = w[1];
      } else if (key == "defaulthead" && w.size() > 1) {
        g.default_head = w[1];
      } else if (key == "defaultbody" && w.size() > 1) {
        g.default_body = w[1];
      } else if (key.compare(0, 11, "defaultattr") == 0 && w.size() > 1) {
        int n = int_or(key.substr(11), 0);
        if (n >= 1 && n <= 30) g.default_attr[static_cast<size_t>(n)] = w[1];
      } else if (key == "movie") {
        in_movie = true;
      } else if (key == "ani") {
        in_ani = true;
      }
      continue;
    }
    if (key == "aniend") {
      finish();
      in_ani = false;
      continue;
    }
    if (key == "wait") {
      int n = w.size() > 1 ? int_or(w[1], 0) : 0;
      if (d > 0) step.ticks += n;
      else if (!g.steps.empty()) g.steps.back().ticks += n;
      continue;
    }
    if (key == "playsound") {
      std::string s = w.size() > 1 ? w[1] : "";
      if (d > 0) step.sound = s;
      else if (!g.steps.empty()) g.steps.back().sound = s;
      continue;
    }
    std::vector<GaniPart> parts;
    if (parse_row(line, parts)) {
      if (d < 4) step.dirs[static_cast<size_t>(d)] = parts;
      ++d;
      if (g.single_direction || d == 4) {
        if (g.single_direction)
          for (size_t k = 1; k < 4; ++k) step.dirs[k] = step.dirs[0];
        finish();
      }
    }
  }
  if (d > 0) finish();
  if (!attach.empty())
    for (auto& s : g.steps)
      for (auto& dir : s.dirs) {
        std::vector<GaniPart> out;
        for (const auto& p : dir) put(attach, p.sprite, p.x, p.y, 0, out);
        dir = out;
      }
  return !g.steps.empty();
}

}  // namespace Quattro::Files
