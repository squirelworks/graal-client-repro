#include "fuzzcases.hpp"

#include "../render/read_3ds.hpp"
#include "../render/read_dif.hpp"
#include "../render/read_dts.hpp"

#include <algorithm>
#include <cstring>
#include <map>

namespace graal3d::tools {
namespace {

uint32_t rd32(const std::vector<uint8_t>& b, size_t at) {
  uint32_t v = 0;
  if (at + 4 <= b.size()) std::memcpy(&v, b.data() + at, 4);
  return v;
}
void wr32(std::vector<uint8_t>& b, size_t at, uint32_t v) {
  if (at + 4 <= b.size()) std::memcpy(b.data() + at, &v, 4);
}
uint16_t rd16(const std::vector<uint8_t>& b, size_t at) {
  uint16_t v = 0;
  if (at + 2 <= b.size()) std::memcpy(&v, b.data() + at, 2);
  return v;
}
void wr16(std::vector<uint8_t>& b, size_t at, uint16_t v) {
  if (at + 2 <= b.size()) std::memcpy(b.data() + at, &v, 2);
}
std::string hex(uint32_t v) {
  char s[16];
  std::snprintf(s, sizeof s, "0x%X", v);
  return s;
}

struct Out {
  std::vector<FuzzCase>& cases;
  void add(std::string what, std::vector<uint8_t> bytes) { cases.push_back({std::move(what), std::move(bytes)}); }
};

// ---- .3ds ---------------------------------------------------------------

struct Chunk3 {
  uint16_t id;
  size_t header;                // offset of the 6-byte header
  size_t payload, end;          // payload start, chunk end
  std::vector<size_t> parents;  // header offsets of the enclosing chunks
};

bool isContainer(uint16_t id) {
  switch (id) {
    case 0x4D4D: case 0x3D3D: case 0x4000: case 0x4100: case 0xAFFF: case 0xA200: case 0xA020: return true;
    default: return false;
  }
}

void walk3ds(const std::vector<uint8_t>& b, size_t at, size_t end, std::vector<size_t>& parents, std::vector<Chunk3>& out) {
  while (end - at >= 6 && out.size() < 100000) {
    const uint16_t id = rd16(b, at);
    const uint32_t len = rd32(b, at + 2);
    if (len < 6 || len > end - at) return;
    Chunk3 c{id, at, at + 6, at + len, parents};
    out.push_back(c);
    if (isContainer(id)) {
      size_t inner = c.payload;
      if (id == 0x4000)  // the object's name comes first
        while (inner < c.end && b[inner] != 0) ++inner, (void)0;
      if (id == 0x4000) ++inner;
      parents.push_back(at);
      walk3ds(b, inner, c.end, parents, out);
      parents.pop_back();
    } else if (id == 0x4120) {  // faces, then the face-material chunks
      const size_t n = rd16(b, c.payload);
      const size_t sub = c.payload + 2 + n * 8;
      if (sub <= c.end) {
        parents.push_back(at);
        walk3ds(b, sub, c.end, parents, out);
        parents.pop_back();
      }
    }
    at = c.end;
  }
}

// Replaces [from, to) with `with`, fixing the length of every chunk
// around it.
std::vector<uint8_t> splice(const std::vector<uint8_t>& b, const Chunk3& c, size_t from, size_t to,
                            const std::vector<uint8_t>& with) {
  std::vector<uint8_t> r(b.begin(), b.begin() + std::ptrdiff_t(from));
  r.insert(r.end(), with.begin(), with.end());
  r.insert(r.end(), b.begin() + std::ptrdiff_t(to), b.end());
  const int64_t delta = int64_t(with.size()) - int64_t(to - from);
  std::vector<size_t> heads = c.parents;
  heads.push_back(c.header);
  for (size_t h : heads) wr32(r, h + 2, uint32_t(int64_t(rd32(b, h + 2)) + delta));
  return r;
}

std::string idName(uint16_t id) {
  static const std::map<uint16_t, const char*> names = {
      {0x4D4D, "main"},          {0x3D3D, "editor"},   {0x4000, "object"},        {0x4100, "mesh"},
      {0x4110, "vertices"},      {0x4120, "faces"},    {0x4130, "face-material"}, {0x4140, "texcoords"},
      {0xAFFF, "material"},      {0xA000, "mat-name"}, {0xA020, "diffuse"},       {0xA200, "texture-map"},
      {0xA300, "map-file"},      {0x0010, "colour-f"}, {0x0011, "colour-b"}};
  auto it = names.find(id);
  return it == names.end() ? hex(id) : it->second;
}

void cases3ds(const std::vector<uint8_t>& b, int perId, Out out) {
  std::vector<Chunk3> chunks;
  std::vector<size_t> parents;
  walk3ds(b, 0, b.size(), parents, chunks);
  std::map<uint16_t, int> seen;
  for (const Chunk3& c : chunks) {
    if (seen[c.id]++ >= perId) continue;
    const std::string at = idName(c.id) + "@" + std::to_string(c.header) + ": ";
    const uint32_t len = rd32(b, c.header + 2);
    for (uint32_t v : {0u, 5u, len - 1, len + 1, 0x7FFFFFFFu, 0xFFFFFFFFu, uint32_t(b.size() - c.header)}) {
      if (v == len) continue;
      std::vector<uint8_t> m = b;
      wr32(m, c.header + 2, v);
      out.add(at + "length " + std::to_string(len) + " -> " + std::to_string(v), m);
    }
    {
      std::vector<uint8_t> m = b;
      wr16(m, c.header, 0xFFFF);
      out.add(at + "id -> 0xFFFF (unknown chunk)", m);
    }
    out.add(at + "file cut at the chunk", std::vector<uint8_t>(b.begin(), b.begin() + std::ptrdiff_t(c.header)));
    if (c.end - c.payload > 2)
      out.add(at + "file cut mid-payload",
              std::vector<uint8_t>(b.begin(), b.begin() + std::ptrdiff_t(c.payload + (c.end - c.payload) / 2)));

    const uint16_t count = rd16(b, c.payload);
    auto setCount = [&](uint16_t v, const char* what) {
      std::vector<uint8_t> m = b;
      wr16(m, c.payload, v);
      out.add(at + "count " + std::to_string(count) + " -> " + std::to_string(v) + what, m);
    };
    auto setF32 = [&](size_t off, float f, const std::string& what) {
      if (off + 4 > c.end) return;
      std::vector<uint8_t> m = b;
      std::memcpy(m.data() + off, &f, 4);
      out.add(at + what, m);
    };
    if (c.id == 0x4110 || c.id == 0x4120 || c.id == 0x4140) {
      setCount(0, "");
      setCount(uint16_t(count + 1), " (one more than present)");
      setCount(0xFFFF, "");
    }
    if (c.id == 0x4110) {
      setF32(c.payload + 2, std::nanf(""), "first vertex x = NaN");
      setF32(c.payload + 2, 1e30f, "first vertex x = 1e30");
    }
    if (c.id == 0x4140) {
      setF32(c.payload + 2, std::nanf(""), "first u = NaN");
      setF32(c.payload + 2, 1e6f, "first u = 1e6 (far repeat)");
      setF32(c.payload + 2, -3.5f, "first u = -3.5 (negative repeat)");
    }
    if (c.id == 0x4120 && count > 0 && c.payload + 10 <= c.end) {
      for (uint16_t v : {uint16_t(0xFFFF), uint16_t(60000)}) {
        std::vector<uint8_t> m = b;
        wr16(m, c.payload + 2, v);
        out.add(at + "first face index -> " + std::to_string(v), m);
      }
      std::vector<uint8_t> m = b;
      wr16(m, c.payload + 4, rd16(b, c.payload + 2));
      wr16(m, c.payload + 6, rd16(b, c.payload + 2));
      out.add(at + "first face degenerate (three equal indices)", m);
    }
    // Strings: the material name, the face group's material, the map file.
    if (c.id == 0xA000 || c.id == 0xA300 || c.id == 0x4130) {
      size_t z = c.payload;
      while (z < c.end && b[z] != 0) ++z;
      if (z >= c.end) continue;
      const std::string name(b.begin() + std::ptrdiff_t(c.payload), b.begin() + std::ptrdiff_t(z));
      auto rename = [&](const std::string& to, const std::string& what) {
        std::vector<uint8_t> w(to.begin(), to.end());
        w.push_back(0);
        out.add(at + what + " (\"" + name + "\" -> \"" + (to.size() > 40 ? to.substr(0, 40) + "..." : to) + "\")",
                splice(b, c, c.payload, z + 1, w));
      };
      std::string upper = name;
      for (char& ch : upper) ch = char(std::toupper(static_cast<unsigned char>(ch)));
      rename(upper, "upper case");
      rename("", "empty name");
      rename(std::string(300, 'x'), "300-character name");
      {
        std::vector<uint8_t> m = b;
        m[z] = 'X';
        out.add(at + "terminating NUL replaced", m);
      }
      if (c.id == 0xA300) {
        const size_t dot = name.find_last_of('.');
        const std::string stem = dot == std::string::npos ? name : name.substr(0, dot);
        for (const char* ext : {"", ".jpg", ".jpeg", ".bmp", ".gif", ".tga", ".dds", ".PNG", ".png.png", "."})
          rename(stem + ext, std::string("extension \"") + ext + "\"");
        rename("sub/" + name, "with a folder (/)");
        rename("sub\\" + name, "with a folder (\\)");
        rename("../" + name, "with a parent folder");
        rename("nosuchtexture.png", "names a texture the server lacks");
        rename("my tex.png", "with a space");
      }
      if (c.id == 0x4130) rename("nosuchmaterial", "names a material that is not defined");
    }
  }
}

// ---- .dts ---------------------------------------------------------------

void casesDts(const std::vector<uint8_t>& b, Out out) {
  if (b.size() < 16) return;
  const uint32_t word = rd32(b, 0);
  const int version = int(word & 0xFF);
  for (int v : {0, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 255}) {
    if (v == version) continue;
    std::vector<uint8_t> m = b;
    wr32(m, 0, (word & ~0xFFu) | uint32_t(v));
    out.add("version " + std::to_string(version) + " -> " + std::to_string(v), m);
  }
  {
    std::vector<uint8_t> m = b;
    wr32(m, 0, (word & 0xFFFFu) | (0xFFFFu << 16));
    out.add("exporter version -> 0xFFFF", m);
  }
  const uint32_t words = rd32(b, 4), start16 = rd32(b, 8), start8 = rd32(b, 12);
  auto setHeader = [&](size_t off, uint32_t v, const std::string& what) {
    std::vector<uint8_t> m = b;
    wr32(m, off, v);
    out.add(what + " -> " + std::to_string(v), m);
  };
  setHeader(4, words + 1, "block words");
  setHeader(4, words - 1, "block words");
  setHeader(4, 0x3FFFFFFF, "block words");
  setHeader(8, start8 + 1, "16-bit stream start");
  setHeader(12, words + 1, "8-bit stream start");
  setHeader(12, start16 - 1, "8-bit stream start");
  // The shape header's counts, at the start of the 32-bit stream.
  const int counts = version > 21 ? (version > 23 ? 17 : version == 23 ? 16 : 17) : 13;
  for (int i = 0; i < counts; ++i)
    for (uint32_t v : {0xFFFFFFFFu, 0x7FFFFFFFu, 0u}) {
      const size_t off = 16 + size_t(i) * 4;
      if (rd32(b, off) == v) continue;
      setHeader(off, v, "shape header count " + std::to_string(i));
    }
  const size_t guard = 16 + size_t(counts + 2) * 4;
  setHeader(guard, rd32(b, guard) ^ 1, "first guard (32-bit stream)");
  auto cut = [&](size_t at, const char* what) {
    if (at < b.size()) out.add(what, std::vector<uint8_t>(b.begin(), b.begin() + std::ptrdiff_t(at)));
  };
  cut(16 + size_t(words) * 2, "file cut inside the block");
  cut(16 + size_t(words) * 4, "file cut after the block");
}

// ---- .dif ---------------------------------------------------------------

void casesDif(const std::vector<uint8_t>& b, Out out) {
  if (b.size() < 13) return;
  auto set32 = [&](size_t off, uint32_t v, const std::string& what) {
    std::vector<uint8_t> m = b;
    wr32(m, off, v);
    out.add(what + " -> " + std::to_string(v), m);
  };
  for (uint32_t v : {0u, 41u, 43u, 45u, 0xFFFFFFFFu}) set32(0, v, "InteriorResource version");
  {
    std::vector<uint8_t> m = b;
    m[4] = m[4] ? 0 : 1;
    out.add(std::string("preview flag -> ") + (m[4] ? "1 (claims a preview image)" : "0"), m);
  }
  if (b[4] == 0) {
    for (uint32_t v : {0u, 2u, 0x7FFFFFFFu}) set32(5, v, "detail level count");
    for (uint32_t v : {1u, 2u, 14u, 0xFFFFFFFFu}) set32(9, v, "Interior version");
  }
  for (size_t cut : {b.size() / 4, b.size() / 2, b.size() - 1})
    out.add("file cut at " + std::to_string(cut) + " of " + std::to_string(b.size()),
            std::vector<uint8_t>(b.begin(), b.begin() + std::ptrdiff_t(cut)));
}

}  // namespace

std::vector<FuzzCase> makeFuzzCases(const std::string& format, const std::vector<uint8_t>& seedFile, int randomCases,
                                    uint32_t seed, int perChunkId) {
  std::vector<FuzzCase> cases;
  Out out{cases};
  if (format == "3ds") cases3ds(seedFile, perChunkId, out);
  else if (format == "dts") casesDts(seedFile, out);
  else if (format == "dif") casesDif(seedFile, out);
  uint32_t s = seed ? seed : 1;
  auto next = [&] {
    s ^= s << 13;
    s ^= s >> 17;
    s ^= s << 5;
    return s;
  };
  for (int i = 0; i < randomCases && !seedFile.empty(); ++i) {
    std::vector<uint8_t> m = seedFile;
    const int k = 1 + int(next() % 6);
    std::string what = "random:";
    for (int j = 0; j < k; ++j) {
      const size_t at = next() % m.size();
      const uint8_t v = uint8_t(next());
      what += " @" + std::to_string(at) + "=" + hex(v);
      m[at] = v;
    }
    out.add(what, m);
  }
  // A change that happens to leave the file as it was is no case.
  cases.erase(std::remove_if(cases.begin(), cases.end(), [&](const FuzzCase& c) { return c.bytes == seedFile; }),
              cases.end());
  return cases;
}

std::string readerVerdict(const std::string& format, const std::vector<uint8_t>& bytes) {
  render::Shape s;
  std::string error;
  const bool ok = format == "dts"   ? render::readDts(bytes, s, error)
                  : format == "dif" ? render::readDif(bytes, s, error)
                                    : render::read3ds(bytes, s, error);
  if (!ok) return "refused: " + error;
  size_t tris = 0;
  for (const auto& m : s.meshes) tris += m.triangles.size();
  return "ok meshes " + std::to_string(s.meshes.size()) + " triangles " + std::to_string(tris) + " materials " +
         std::to_string(s.materials.size());
}

}  // namespace graal3d::tools
