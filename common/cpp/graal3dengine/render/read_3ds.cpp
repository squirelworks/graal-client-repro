#include "read_3ds.hpp"

#include <cstring>
#include <map>

namespace graal3d::render {
namespace {

enum : uint16_t {
  kMain = 0x4D4D,
  kEditor = 0x3D3D,
  kObject = 0x4000,
  kTriMesh = 0x4100,
  kVertices = 0x4110,
  kFaces = 0x4120,
  kFaceMaterial = 0x4130,
  kTexCoords = 0x4140,
  kMaterial = 0xAFFF,
  kMaterialName = 0xA000,
  kDiffuse = 0xA020,
  kTextureMap = 0xA200,
  kMapFile = 0xA300,
  kColorF = 0x0010,
  kColorB = 0x0011,
  kColorBGamma = 0x0012,
  kColorFGamma = 0x0013,
};

struct Cursor {
  const uint8_t* p;
  size_t n;
  size_t at = 0;
  bool bad = false;

  bool need(size_t k) {
    if (bad || n - at < k) {
      bad = true;
      return false;
    }
    return true;
  }
  uint16_t u16() {
    if (!need(2)) return 0;
    const uint16_t v = uint16_t(p[at] | (p[at + 1] << 8));
    at += 2;
    return v;
  }
  uint32_t u32() {
    if (!need(4)) return 0;
    const uint32_t v = uint32_t(p[at]) | uint32_t(p[at + 1]) << 8 | uint32_t(p[at + 2]) << 16 | uint32_t(p[at + 3]) << 24;
    at += 4;
    return v;
  }
  float f32() {
    const uint32_t b = u32();
    float f;
    std::memcpy(&f, &b, 4);
    return f;
  }
  uint8_t u8() {
    if (!need(1)) return 0;
    return p[at++];
  }
  std::string cstr() {
    std::string s;
    while (!bad) {
      if (!need(1)) break;
      const char c = char(p[at++]);
      if (!c) return s;
      if (s.size() >= 1024) {
        bad = true;
        break;
      }
      s += c;
    }
    return s;
  }
};

struct Chunk {
  uint16_t id = 0;
  size_t begin = 0, end = 0;  // the payload, after the 6-byte header
};

// Reads the header of the chunk at c.at, inside [c.at, limit).
bool nextChunk(Cursor& c, size_t limit, Chunk& ch) {
  if (limit - c.at < 6) return false;
  const size_t start = c.at;
  ch.id = c.u16();
  const uint32_t len = c.u32();
  if (c.bad || len < 6 || len > limit - start) {
    c.bad = true;
    return false;
  }
  ch.begin = start + 6;
  ch.end = start + len;
  return true;
}

struct Reader {
  Cursor c;
  Shape& shape;
  std::string error;
  std::map<std::string, int> materialIndex;
  // Face groups name materials that may be defined later in the file.
  struct PendingGroup {
    size_t mesh;
    bool collision;
    std::string material;
    std::vector<uint16_t> faces;
  };
  std::vector<PendingGroup> groups;
  size_t objects = 0;

  Reader(const uint8_t* p, size_t n, Shape& s) : c{p, n}, shape(s) {}

  bool fail(const std::string& why) {
    if (error.empty()) error = why;
    return false;
  }

  bool readColor(size_t end, float out[3]) {
    Chunk ch;
    bool got = false;
    while (c.at < end && nextChunk(c, end, ch)) {
      // Prefer the plain colour; a gamma-corrected one only when alone.
      if (ch.id == kColorF || (ch.id == kColorFGamma && !got)) {
        for (int i = 0; i < 3; ++i) out[i] = c.f32();
        got = true;
      } else if (ch.id == kColorB || (ch.id == kColorBGamma && !got)) {
        for (int i = 0; i < 3; ++i) out[i] = c.u8() / 255.0f;
        got = true;
      }
      c.at = ch.end;
    }
    return !c.bad;
  }

  bool readMaterial(size_t end) {
    Material m;
    Chunk ch;
    while (c.at < end && nextChunk(c, end, ch)) {
      if (ch.id == kMaterialName) {
        m.name = c.cstr();
      } else if (ch.id == kDiffuse) {
        if (!readColor(ch.end, m.color)) return false;
      } else if (ch.id == kTextureMap) {
        Chunk sub;
        while (c.at < ch.end && nextChunk(c, ch.end, sub)) {
          if (sub.id == kMapFile) m.texture = c.cstr();
          c.at = sub.end;
        }
      }
      if (c.bad) return fail("3ds: material chunk runs past its end");
      c.at = ch.end;
    }
    materialIndex[m.name] = int(shape.materials.size());
    shape.materials.push_back(m);
    return !c.bad;
  }

  bool readTriMesh(size_t end, Mesh& mesh, bool collision, size_t meshIndex) {
    Chunk ch;
    size_t uvCount = 0;
    std::vector<std::pair<float, float>> uvs;
    while (c.at < end && nextChunk(c, end, ch)) {
      if (ch.id == kVertices) {
        const uint16_t n = c.u16();
        if (!c.need(size_t(n) * 12)) return fail("3ds: vertex list runs past its chunk");
        mesh.vertices.resize(n);
        for (auto& v : mesh.vertices) {
          v.position.x = c.f32();
          v.position.y = c.f32();
          v.position.z = c.f32();
        }
      } else if (ch.id == kTexCoords) {
        const uint16_t n = c.u16();
        if (!c.need(size_t(n) * 8)) return fail("3ds: texture coordinates run past their chunk");
        uvCount = n;
        uvs.resize(n);
        for (auto& uv : uvs) {
          uv.first = c.f32();
          uv.second = c.f32();
        }
      } else if (ch.id == kFaces) {
        const uint16_t n = c.u16();
        if (!c.need(size_t(n) * 8)) return fail("3ds: face list runs past its chunk");
        mesh.triangles.resize(n);
        for (auto& t : mesh.triangles) {
          for (auto& i : t.v) i = c.u16();
          c.u16();  // edge flags
        }
        Chunk sub;
        while (c.at < ch.end && nextChunk(c, ch.end, sub)) {
          if (sub.id == kFaceMaterial) {
            PendingGroup g;
            g.mesh = meshIndex;
            g.collision = collision;
            g.material = c.cstr();
            const uint16_t k = c.u16();
            if (!c.need(size_t(k) * 2)) return fail("3ds: face group runs past its chunk");
            g.faces.resize(k);
            for (auto& f : g.faces) f = c.u16();
            groups.push_back(std::move(g));
          }
          c.at = sub.end;
        }
      }
      if (c.bad) return fail("3ds: mesh chunk runs past its end");
      c.at = ch.end;
    }
    for (size_t i = 0; i < mesh.vertices.size() && i < uvCount; ++i) {
      mesh.vertices[i].u = uvs[i].first;
      mesh.vertices[i].v = 1.0f - uvs[i].second;  // .3ds counts v from the bottom of the image
    }
    for (const auto& t : mesh.triangles)
      for (uint32_t i : t.v)
        if (i >= mesh.vertices.size()) return fail("3ds: a face names a vertex the mesh does not have");
    computeNormals(mesh);
    return true;
  }

  bool readObject(size_t end) {
    if (++objects > k3dsMaxObjects) return fail("3ds: too many objects");
    const std::string name = c.cstr();
    if (c.bad) return fail("3ds: object name runs past its chunk");
    const bool collision = name.size() >= 4 && (name.compare(0, 4, "Col-") == 0 || name.compare(0, 4, "col-") == 0);
    Chunk ch;
    while (c.at < end && nextChunk(c, end, ch)) {
      if (ch.id == kTriMesh) {
        auto& list = collision ? shape.collision : shape.meshes;
        list.emplace_back();
        list.back().name = name;
        Mesh mesh;
        mesh.name = name;
        if (!readTriMesh(ch.end, mesh, collision, list.size() - 1)) return false;
        list.back() = std::move(mesh);
      }
      c.at = ch.end;
    }
    return !c.bad;
  }

  bool readEditor(size_t end) {
    Chunk ch;
    while (c.at < end && nextChunk(c, end, ch)) {
      if (ch.id == kMaterial) {
        if (!readMaterial(ch.end)) return false;
      } else if (ch.id == kObject) {
        if (!readObject(ch.end)) return false;
      }
      c.at = ch.end;
    }
    return !c.bad;
  }

  bool run() {
    Chunk main;
    if (!nextChunk(c, c.n, main) || main.id != kMain) return fail("3ds: not a 3D Studio file");
    Chunk ch;
    while (c.at < main.end && nextChunk(c, main.end, ch)) {
      if (ch.id == kEditor && !readEditor(ch.end)) return false;
      c.at = ch.end;
    }
    if (c.bad) return fail("3ds: a chunk runs past the end of the file");
    for (const PendingGroup& g : groups) {
      auto it = materialIndex.find(g.material);
      const int m = it == materialIndex.end() ? -1 : it->second;
      Mesh& mesh = g.collision ? shape.collision[g.mesh] : shape.meshes[g.mesh];
      for (uint16_t f : g.faces)
        if (f < mesh.triangles.size()) mesh.triangles[f].material = m;
    }
    // The real 5.12 draws a Col- hull like any mesh (lab T3D-032): kept as
    // the collision hull and drawn too.
    for (const Mesh& m : shape.collision) shape.meshes.push_back(m);
    shape.computeBounds();
    return true;
  }
};

}  // namespace

bool read3ds(const uint8_t* data, size_t size, Shape& out, std::string& error) {
  Shape shape;
  Reader r(data, size, shape);
  if (!r.run()) {
    error = r.error.empty() ? "3ds: unreadable" : r.error;
    return false;
  }
  out = std::move(shape);
  return true;
}

bool read3ds(const std::vector<uint8_t>& bytes, Shape& out, std::string& error) {
  return read3ds(bytes.data(), bytes.size(), out, error);
}

}  // namespace graal3d::render
