#include "read_ft.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <sstream>

namespace graal3d::render {

namespace {

// Words of one line: spaces and tabs split, "..." keeps spaces, `//` ends it.
std::vector<std::string> words(const std::string& line) {
  std::vector<std::string> out;
  std::string cur;
  bool quoted = false, have = false;
  for (size_t i = 0; i < line.size(); ++i) {
    const char c = line[i];
    if (!quoted && c == '/' && i + 1 < line.size() && line[i + 1] == '/') break;
    if (c == '"') {
      quoted = !quoted;
      have = true;
      continue;
    }
    if (!quoted && (c == ' ' || c == '\t' || c == '\r')) {
      if (have) out.push_back(cur);
      cur.clear();
      have = false;
      continue;
    }
    cur += c;
    have = true;
  }
  if (have) out.push_back(cur);
  return out;
}

float num(const std::string& s) {
  const float v = std::strtof(s.c_str(), nullptr);
  return std::isfinite(v) ? v : 0.0f;
}

// A value or a "min max" range from words[1..].
void range(const std::vector<std::string>& w, float out[2]) {
  out[0] = w.size() > 1 ? num(w[1]) : 0;
  out[1] = w.size() > 2 ? num(w[2]) : out[0];
}

bool termType(const std::string& s, FtTerm::Type& t) {
  static const std::pair<const char*, FtTerm::Type> kTypes[] = {
      {"push", FtTerm::kPush},     {"pop", FtTerm::kPop},       {"branch", FtTerm::kBranch},
      {"move", FtTerm::kMove},     {"leaf", FtTerm::kLeaf},     {"rotate", FtTerm::kRotate},
      {"absrotate", FtTerm::kAbsRotate}, {"resize", FtTerm::kResize}};
  for (const auto& [name, type] : kTypes)
    if (s == name) return t = type, true;
  return false;
}

// A small, fixed generator: the rebuild's own.
struct Rng {
  uint32_t s;
  explicit Rng(uint32_t seed) : s(seed ? seed : 0x9E3779B9u) {}
  uint32_t next() {
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return s;
  }
  float unit() { return float(next() >> 8) / float(1u << 24); }
  float in(const float r[2]) { return r[0] + (r[1] - r[0]) * unit(); }
};

int clampLevels(const FtTree& t, int levels) {
  if (levels <= 0) levels = t.defaultLevels;
  return std::clamp(levels, 1, 15);
}

}  // namespace

bool parseFt(const std::string& text, FtTree& out, std::string& error) {
  FtTree t;
  std::vector<std::vector<std::string>> lines;
  {
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
      if (line.size() > 127) line.resize(127);
      auto w = words(line);
      if (!w.empty()) lines.push_back(std::move(w));
    }
  }
  bool haveStart = false;
  // The block after line i, if the next line is "{": its lines, and i
  // moved past its "}". Nested blocks are skipped whole.
  auto block = [&](size_t& i) {
    std::vector<std::vector<std::string>> b;
    if (i + 1 >= lines.size() || lines[i + 1].size() != 1 || lines[i + 1][0] != "{") return b;
    i += 2;
    int depth = 1;
    for (; i < lines.size(); ++i) {
      const auto& l = lines[i];
      if (l.size() == 1 && l[0] == "{") ++depth;
      else if (l.size() == 1 && l[0] == "}") {
        if (--depth == 0) break;
      } else if (depth == 1)
        b.push_back(l);
    }
    return b;
  };
  for (size_t i = 0; i < lines.size(); ++i) {
    const auto& w = lines[i];
    const std::string& k = w[0];
    if (k == "width" && w.size() >= 3) {
      t.width[0] = num(w[1]);
      t.width[1] = num(w[2]);
    } else if (k == "length" && w.size() >= 2) {
      t.length = num(w[1]);
    } else if (k == "defaultLevels" && w.size() >= 2) {
      t.defaultLevels = std::atoi(w[1].c_str());
    } else if (k == "billboard" && w.size() >= 2) {
      t.billboard = w[1];
    } else if (k == "billboardsize" && w.size() >= 3) {
      t.billboardSize[0] = num(w[1]);
      t.billboardSize[1] = num(w[2]);
    } else if (k == "gramma") {
      for (const auto& r : block(i)) {
        if (r[0].size() != 1 || r.size() < 2) continue;
        FtRule rule;
        if (r.size() >= 3) {
          rule.weight = num(r[1]);
          rule.replacement = r[2];
        } else {
          rule.replacement = r[1];
        }
        if (!(rule.weight > 0)) continue;
        t.rules[r[0][0]].push_back(rule);
        if (!haveStart) {
          t.start = r[0][0];
          haveStart = true;
        }
      }
    } else if (k == "term" && w.size() >= 3 && w[1].size() == 1) {
      FtTerm term;
      if (!termType(w[2], term.type)) {
        block(i);
        continue;
      }
      for (const auto& o : block(i)) {
        const std::string& ok = o[0];
        if (ok == "nobranch") term.noBranch = true;
        else if (ok == "texBranch" && o.size() > 1) term.texBranch = std::clamp(std::atoi(o[1].c_str()), 0, 7);
        else if (ok == "texLeaf" && o.size() > 1) term.texLeaf = std::clamp(std::atoi(o[1].c_str()), 0, 7);
        else if (ok == "coordLeaf" && o.size() > 1) term.coordLeaf = std::atoi(o[1].c_str());
        else if (ok == "size" && o.size() > 1) term.size = std::clamp(num(o[1]), 0.1f, 100.0f);
        else if (ok == "widthRatio" && o.size() > 1) term.widthRatio = num(o[1]);
        else if (ok == "lengthRatio") range(o, term.lengthRatio);
        else if (ok == "yaw") range(o, term.yaw);
        else if (ok == "pitch") range(o, term.pitch);
      }
      t.terms[w[1][0]] = term;
    } else if (k == "texture" && w.size() >= 3) {
      const int slot = std::atoi(w[1].c_str());
      if (slot >= 0 && slot < 8) t.textures[slot] = w[2];
      block(i);  // texture-coordinate rows: not used yet
    } else {
      block(i);  // an unknown line's block is skipped whole
    }
  }
  if (!haveStart) return error = "ft: no gramma rules", false;
  out = std::move(t);
  return true;
}

std::string growFt(const FtTree& tree, uint32_t seed, int levels) {
  Rng rng(seed);
  std::string s(1, tree.start);
  for (int round = clampLevels(tree, levels); round > 0; --round) {
    std::string next;
    bool cut = false;
    for (char c : s) {
      auto r = tree.rules.find(c);
      if (r != tree.rules.end()) {
        float total = 0;
        for (const auto& rule : r->second) total += rule.weight;
        float pick = rng.unit() * total;
        const FtRule* chosen = &r->second.back();
        for (const auto& rule : r->second) {
          if (pick < rule.weight) {
            chosen = &rule;
            break;
          }
          pick -= rule.weight;
        }
        next += chosen->replacement;
      } else if (tree.terms.count(c)) {
        next += c;
      }
      if (next.size() > kFtMaxString) {
        next.resize(kFtMaxString);
        cut = true;
        break;
      }
    }
    s = std::move(next);
    if (cut) break;
  }
  return s;
}

namespace {

struct Turtle {
  V3 pos{0, 0, 0};
  V3 heading{0, 0, 1};
  V3 left{-1, 0, 0};
  float length = 1;
  float w0 = 0.5f, w1 = 0.5f;
};

V3 rotateAbout(const V3& v, const V3& axis, float radians) { return M4::rotation(axis, radians).vector(v); }

constexpr float kDeg = 3.14159265358979f / 180.0f;

void turn(Turtle& t, float yawDeg, float pitchDeg) {
  t.left = normalize(rotateAbout(t.left, t.heading, yawDeg * kDeg));
  t.heading = normalize(rotateAbout(t.heading, t.left, pitchDeg * kDeg));
}

void addTube(Mesh& m, int material, const V3& a, const V3& b, const V3& side, float r0, float r1) {
  constexpr int kSides = 6;
  const V3 h = normalize(b - a);
  const V3 s0 = normalize(side - h * dot(side, h));
  const V3 s1 = cross(h, s0);
  const uint32_t base = uint32_t(m.vertices.size());
  for (int i = 0; i <= kSides; ++i) {
    const float ang = 2 * 3.14159265358979f * float(i) / kSides;
    const V3 n = s0 * std::cos(ang) + s1 * std::sin(ang);
    m.vertices.push_back({a + n * r0, n, float(i) / kSides, 1});
    m.vertices.push_back({b + n * r1, n, float(i) / kSides, 0});
  }
  for (int i = 0; i < kSides; ++i) {
    const uint32_t k = base + uint32_t(i) * 2;
    m.triangles.push_back({{k, k + 2, k + 3}, material});
    m.triangles.push_back({{k, k + 3, k + 1}, material});
  }
}

void addLeaf(Mesh& m, int material, const Turtle& t, float size) {
  const V3 h = t.heading, l = t.left, u = cross(h, l);
  const float s = size * 0.5f;
  for (const V3& across : {l, u}) {
    const V3 n = normalize(cross(h, across));
    const uint32_t base = uint32_t(m.vertices.size());
    m.vertices.push_back({t.pos - across * s, n, 0, 1});
    m.vertices.push_back({t.pos + across * s, n, 1, 1});
    m.vertices.push_back({t.pos + across * s + h * (2 * s), n, 1, 0});
    m.vertices.push_back({t.pos - across * s + h * (2 * s), n, 0, 0});
    // Both sides: leaves are seen from either.
    m.triangles.push_back({{base, base + 1, base + 2}, material});
    m.triangles.push_back({{base, base + 2, base + 3}, material});
    m.triangles.push_back({{base, base + 2, base + 1}, material});
    m.triangles.push_back({{base, base + 3, base + 2}, material});
  }
}

}  // namespace

Shape ftShape(const FtTree& tree, uint32_t seed, int levels) {
  const std::string s = growFt(tree, seed, levels);
  // The drawing walk uses its own stream, after the growing one.
  Rng rng(seed ^ 0xA5A5A5A5u);
  Shape shape;
  for (int i = 0; i < 8; ++i) {
    Material m;
    m.name = "slot" + std::to_string(i);
    m.texture = tree.textures[i];
    shape.materials.push_back(m);
  }
  Mesh mesh;
  mesh.name = "tree";
  Turtle t;
  t.length = tree.length;
  t.w0 = tree.width[0];
  t.w1 = tree.width[1];
  std::vector<Turtle> stack;
  for (char c : s) {
    auto it = tree.terms.find(c);
    if (it == tree.terms.end()) continue;
    const FtTerm& term = it->second;
    switch (term.type) {
      case FtTerm::kPush:
        if (stack.size() < 256) stack.push_back(t);
        break;
      case FtTerm::kPop:
        if (!stack.empty()) {
          t = stack.back();
          stack.pop_back();
        }
        break;
      case FtTerm::kBranch:
      case FtTerm::kMove: {
        const V3 end = t.pos + t.heading * (t.length * term.size);
        if (term.type == FtTerm::kBranch)
          addTube(mesh, term.texBranch, t.pos, end, t.left, t.w0 * 0.5f, t.w1 * 0.5f);
        t.pos = end;
        t.w0 = t.w1;
        t.w1 *= term.widthRatio;
        t.length *= rng.in(term.lengthRatio);
        break;
      }
      case FtTerm::kLeaf:
        turn(t, rng.in(term.yaw), 0);
        addLeaf(mesh, term.texLeaf, t, term.size);
        break;
      case FtTerm::kRotate:
        turn(t, rng.in(term.yaw), rng.in(term.pitch));
        break;
      case FtTerm::kAbsRotate: {
        const float yaw = rng.in(term.yaw) * kDeg, pitch = rng.in(term.pitch) * kDeg;
        t.heading = normalize(V3{std::sin(pitch) * std::sin(yaw), std::sin(pitch) * -std::cos(yaw), std::cos(pitch)});
        V3 l = cross(V3{0, 0, 1}, t.heading);
        t.left = dot(l, l) > 1e-6f ? normalize(l) : V3{-1, 0, 0};
        break;
      }
      case FtTerm::kResize:
        t.w0 *= term.widthRatio;
        t.w1 *= term.widthRatio;
        t.length *= rng.in(term.lengthRatio) * term.size;
        break;
    }
  }
  shape.meshes.push_back(std::move(mesh));
  shape.computeBounds();
  return shape;
}

bool readFt(const std::vector<uint8_t>& bytes, Shape& out, std::string& error) {
  FtTree tree;
  if (!parseFt(std::string(bytes.begin(), bytes.end()), tree, error)) return false;
  out = ftShape(tree, kFtDefaultSeed, 0);
  return true;
}

}  // namespace graal3d::render
