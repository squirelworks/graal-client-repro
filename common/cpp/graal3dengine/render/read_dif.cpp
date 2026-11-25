#include "read_dif.hpp"

#include <cmath>
#include <cstring>

namespace graal3d::render {
namespace {

struct In {
  const uint8_t* p = nullptr;
  size_t n = 0;
  size_t at = 0;
  bool bad = false;
  std::string why;

  bool fail(const std::string& w) {
    if (!bad) why = w;
    bad = true;
    return false;
  }
  bool need(size_t k) {
    if (bad) return false;
    if (n - at < k) return fail("dif: the file ends early");
    return true;
  }
  void skip(size_t k) {
    if (need(k)) at += k;
  }
  uint8_t u8() {
    if (!need(1)) return 0;
    return p[at++];
  }
  uint16_t u16() {
    if (!need(2)) return 0;
    const uint16_t v = uint16_t(p[at] | p[at + 1] << 8);
    at += 2;
    return v;
  }
  int16_t s16() { return int16_t(u16()); }
  uint32_t u32() {
    if (!need(4)) return 0;
    uint32_t v;
    std::memcpy(&v, p + at, 4);
    at += 4;
    return v;
  }
  int32_t s32() { return int32_t(u32()); }
  float f32() {
    const uint32_t b = u32();
    float f;
    std::memcpy(&f, &b, 4);
    return std::isfinite(f) ? f : 0.0f;
  }
  std::string str() {
    const uint8_t len = u8();
    if (!need(len)) return {};
    std::string s(reinterpret_cast<const char*>(p + at), len);
    at += len;
    const size_t z = s.find('\0');
    if (z != std::string::npos) s.resize(z);
    return s;
  }
  size_t count(const char* what) {
    const uint32_t c = u32();
    if (bad) return 0;
    if (c > kDifMaxCount) {
      fail(std::string("dif: bad ") + what + " count");
      return 0;
    }
    return c;
  }
  // A list of fixed-size entries, stepped over.
  void skipList(size_t entryBytes, const char* what) {
    const size_t c = count(what);
    if (c && entryBytes > (n - at) / c) return void(fail("dif: the file ends early"));
    skip(c * entryBytes);
  }
  // Torque's list whose entries are 16-bit when its count's top bit is
  // set and the byte after it is not zero, else `wide` bytes.
  std::vector<int32_t> flexList(const char* what, bool narrowWhenFlagged, size_t wide) {
    uint32_t c = u32();
    bool narrow = false;
    if (c & 0x80000000u) {
      c ^= 0x80000000u;
      const uint8_t param = u8();
      narrow = narrowWhenFlagged ? param > 0 : true;
    } else {
      narrow = wide == 2;
    }
    std::vector<int32_t> v;
    if (bad) return v;
    if (c > kDifMaxCount) return fail(std::string("dif: bad ") + what + " count"), v;
    const size_t each = narrow ? 2 : 4;
    if (c && each > (n - at) / c) return fail("dif: the file ends early"), v;
    v.resize(c);
    for (auto& x : v) x = narrow ? int32_t(s16()) : s32();
    return v;
  }
};

struct Plane {
  int normal;
  float d;
};
struct TexGen {
  float x[4], y[4];
};
struct Surface {
  uint32_t windingStart, windingCount;
  int plane, material, texGen;
};

// Reads the surfaces with the lightmap fields as bytes or as 16-bit
// values; false (and `in` unchanged) when an entry does not fit the lists
// read before it.
bool readSurfaces(In& in, bool wideMaps, size_t windings, size_t planes, size_t materials, size_t texGens,
                  std::vector<Surface>& out) {
  In r = in;
  const size_t c = r.count("surface");
  std::vector<Surface> v;
  v.reserve(std::min<size_t>(c, 65536));
  for (size_t i = 0; i < c && !r.bad; ++i) {
    Surface s;
    s.windingStart = r.u32();
    s.windingCount = r.u8();
    const uint16_t plane = r.u16();
    s.plane = plane & 0x7FFF;
    s.material = r.s16();
    s.texGen = r.s32();
    r.u8();       // flags
    r.u32();      // fan mask
    r.u16();      // lightmap final word
    r.skip(8);    // lightmap texgen x and y
    r.u16();      // light count
    r.u32();      // light state start
    r.skip(wideMaps ? 8 : 4);  // lightmap offset and size
    if (r.bad) break;
    if (s.windingStart >= windings || s.windingStart + s.windingCount > windings || size_t(s.plane) >= planes ||
        s.material < 0 || size_t(s.material) >= materials || s.texGen < 0 || size_t(s.texGen) >= texGens)
      return false;
    v.push_back(s);
  }
  if (r.bad) return false;
  in = r;
  out = std::move(v);
  return true;
}

}  // namespace

bool readDif(const uint8_t* data, size_t size, Shape& out, std::string& error) {
  In in;
  in.p = data;
  in.n = size;
  const uint32_t version = in.u32();
  if (in.bad) return error = "dif: not an interior", false;
  if (version != kDifResourceVersion)
    return error = "dif: resource version " + std::to_string(version) + " is not read (44 is)", false;
  if (in.u8()) {
    // A preview image: a PNG, stepped over to its end chunk.
    static const uint8_t kEnd[8] = {'I', 'E', 'N', 'D', 0xAE, 0x42, 0x60, 0x82};
    const uint8_t* e = nullptr;
    for (size_t i = in.at; i + 8 <= size; ++i)
      if (std::memcmp(data + i, kEnd, 8) == 0) {
        e = data + i + 8;
        break;
      }
    if (!e) return error = "dif: the preview image has no end", false;
    in.at = size_t(e - data);
  }
  const size_t levels = in.count("detail level");
  if (in.bad) return error = in.why, false;
  if (levels == 0) return error = "dif: no detail levels", false;

  // The first (most detailed) Interior.
  const int32_t iv = in.s32();
  if (!in.bad && iv != kDifInteriorVersion)
    return error = "dif: interior version " + std::to_string(iv) + " is not read (0 is)", false;
  in.s32();       // detail level
  in.s32();       // minimum pixels
  in.skip(6 * 4); // bounding box
  in.skip(4 * 4); // bounding sphere
  in.u8();        // alarm state
  in.u32();       // light state entries
  const size_t nn = in.count("normal");
  if (nn && 12 > (size - in.at) / nn) return error = "dif: the file ends early", false;
  std::vector<V3> normals(nn);
  for (auto& v : normals) {
    v.x = in.f32();
    v.y = in.f32();
    v.z = in.f32();
  }
  const size_t np = in.count("plane");
  if (np && 6 > (size - in.at) / np) return error = "dif: the file ends early", false;
  std::vector<Plane> planes(np);
  for (auto& p : planes) {
    p.normal = in.s16();
    p.d = in.f32();
  }
  const size_t npt = in.count("point");
  if (npt && 12 > (size - in.at) / npt) return error = "dif: the file ends early", false;
  std::vector<V3> points(npt);
  for (auto& v : points) {
    v.x = in.f32();
    v.y = in.f32();
    v.z = in.f32();
  }
  in.skipList(1, "point visibility");
  const size_t ntg = in.count("texgen");
  if (ntg && 32 > (size - in.at) / ntg) return error = "dif: the file ends early", false;
  std::vector<TexGen> texGens(ntg);
  for (auto& t : texGens) {
    for (float& f : t.x) f = in.f32();
    for (float& f : t.y) f = in.f32();
  }
  in.skipList(6, "BSP node");
  in.skipList(6, "BSP leaf");
  in.u8();  // material list version
  const size_t nm = in.count("material");
  Shape shape;
  for (size_t i = 0; i < nm && !in.bad; ++i) {
    Material m;
    m.name = in.str();
    m.texture = m.name;
    shape.materials.push_back(m);
  }
  const std::vector<int32_t> windings = in.flexList("winding", true, 4);
  in.skipList(8, "winding index");
  in.skipList(12, "zone");
  in.flexList("zone surface", false, 2);
  in.flexList("zone portal", false, 2);
  in.skipList(12, "portal");
  if (in.bad) return error = in.why, false;

  std::vector<Surface> surfaces;
  if (!readSurfaces(in, false, windings.size(), planes.size(), shape.materials.size(), texGens.size(), surfaces) &&
      !readSurfaces(in, true, windings.size(), planes.size(), shape.materials.size(), texGens.size(), surfaces))
    return error = in.bad ? in.why : "dif: the surfaces do not fit the interior", false;

  // Torque's marker materials are never drawn.
  auto hidden = [](const std::string& name) {
    std::string l;
    for (char c : name) l += char(c >= 'A' && c <= 'Z' ? c - 'A' + 'a' : c);
    return l == "null" || l == "origin" || l == "trigger" || l == "forcefield" || l == "emitter";
  };

  // One mesh per material; each surface's strip becomes triangles with its
  // own vertices (texture coordinates are per surface).
  std::vector<Mesh> perMat(shape.materials.size());
  for (const Surface& s : surfaces) {
    if (hidden(shape.materials[size_t(s.material)].name)) continue;
    Mesh& m = perMat[size_t(s.material)];
    const TexGen& tg = texGens[size_t(s.texGen)];
    const uint32_t base = uint32_t(m.vertices.size());
    bool ok = true;
    for (uint32_t k = 0; k < s.windingCount; ++k) {
      const int32_t pi = windings[s.windingStart + k];
      if (pi < 0 || size_t(pi) >= points.size()) {
        ok = false;
        break;
      }
    }
    if (!ok || s.windingCount < 3) continue;
    for (uint32_t k = 0; k < s.windingCount; ++k) {
      const V3& p = points[size_t(windings[s.windingStart + k])];
      Vertex v;
      v.position = p;
      v.u = tg.x[0] * p.x + tg.x[1] * p.y + tg.x[2] * p.z + tg.x[3];
      v.v = tg.y[0] * p.x + tg.y[1] * p.y + tg.y[2] * p.z + tg.y[3];
      m.vertices.push_back(v);
    }
    for (uint32_t k = 0; k + 2 < s.windingCount; ++k) {
      Triangle t;
      t.material = s.material;
      if (k & 1) {
        t.v[0] = base + k + 1;
        t.v[1] = base + k;
      } else {
        t.v[0] = base + k;
        t.v[1] = base + k + 1;
      }
      t.v[2] = base + k + 2;
      m.triangles.push_back(t);
    }
  }
  for (size_t i = 0; i < perMat.size(); ++i) {
    if (perMat[i].triangles.empty()) continue;
    perMat[i].name = shape.materials[i].name;
    computeNormals(perMat[i]);
    shape.meshes.push_back(std::move(perMat[i]));
  }
  shape.computeBounds();
  out = std::move(shape);
  return true;
}

bool readDif(const std::vector<uint8_t>& bytes, Shape& out, std::string& error) {
  return readDif(bytes.data(), bytes.size(), out, error);
}

}  // namespace graal3d::render
