#include "read_dts.hpp"

#include <cmath>
#include <cstring>

namespace graal3d::render {
namespace {

struct Bytes {
  const uint8_t* p;
  size_t n;
};

// The three streams of the shape block, each a window into the file.
struct Alloc {
  const uint8_t* p = nullptr;
  size_t at32 = 0, end32 = 0, at16 = 0, end16 = 0, at8 = 0, end8 = 0;
  uint32_t guard = 0;
  bool bad = false;
  std::string why;

  void fail(const std::string& w) {
    if (!bad) why = w;
    bad = true;
  }
  bool need32(size_t words) {
    if (bad || words > (end32 - at32) / 4) return fail("dts: the 32-bit stream runs out"), false;
    return true;
  }
  int32_t s32() {
    if (!need32(1)) return 0;
    int32_t v;
    std::memcpy(&v, p + at32, 4);
    at32 += 4;
    return v;
  }
  float f32() {
    if (!need32(1)) return 0;
    float v;
    std::memcpy(&v, p + at32, 4);
    at32 += 4;
    return std::isfinite(v) ? v : 0.0f;
  }
  void skip32(size_t words) {
    if (need32(words)) at32 += words * 4;
  }
  int16_t s16() {
    if (bad || end16 - at16 < 2) return fail("dts: the 16-bit stream runs out"), 0;
    int16_t v;
    std::memcpy(&v, p + at16, 2);
    at16 += 2;
    return v;
  }
  void skip16(size_t n) {
    if (bad || n > (end16 - at16) / 2) return fail("dts: the 16-bit stream runs out");
    at16 += n * 2;
  }
  uint8_t u8() {
    if (bad || at8 >= end8) return fail("dts: the 8-bit stream runs out"), 0;
    return p[at8++];
  }
  void skip8(size_t n) {
    if (bad || n > end8 - at8) return fail("dts: the 8-bit stream runs out");
    at8 += n;
  }
  void checkGuard() {
    if (bad) return;
    const uint32_t a = uint32_t(s32());
    const uint32_t b = uint16_t(s16());
    const uint32_t c = u8();
    if (bad) return;
    if (a != guard || b != (guard & 0xFFFF) || c != (guard & 0xFF))
      fail("dts: guard " + std::to_string(guard) + " does not match");
    ++guard;
  }
  // A count from the file, refused when negative or past the limit.
  size_t count(int32_t v, const char* what) {
    if (v < 0 || size_t(v) > kDtsMaxCount) {
      fail(std::string("dts: bad ") + what + " count");
      return 0;
    }
    return size_t(v);
  }
  V3 point() {
    V3 v;
    v.x = f32();
    v.y = f32();
    v.z = f32();
    return v;
  }
};

struct Quat {
  float x = 0, y = 0, z = 0, w = 1;
};

// Torque's 16-bit quaternion, as a standard unit quaternion: Torque keeps
// the conjugate of the usual form.
Quat quat16(Alloc& a) {
  Quat q;
  q.x = a.s16();
  q.y = a.s16();
  q.z = a.s16();
  q.w = a.s16();
  const float len = std::sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
  if (!(len > 0)) return Quat();
  q.x = -q.x / len;
  q.y = -q.y / len;
  q.z = -q.z / len;
  q.w = q.w / len;
  return q;
}

M4 quatMatrix(const Quat& q, const V3& t) {
  M4 m = M4::identity();
  const float x = q.x, y = q.y, z = q.z, w = q.w;
  m.m[0][0] = 1 - 2 * (y * y + z * z);
  m.m[0][1] = 2 * (x * y - z * w);
  m.m[0][2] = 2 * (x * z + y * w);
  m.m[1][0] = 2 * (x * y + z * w);
  m.m[1][1] = 1 - 2 * (x * x + z * z);
  m.m[1][2] = 2 * (y * z - x * w);
  m.m[2][0] = 2 * (x * z - y * w);
  m.m[2][1] = 2 * (y * z + x * w);
  m.m[2][2] = 1 - 2 * (x * x + y * y);
  m.m[0][3] = t.x;
  m.m[1][3] = t.y;
  m.m[2][3] = t.z;
  return m;
}

enum MeshType { kStandard = 0, kSkin = 1, kDecal = 2, kSorted = 3, kNull = 4 };

enum : uint32_t {
  kPrimStrip = 1u << 30,
  kPrimFan = 2u << 30,
  kPrimTypeMask = 3u << 30,
  kPrimNoMaterial = 1u << 28,
  kPrimMaterialMask = ~(kPrimTypeMask | (1u << 29) | kPrimNoMaterial),
};

struct RawMesh {
  bool present = false;
  int type = kNull;
  std::vector<V3> verts;
  std::vector<std::pair<float, float>> tverts;
  struct Prim {
    uint32_t start, count, mat;
  };
  std::vector<Prim> prims;
  std::vector<int32_t> indices;
};

struct Header {
  size_t nodes, objects, decals, subShapes, ifls, rots, trans, uscales, ascales, arbscales, groundFrames,
      objectStates, decalStates, triggers, details, meshes, names;
};

bool readMesh(Alloc& a, int type, std::vector<RawMesh>& meshes, RawMesh& m) {
  m.present = true;
  m.type = type;
  a.checkGuard();
  a.s32();  // frames
  a.s32();  // material frames
  const int32_t parent = a.s32();
  a.skip32(6 + 3 + 1);  // bounds, centre, radius
  if (parent >= 0 && size_t(parent) >= meshes.size()) return a.fail("dts: a mesh names a parent that is not before it"), false;
  const RawMesh* p = parent >= 0 ? &meshes[size_t(parent)] : nullptr;
  if (p && !p->present) return a.fail("dts: a mesh's parent is a null mesh"), false;

  const size_t nv = a.count(a.s32(), "vertex");
  if (p) {
    m.verts = p->verts;
  } else {
    if (!a.need32(nv * 3)) return false;
    m.verts.resize(nv);
    for (auto& v : m.verts) v = a.point();
  }
  const size_t nt = a.count(a.s32(), "texture coordinate");
  if (p) {
    m.tverts = p->tverts;
  } else {
    if (!a.need32(nt * 2)) return false;
    m.tverts.resize(nt);
    for (auto& t : m.tverts) {
      t.first = a.f32();
      t.second = a.f32();
    }
  }
  if (!p) {
    a.skip32(nv * 3);  // normals
    a.skip8(nv);       // encoded normals (versions above 21)
  }
  const size_t np = a.count(a.s32(), "primitive");
  std::vector<int16_t> se(np * 2);
  for (auto& s : se) s = a.s16();
  m.prims.resize(np);
  for (size_t i = 0; i < np; ++i) {
    m.prims[i].start = uint16_t(se[i * 2]);
    m.prims[i].count = uint16_t(se[i * 2 + 1]);
    m.prims[i].mat = uint32_t(a.s32());
  }
  const size_t ni = a.count(a.s32(), "index");
  m.indices.resize(ni);
  for (auto& i : m.indices) i = uint16_t(a.s16());
  const size_t nm = a.count(a.s32(), "merge index");
  a.skip16(nm);
  a.s32();  // vertices per frame
  a.s32();  // flags
  a.checkGuard();

  if (type == kSkin) {
    const size_t niv = a.count(a.s32(), "skin vertex");
    if (p) {
      m.verts = p->verts;
    } else {
      if (!a.need32(niv * 3)) return false;
      m.verts.resize(niv);
      for (auto& v : m.verts) v = a.point();
      a.skip32(niv * 3);  // normals
      a.skip8(niv);       // encoded normals
    }
    const size_t nx = a.count(a.s32(), "skin transform");
    if (!p) a.skip32(nx * 16);
    const size_t nw = a.count(a.s32(), "skin weight");
    if (!p) a.skip32(nw * 3);  // vertex, bone, weight
    const size_t nn = a.count(a.s32(), "skin node");
    if (!p) a.skip32(nn);
    a.checkGuard();
  }
  return !a.bad;
}

// Appends the triangles of `raw` to `out`, placed by `place`.
void buildMesh(const RawMesh& raw, const M4& place, size_t numMaterials, Mesh& out) {
  out.vertices.resize(raw.verts.size());
  for (size_t i = 0; i < raw.verts.size(); ++i) {
    out.vertices[i].position = place.point(raw.verts[i]);
    if (i < raw.tverts.size()) {
      out.vertices[i].u = raw.tverts[i].first;
      out.vertices[i].v = raw.tverts[i].second;
    }
  }
  const size_t nv = raw.verts.size();
  auto add = [&](int32_t a, int32_t b, int32_t c, int mat) {
    if (a < 0 || b < 0 || c < 0 || size_t(a) >= nv || size_t(b) >= nv || size_t(c) >= nv) return;
    if (a == b || b == c || a == c) return;
    Triangle t;
    t.v[0] = uint32_t(a);
    t.v[1] = uint32_t(b);
    t.v[2] = uint32_t(c);
    t.material = mat;
    out.triangles.push_back(t);
  };
  for (const auto& pr : raw.prims) {
    if (size_t(pr.start) + pr.count > raw.indices.size()) continue;
    const uint32_t mi = pr.mat & kPrimMaterialMask;
    const int mat = (pr.mat & kPrimNoMaterial) || mi >= numMaterials ? -1 : int(mi);
    const int32_t* ix = raw.indices.data() + pr.start;
    const uint32_t n = pr.count;
    switch (pr.mat & kPrimTypeMask) {
      case kPrimStrip:
        for (uint32_t i = 0; i + 2 < n; ++i) {
          if (i & 1) add(ix[i + 1], ix[i], ix[i + 2], mat);
          else add(ix[i], ix[i + 1], ix[i + 2], mat);
        }
        break;
      case kPrimFan:
        for (uint32_t i = 1; i + 1 < n; ++i) add(ix[0], ix[i], ix[i + 1], mat);
        break;
      default:
        for (uint32_t i = 0; i + 2 < n; i += 3) add(ix[i], ix[i + 1], ix[i + 2], mat);
        break;
    }
  }
}

struct Reader {
  Bytes in{nullptr, 0};
  size_t at = 0;
  bool bad = false;
  std::string why;

  bool fail(const std::string& w) {
    if (!bad) why = w;
    bad = true;
    return false;
  }
  bool need(size_t k) {
    if (bad || in.n - at < k) return fail("dts: the file ends early");
    return true;
  }
  uint32_t u32() {
    if (!need(4)) return 0;
    uint32_t v;
    std::memcpy(&v, in.p + at, 4);
    at += 4;
    return v;
  }
  uint8_t u8() {
    if (!need(1)) return 0;
    return in.p[at++];
  }
  void skip(size_t k) {
    if (need(k)) at += k;
  }
  void skipBitSet() {
    u32();  // unused
    const uint32_t words = u32();
    if (words > kDtsMaxCount) return void(fail("dts: bad sequence bit set"));
    skip(size_t(words) * 4);
  }
};

}  // namespace

bool readDts(const uint8_t* data, size_t size, Shape& out, std::string& error) {
  Reader r;
  r.in = {data, size};
  const uint32_t word = r.u32();
  const int version = int(word & 0xFF);
  if (r.bad) return error = "dts: not a shape", false;
  if (version < kDtsMinVersion || version > kDtsMaxVersion) {
    error = "dts: version " + std::to_string(version) + " is not read (versions " + std::to_string(kDtsMinVersion) +
            " to " + std::to_string(kDtsMaxVersion) + " are)";
    return false;
  }
  const uint32_t words = r.u32();
  const uint32_t start16 = r.u32();
  const uint32_t start8 = r.u32();
  if (r.bad || words > (size - r.at) / 4 || start16 > start8 || start8 > words)
    return error = "dts: the shape block does not fit the file", false;
  const size_t block = r.at;
  r.at += size_t(words) * 4;

  // Sequences: only stepped over, to reach the material list.
  const uint32_t numSeq = r.u32();
  if (numSeq > kDtsMaxCount) return error = "dts: bad sequence count", false;
  for (uint32_t i = 0; i < numSeq && !r.bad; ++i) {
    r.skip(15 * 4);
    for (int b = 0; b < 8; ++b) r.skipBitSet();
  }
  // Material list: stream type, count, then names (length-prefixed).
  r.u8();
  const uint32_t numMat = r.u32();
  if (numMat > kDtsMaxCount) return error = "dts: bad material count", false;
  Shape shape;
  for (uint32_t i = 0; i < numMat && !r.bad; ++i) {
    const uint8_t len = r.u8();
    if (!r.need(len)) break;
    std::string name(reinterpret_cast<const char*>(r.in.p + r.at), len);
    r.at += len;
    while (!name.empty() && name.back() == '\0') name.pop_back();
    Material m;
    m.name = name;
    m.texture = name;
    shape.materials.push_back(m);
  }
  // Then each material's flags: only a translucent one (bit 2) uses its
  // texture's alpha for transparency.
  for (uint32_t i = 0; i < numMat && !r.bad; ++i) shape.materials[i].alphaTest = (r.u32() & 4) != 0;
  if (r.bad) return error = r.why, false;

  Alloc a;
  a.p = data;
  a.at32 = block;
  a.end32 = block + size_t(start16) * 4;
  a.at16 = a.end32;
  a.end16 = block + size_t(start8) * 4;
  a.at8 = a.end16;
  a.end8 = block + size_t(words) * 4;

  Header h{};
  h.nodes = a.count(a.s32(), "node");
  h.objects = a.count(a.s32(), "object");
  h.decals = a.count(a.s32(), "decal");
  h.subShapes = a.count(a.s32(), "sub-shape");
  h.ifls = a.count(a.s32(), "IFL material");
  h.rots = a.count(a.s32(), "node rotation");
  h.trans = a.count(a.s32(), "node translation");
  h.uscales = a.count(a.s32(), "uniform scale");
  h.ascales = a.count(a.s32(), "aligned scale");
  h.arbscales = a.count(a.s32(), "arbitrary scale");
  if (version > 23) h.groundFrames = a.count(a.s32(), "ground frame");
  h.objectStates = a.count(a.s32(), "object state");
  h.decalStates = a.count(a.s32(), "decal state");
  h.triggers = a.count(a.s32(), "trigger");
  h.details = a.count(a.s32(), "detail");
  h.meshes = a.count(a.s32(), "mesh");
  size_t skins = 0;
  if (version < 23) skins = a.count(a.s32(), "skin");
  h.names = a.count(a.s32(), "name");
  a.s32();  // smallest visible size
  a.s32();  // smallest visible detail
  a.checkGuard();
  a.skip32(1 + 1 + 3 + 6);  // radius, tube radius, centre, bounds
  a.checkGuard();

  struct Node {
    int32_t parent;
  };
  std::vector<Node> nodes(h.nodes);
  if (!a.need32(h.nodes * 5)) return error = a.why, false;
  for (auto& n : nodes) {
    a.s32();  // name
    n.parent = a.s32();
    a.skip32(3);  // first object, first child, next sibling
  }
  a.checkGuard();
  struct Object {
    int32_t numMeshes, startMesh, node;
  };
  std::vector<Object> objects(h.objects);
  if (!a.need32(h.objects * 6)) return error = a.why, false;
  for (auto& o : objects) {
    a.s32();  // name
    o.numMeshes = a.s32();
    o.startMesh = a.s32();
    o.node = a.s32();
    a.skip32(2);  // next sibling, first decal
  }
  if (version < 23) a.skip32(skins * 6);
  a.checkGuard();
  a.skip32(h.decals * 5);
  a.checkGuard();
  a.skip32(h.ifls * 5);
  a.checkGuard();
  a.skip32(h.subShapes * 3);  // first node, object, decal
  a.checkGuard();
  a.skip32(h.subShapes * 3);  // numbers of nodes, objects, decals
  a.checkGuard();
  std::vector<Quat> rot(h.nodes);
  for (auto& q : rot) q = quat16(a);
  std::vector<V3> trans(h.nodes);
  if (!a.need32(h.nodes * 3)) return error = a.why, false;
  for (auto& t : trans) t = a.point();
  a.skip32(h.trans * 3);
  a.skip16(h.rots * 4);
  a.checkGuard();
  a.skip32(h.uscales + h.ascales * 3 + h.arbscales * 3);
  a.skip16(h.arbscales * 4);
  a.checkGuard();
  if (version > 23) {
    a.skip32(h.groundFrames * 3);
    a.skip16(h.groundFrames * 4);
    a.checkGuard();
  }
  a.skip32(h.objectStates * 3);
  a.checkGuard();
  a.skip32(h.decalStates);
  a.checkGuard();
  a.skip32(h.triggers * 2);
  a.checkGuard();
  struct Detail {
    int32_t subShape, objectDetail;
    float size;
  };
  std::vector<Detail> details(h.details);
  if (!a.need32(h.details * 7)) return error = a.why, false;
  for (auto& d : details) {
    a.s32();  // name
    d.subShape = a.s32();
    d.objectDetail = a.s32();
    d.size = a.f32();
    a.skip32(3);  // average error, max error, polygon count
  }
  a.checkGuard();
  if (a.bad) return error = a.why, false;

  std::vector<RawMesh> meshes(h.meshes);
  for (size_t i = 0; i < h.meshes && !a.bad; ++i) {
    const int type = a.s32();
    if (type == kNull) continue;
    if (type == kDecal || type == kSorted) {
      error = std::string("dts: ") + (type == kDecal ? "decal" : "sorted") + " meshes are not read yet";
      return false;
    }
    if (type != kStandard && type != kSkin) return error = "dts: unknown mesh type " + std::to_string(type), false;
    if (!readMesh(a, type, meshes, meshes[i])) break;
  }
  if (a.bad) return error = a.why, false;
  a.checkGuard();
  if (a.bad) return error = a.why, false;

  // The node chain's default pose, shape space.
  std::vector<M4> world(h.nodes);
  std::vector<int> state(h.nodes, 0);  // 0 not done, 1 in progress, 2 done
  for (size_t root = 0; root < h.nodes; ++root) {
    // Walk up from `root`, then resolve back down.
    std::vector<size_t> chain;
    size_t n = root;
    while (true) {
      if (state[n] == 2) break;
      if (state[n] == 1) return error = "dts: the node tree has a loop", false;
      state[n] = 1;
      chain.push_back(n);
      const int32_t p = nodes[n].parent;
      if (p < 0) break;
      if (size_t(p) >= h.nodes) return error = "dts: a node names a parent that is not there", false;
      n = size_t(p);
    }
    for (auto it = chain.rbegin(); it != chain.rend(); ++it) {
      const M4 local = quatMatrix(rot[*it], trans[*it]);
      const int32_t p = nodes[*it].parent;
      world[*it] = p >= 0 ? world[size_t(p)] * local : local;
      state[*it] = 2;
    }
  }

  // The highest detail level that is drawn (a negative size marks
  // collision and other hidden levels).
  int detailNum = -1;
  for (size_t d = 0; d < details.size(); ++d)
    if (details[d].size >= 0 && details[d].subShape >= 0) {
      detailNum = int(d);
      break;
    }
  if (detailNum >= 0) {
    const int32_t k = details[size_t(detailNum)].objectDetail;
    for (const Object& o : objects) {
      if (k < 0 || k >= o.numMeshes) continue;
      const int64_t mi = int64_t(o.startMesh) + k;
      if (mi < 0 || size_t(mi) >= meshes.size() || !meshes[size_t(mi)].present) continue;
      const RawMesh& raw = meshes[size_t(mi)];
      M4 place = M4::identity();
      if (raw.type == kStandard && o.node >= 0 && size_t(o.node) < world.size()) place = world[size_t(o.node)];
      Mesh m;
      buildMesh(raw, place, shape.materials.size(), m);
      if (m.triangles.empty()) continue;
      computeNormals(m);
      shape.meshes.push_back(std::move(m));
    }
  }
  shape.computeBounds();
  out = std::move(shape);
  return true;
}

bool readDts(const std::vector<uint8_t>& bytes, Shape& out, std::string& error) {
  return readDts(bytes.data(), bytes.size(), out, error);
}

}  // namespace graal3d::render
