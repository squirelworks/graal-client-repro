// Tests for the world renderer (render/): the .3ds reader, the file
// resolver, the scene built from ghosts, and frames drawn from them.
// Every shape and texture here is made by the test itself.
#include "../render/draw.hpp"
#include "../render/motion.hpp"
#include "../render/read_3ds.hpp"
#include "../render/read_dif.hpp"
#include "../render/read_dts.hpp"
#include "../render/read_ft.hpp"
#include "../render/replicate.hpp"
#include "../render/terrain.hpp"
#include "bits.hpp"
#include "vectors.hpp"
#include "world.hpp"

#include <array>
#include <cmath>
#include <limits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include <zlib.h>

using namespace graal3d;
using namespace graal3d::render;

static int failures = 0;
#define CHECK(cond)                                                                 \
  do {                                                                              \
    if (!(cond)) {                                                                  \
      std::fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
      ++failures;                                                                   \
    }                                                                               \
  } while (0)

namespace {

constexpr float kPi = 3.14159265358979f;

std::string fromHexStr(const char* hex) {
  std::string out;
  for (size_t i = 0; hex[i] && hex[i + 1]; i += 2) out.push_back(char(std::strtoul(std::string(hex + i, 2).c_str(), nullptr, 16)));
  return out;
}

// ---- A small .3ds writer, for the tests' own shapes ----

struct Bytes {
  std::vector<uint8_t> b;
  void u8(uint8_t v) { b.push_back(v); }
  void u16(uint16_t v) {
    u8(uint8_t(v));
    u8(uint8_t(v >> 8));
  }
  void u32(uint32_t v) {
    u16(uint16_t(v));
    u16(uint16_t(v >> 16));
  }
  void f32(float f) {
    uint32_t v;
    std::memcpy(&v, &f, 4);
    u32(v);
  }
  void cstr(const std::string& s) {
    for (char c : s) u8(uint8_t(c));
    u8(0);
  }
  void append(const Bytes& o) { b.insert(b.end(), o.b.begin(), o.b.end()); }
};

Bytes chunk(uint16_t id, const Bytes& payload) {
  Bytes c;
  c.u16(id);
  c.u32(uint32_t(payload.b.size() + 6));
  c.append(payload);
  return c;
}

struct TestMesh {
  std::string name;
  std::vector<V3> vertices;
  std::vector<std::array<uint16_t, 3>> faces;
  std::vector<std::pair<float, float>> uvs;
  std::string material;  // empty: no face group
};

Bytes material3ds(const std::string& name, float r, float g, float b, const std::string& texture = "") {
  Bytes m;
  Bytes n;
  n.cstr(name);
  m.append(chunk(0xA000, n));
  Bytes col;
  col.f32(r);
  col.f32(g);
  col.f32(b);
  m.append(chunk(0xA020, chunk(0x0010, col)));
  if (!texture.empty()) {
    Bytes f;
    f.cstr(texture);
    m.append(chunk(0xA200, chunk(0xA300, f)));
  }
  return chunk(0xAFFF, m);
}

Bytes object3ds(const TestMesh& mesh) {
  Bytes tri;
  Bytes verts;
  verts.u16(uint16_t(mesh.vertices.size()));
  for (const V3& v : mesh.vertices) {
    verts.f32(v.x);
    verts.f32(v.y);
    verts.f32(v.z);
  }
  tri.append(chunk(0x4110, verts));
  if (!mesh.uvs.empty()) {
    Bytes uv;
    uv.u16(uint16_t(mesh.uvs.size()));
    for (auto& p : mesh.uvs) {
      uv.f32(p.first);
      uv.f32(p.second);
    }
    tri.append(chunk(0x4140, uv));
  }
  Bytes faces;
  faces.u16(uint16_t(mesh.faces.size()));
  for (auto& f : mesh.faces) {
    for (uint16_t i : f) faces.u16(i);
    faces.u16(7);
  }
  if (!mesh.material.empty()) {
    Bytes g;
    g.cstr(mesh.material);
    g.u16(uint16_t(mesh.faces.size()));
    for (size_t i = 0; i < mesh.faces.size(); ++i) g.u16(uint16_t(i));
    faces.append(chunk(0x4130, g));
  }
  tri.append(chunk(0x4120, faces));
  Bytes obj;
  obj.cstr(mesh.name);
  obj.append(chunk(0x4100, tri));
  return chunk(0x4000, obj);
}

// A cube of side `size` centred on `c`, every face its own four vertices.
TestMesh cubeMesh(const std::string& name, V3 c, float size, const std::string& material) {
  TestMesh m;
  m.name = name;
  m.material = material;
  const float h = size / 2;
  const V3 n[6] = {{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}};
  for (const V3& f : n) {
    // Two axes across the face.
    const V3 a = std::fabs(f.z) > 0.5f ? V3{1, 0, 0} : V3{0, 0, 1};
    const V3 b = cross(f, a);
    const uint16_t base = uint16_t(m.vertices.size());
    const V3 centre = c + f * h;
    m.vertices.push_back(centre + a * -h + b * -h);
    m.vertices.push_back(centre + a * h + b * -h);
    m.vertices.push_back(centre + a * h + b * h);
    m.vertices.push_back(centre + a * -h + b * h);
    m.uvs.insert(m.uvs.end(), {{0, 0}, {1, 0}, {1, 1}, {0, 1}});
    m.faces.push_back({base, uint16_t(base + 1), uint16_t(base + 2)});
    m.faces.push_back({base, uint16_t(base + 2), uint16_t(base + 3)});
  }
  return m;
}

std::vector<uint8_t> file3ds(const std::vector<Bytes>& materials, const std::vector<TestMesh>& meshes) {
  Bytes editor;
  for (const Bytes& m : materials) editor.append(m);
  for (const TestMesh& m : meshes) editor.append(object3ds(m));
  Bytes ver;
  ver.u32(3);
  Bytes main;
  main.append(chunk(0x0002, ver));
  main.append(chunk(0x3D3D, editor));
  return chunk(0x4D4D, main).b;
}

Shape cubeShape(float r, float g, float b, float size = 1.0f, V3 c = {0, 0, 0}) {
  Shape s;
  std::string error;
  const bool ok = read3ds(file3ds({material3ds("paint", r, g, b)}, {cubeMesh("box", c, size, "paint")}), s, error);
  CHECK(ok);
  return s;
}

// A 24-bit BMP of one colour.
std::vector<uint8_t> solidBmp(int w, int h, uint8_t r, uint8_t g, uint8_t b) {
  const int row = (w * 3 + 3) & ~3;
  Bytes f;
  f.u8('B');
  f.u8('M');
  f.u32(uint32_t(54 + row * h));
  f.u32(0);
  f.u32(54);
  f.u32(40);
  f.u32(uint32_t(w));
  f.u32(uint32_t(h));
  f.u16(1);
  f.u16(24);
  f.u32(0);
  f.u32(uint32_t(row * h));
  f.u32(2835);
  f.u32(2835);
  f.u32(0);
  f.u32(0);
  for (int y = 0; y < h; ++y) {
    for (int x = 0; x < w; ++x) {
      f.u8(b);
      f.u8(g);
      f.u8(r);
    }
    for (int p = w * 3; p < row; ++p) f.u8(0);
  }
  return f.b;
}

Texture solidTexture(uint8_t r, uint8_t g, uint8_t b) {
  Texture t;
  t.width = t.height = 2;
  t.pixels.assign(4, packRgba(r, g, b));
  return t;
}

struct TestFrame {
  int w, h;
  std::vector<uint32_t> px;
  TestFrame(int w_ = 160, int h_ = 120) : w(w_), h(h_), px(size_t(w_) * h_, 0xDEADBEEF) {}
  Frame frame() { return Frame{px.data(), w, h, w}; }
  uint32_t at(int x, int y) const { return px[size_t(y) * w + x]; }
  uint32_t centre() const { return at(w / 2, h / 2); }
};

// A scene with a camera at `eye`, turned by the wire's axis and angle.
Scene cameraScene(V3 eye, V3 axis = {1, 0, 0}, float angle = 0) {
  Scene s;
  s.hasCamera = true;
  s.view.cameraToWorld = graalTransform(eye, axis, angle);
  s.view.fovDegrees = 90;
  s.sun.present = true;  // full light (the 5.12 draws a quarter without one)
  return s;
}

SceneObject objectAt(const std::string& shape, V3 pos) {
  SceneObject o;
  o.shape = shape;
  o.transform = M4::translation(pos);
  return o;
}

bool isColor(uint32_t c, int r, int g, int b, int tol = 2) {
  return std::abs(red(c) - r) <= tol && std::abs(green(c) - g) <= tol && std::abs(blue(c) - b) <= tol;
}

// ---- Tests ----

void testRead3ds() {
  TestMesh col = cubeMesh("Col-1", {0, 0, 0}, 1, "paint");
  TestMesh bare = cubeMesh("bare", {3, 0, 0}, 1, "");
  Shape s;
  std::string error;
  CHECK(read3ds(file3ds({material3ds("paint", 1, 0.5f, 0, "brick.png")}, {cubeMesh("box", {0, 0, 0}, 2, "paint"), col, bare}),
                s, error));
  CHECK(s.materials.size() == 1);
  CHECK(s.materials[0].name == "paint" && s.materials[0].texture == "brick.png");
  CHECK(std::fabs(s.materials[0].color[1] - 0.5f) < 1e-6f);
  CHECK(s.meshes.size() == 3);       // box, bare, and Col-1 (drawn, lab T3D-032)
  CHECK(s.collision.size() == 1);    // Col-1 is also the collision hull
  CHECK(s.meshes[0].vertices.size() == 24 && s.meshes[0].triangles.size() == 12);
  CHECK(s.meshes[0].triangles[0].material == 0);
  CHECK(s.meshes[1].triangles[0].material == -1);  // no face group: not drawn
  CHECK(std::fabs(s.boundsMin.x + 1) < 1e-6f && std::fabs(s.boundsMax.x - 3.5f) < 1e-6f);
  // v counts from the bottom of the image in a .3ds.
  CHECK(std::fabs(s.meshes[0].vertices[0].v - 1.0f) < 1e-6f);

  // A material defined after the object that names it.
  Bytes editor;
  editor.append(object3ds(cubeMesh("box", {0, 0, 0}, 1, "late")));
  editor.append(material3ds("late", 0, 1, 0));
  Shape late;
  CHECK(read3ds(chunk(0x4D4D, chunk(0x3D3D, editor)).b, late, error));
  CHECK(late.meshes.size() == 1 && late.meshes[0].triangles[0].material == 0);

  // Refused: not a 3ds, a chunk longer than the file, cut short, a face
  // naming a vertex that is not there.
  Shape bad;
  CHECK(!read3ds(std::vector<uint8_t>{1, 2, 3, 4, 5, 6, 7}, bad, error));
  auto good = file3ds({material3ds("paint", 1, 1, 1)}, {cubeMesh("box", {0, 0, 0}, 1, "paint")});
  auto cut = good;
  cut.resize(cut.size() - 10);
  CHECK(!read3ds(cut, bad, error));
  auto longer = good;
  longer[2] = 0xFF;
  longer[3] = 0xFF;
  CHECK(!read3ds(longer, bad, error));
  TestMesh wrong = cubeMesh("box", {0, 0, 0}, 1, "paint");
  wrong.faces[0][1] = 999;
  CHECK(!read3ds(file3ds({material3ds("paint", 1, 1, 1)}, {wrong}), bad, error));
  // Every truncation of a good file is refused or read, never a crash.
  for (size_t n = 0; n < good.size(); ++n) {
    Shape any;
    read3ds(good.data(), n, any, error);
  }
}

void testRotationRule() {
  // A shape turns as the camera does (lab follow-up 10): at +90 degrees
  // about +z its +x face looks to -y.
  const V3 g = graalShapeTransform({0, 0, 0}, {0, 0, 1}, kPi / 2).vector({1, 0, 0});
  CHECK(std::fabs(g.y + 1) < 1e-5f && std::fabs(g.x) < 1e-5f);
  // A positive angle about +z turns right: forward (+y) becomes +x.
  const V3 f = graalRotation({0, 0, 1}, kPi / 2).vector({0, 1, 0});
  CHECK(std::fabs(f.x - 1) < 1e-5f && std::fabs(f.y) < 1e-5f);
  // A positive angle about +x tilts the view down.
  const V3 d = graalRotation({1, 0, 0}, 0.38f).vector({0, 1, 0});
  CHECK(d.z < 0 && d.y > 0);
}

void testDrawObjects() {
  Resources res;
  res.putShape("red.3ds", cubeShape(1, 0, 0));
  res.putShape("green.3ds", cubeShape(0, 1, 0, 0.5f));

  // No Camera: black, as the 5.x client.
  {
    TestFrame f;
    Scene s;
    s.objects.push_back(objectAt("red.3ds", {0, 5, 0}));
    CHECK(drawScene(f.frame(), s, res).objectsDrawn == 0);
    CHECK(isColor(f.centre(), 0, 0, 0) && isColor(f.at(0, 0), 0, 0, 0));
  }
  // A red cube straight ahead, nothing else: red in the middle, the
  // clear colour (black without a Sky) at the corner.
  {
    TestFrame f;
    Scene s = cameraScene({0, -5, 0});
    s.objects.push_back(objectAt("red.3ds", {0, 0, 0}));
    const DrawStats st = drawScene(f.frame(), s, res);
    CHECK(st.objectsDrawn == 1 && st.triangles == 12);
    CHECK(isColor(f.centre(), 255, 0, 0));
    CHECK(isColor(f.at(0, 0), 0, 0, 0));
    // The cube is 1 unit wide, 4.5 units away, 90 degrees across 160
    // pixels: about 160 / 2 / 4.5 = 18 pixels wide.
    int wide = 0;
    for (int x = 0; x < f.w; ++x) wide += isColor(f.at(x, f.h / 2), 255, 0, 0);
    CHECK(wide >= 16 && wide <= 20);
  }
  // A nearer green cube hides the red one; order in the list does not matter.
  {
    TestFrame f;
    Scene s = cameraScene({0, -5, 0});
    s.objects.push_back(objectAt("green.3ds", {0, -2, 0}));
    s.objects.push_back(objectAt("red.3ds", {0, 0, 0}));
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 0, 255, 0));
  }
  // Turning the camera right by a quarter turn brings a cube on +x into view.
  {
    TestFrame f;
    Scene s = cameraScene({0, 0, 0}, {0, 0, 1}, kPi / 2);
    s.objects.push_back(objectAt("red.3ds", {5, 0, 0}));
    s.objects.push_back(objectAt("green.3ds", {0, 5, 0}));
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 255, 0, 0));
  }
  // Behind the camera: not drawn, and nothing crosses the near plane badly.
  {
    TestFrame f;
    Scene s = cameraScene({0, 0, 0});
    s.objects.push_back(objectAt("red.3ds", {0, -5, 0}));
    s.objects.push_back(objectAt("green.3ds", {0, 0, 0}));  // around the eye
    drawScene(f.frame(), s, res);
    for (uint32_t c : f.px) CHECK(alpha(c) == 255);
    CHECK(!isColor(f.centre(), 255, 0, 0));
  }
  // A missing shape is counted, not drawn.
  {
    TestFrame f;
    Scene s = cameraScene({0, -5, 0});
    s.objects.push_back(objectAt("nothere.dts", {0, 0, 0}));
    const DrawStats st = drawScene(f.frame(), s, res);
    CHECK(st.objectsDrawn == 0 && st.objectsMissing == 1);
  }
  // A shape whose faces have no material is loaded but not drawn.
  {
    Shape bare;
    std::string error;
    CHECK(read3ds(file3ds({}, {cubeMesh("box", {0, 0, 0}, 1, "")}), bare, error));
    res.putShape("bare.3ds", bare);
    TestFrame f;
    Scene s = cameraScene({0, -5, 0});
    s.objects.push_back(objectAt("bare.3ds", {0, 0, 0}));
    const DrawStats st = drawScene(f.frame(), s, res);
    CHECK(st.objectsDrawn == 1 && st.triangles == 0);
    CHECK(isColor(f.centre(), 0, 0, 0));
  }
}

void testSunAndFog() {
  Resources res;
  res.putShape("white.3ds", cubeShape(1, 1, 1));
  auto litCentre = [&](V3 dir) {
    TestFrame f;
    Scene s = cameraScene({0, -5, 0});
    s.sun.present = true;
    s.sun.direction = normalize(dir);
    for (int i = 0; i < 3; ++i) {
      s.sun.color[i] = 0.75f;
      s.sun.ambient[i] = 0.25f;
    }
    s.objects.push_back(objectAt("white.3ds", {0, 0, 0}));
    drawScene(f.frame(), s, res);
    return f.centre();
  };
  // The draw distance (T3D-075): 1000 by default, set by the player,
  // clamped to 2400; nothing past it draws.
  {
    res.putShape("big.3ds", cubeShape(1, 1, 1, 100));
    auto drawnAt = [&](float y) {
      TestFrame f;
      Scene s = cameraScene({0, 0, 0});
      s.objects.push_back(objectAt("big.3ds", {0, y, 0}));
      drawScene(f.frame(), s, res);
      return isColor(f.centre(), 255, 255, 255);
    };
    CHECK(gVisibleDistance3D == 1000);
    CHECK(drawnAt(900) && !drawnAt(1100));
    CHECK(setVisibleDistance3D(500) == 500 && drawnAt(400) && !drawnAt(600));
    CHECK(setVisibleDistance3D(5000) == 2400 && drawnAt(2300) && !drawnAt(2500));
    CHECK(setVisibleDistance3D(-1) == 1000 && setVisibleDistance3D(std::nanf("")) == 1000);
  }
  // The 5.12 ignores the Sun's direction, colour and ambient (lighting
  // probe): every face full; without a Sun, a quarter.
  CHECK(isColor(litCentre({0, 1, 0}), 255, 255, 255));
  CHECK(isColor(litCentre({0, -1, 0}), 255, 255, 255));
  CHECK(isColor(litCentre({0, 0.5f, -0.8660254f}), 255, 255, 255));
  {
    TestFrame f;
    Scene s = cameraScene({0, -5, 0});
    s.sun.present = false;
    s.objects.push_back(objectAt("white.3ds", {0, 0, 0}));
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 64, 64, 64));
  }
  // The fixed light from (-x, -y, +z): a face toward +y or +x draws at
  // 0.85, whatever the Sun (follow-up 10).
  {
    TestFrame f;
    Scene s = cameraScene({0, 5, 0}, {0, 0, 1}, kPi);  // looking -y at the +y face
    s.objects.push_back(objectAt("white.3ds", {0, 0, 0}));
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 217, 217, 217));
  }
  // A .dts or .dif without a Sun is black; with one, full (follow-up 11).
  {
    Shape d = cubeShape(1, 1, 1);
    d.kind = Shape::kDif;
    res.putShape("white.dif", d);
    TestFrame f;
    Scene s = cameraScene({0, 5, 0}, {0, 0, 1}, kPi);
    s.objects.push_back(objectAt("white.dif", {0, 0, 0}));
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 255, 255, 255));
    s.sun.present = false;
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 0, 0, 0));
  }

  // No fog on objects and no distance clip (lab, Mesa): with a visible
  // distance of 100 and a blue fog, cubes at 20, 90, 120 and 800 units
  // all draw white.
  res.putShape("bigwhite.3ds", cubeShape(1, 1, 1, 10));
  auto fogged = [&](float dist) {
    TestFrame f;
    Scene s = cameraScene({0, 0, 0});
    s.sky.present = true;
    s.sky.visibleDistance = 100;
    s.sky.fogColor[0] = 0;
    s.sky.fogColor[1] = 0;
    s.sky.fogColor[2] = 1;
    s.objects.push_back(objectAt("bigwhite.3ds", {0, dist, 0}));
    drawScene(f.frame(), s, res);
    return f.centre();
  };
  for (float d : {20.0f, 90.0f, 120.0f, 800.0f}) CHECK(isColor(fogged(d), 255, 255, 255));
}

void testSkyBox() {
  Resources res;
  const char* names[6] = {"sky_fr", "sky_rt", "sky_bk", "sky_lf", "sky_up", "sky_dn"};
  const int colors[6][3] = {{200, 0, 0}, {0, 200, 0}, {0, 0, 200}, {200, 200, 0}, {0, 200, 200}, {200, 0, 200}};
  for (int i = 0; i < 6; ++i) res.putTexture(names[i], solidTexture(uint8_t(colors[i][0]), uint8_t(colors[i][1]), uint8_t(colors[i][2])));
  auto look = [&](V3 axis, float angle) {
    TestFrame f;
    Scene s = cameraScene({10, 20, 3}, axis, angle);
    s.sky.present = true;
    s.sky.visibleDistance = 500;
    for (int i = 0; i < 6; ++i) s.sky.textures[i] = names[i];
    drawScene(f.frame(), s, res);
    return f.centre();
  };
  // Facing +y the client draws entry 2 (T3D-046); a point above the band.
  auto lookAbove = [&](V3 axis, float angle) {
    TestFrame f;
    Scene s = cameraScene({10, 20, 3}, axis, angle);
    s.sky.present = true;
    for (int i = 0; i < 6; ++i) s.sky.textures[i] = names[i];
    drawScene(f.frame(), s, res);
    return f.at(f.w / 2, f.h / 2 - 30);
  };
  CHECK(isColor(lookAbove({0, 0, 1}, 0), 0, 0, 200));            // entry 2, +y
  CHECK(isColor(lookAbove({0, 0, 1}, kPi / 2), 0, 200, 0));      // entry 1, +x
  CHECK(isColor(lookAbove({0, 0, 1}, kPi), 200, 0, 0));          // entry 0, -y
  CHECK(isColor(lookAbove({0, 0, 1}, -kPi / 2), 200, 200, 0));   // entry 3, -x
  CHECK(isColor(look({1, 0, 0}, -kPi / 2), 0, 200, 200));        // up (a negative angle tilts up)
  CHECK(isColor(look({1, 0, 0}, kPi / 2), 0, 0, 0));             // down: entry 5 not drawn, the fog colour
  {
    TestFrame f;
    Scene s = cameraScene({10, 20, 3}, {1, 0, 0}, kPi / 2);
    s.sky.present = true;
    s.sky.drawBottom = true;  // the Sky's floor option
    for (int i = 0; i < 6; ++i) s.sky.textures[i] = names[i];
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 200, 0, 200));
  }

  // The fog band: the fog colour at the horizon, the image above it,
  // the fog colour below.
  {
    TestFrame f;
    Scene s = cameraScene({10, 20, 3});
    s.sky.present = true;
    s.sky.fogColor[0] = 1;
    for (int i = 0; i < 6; ++i) s.sky.textures[i] = names[i];
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.at(f.w / 2, f.h / 2 - 1), 255, 0, 0, 8));
    CHECK(isColor(f.at(f.w / 2, f.h / 2 - 30), 0, 0, 200));
    const uint32_t mid = f.at(f.w / 2, f.h / 2 - 10);  // part way up the band
    CHECK(red(mid) > 60 && red(mid) < 200 && blue(mid) > 40 && blue(mid) < 160);
    CHECK(isColor(f.at(f.w / 2, f.h / 2 + 10), 255, 0, 0));
  }
  // The side faces draw mirrored: facing +y, the image's right half is on
  // the viewer's left.
  {
    Texture halves;
    halves.width = 2;
    halves.height = 1;
    halves.pixels = {packRgba(255, 0, 0), packRgba(0, 0, 255)};
    res.putTexture("halves", halves);
    TestFrame f;
    Scene s = cameraScene({10, 20, 3});
    s.sky.present = true;
    s.sky.textures[2] = "halves";
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.at(f.w / 4, f.h / 2 - 30), 0, 0, 255));
    CHECK(isColor(f.at(3 * f.w / 4, f.h / 2 - 30), 255, 0, 0));
  }
  // The first option off: the solid colour instead of the images.
  {
    TestFrame f;
    Scene s = cameraScene({10, 20, 3});
    s.sky.present = true;
    s.sky.useTextures = false;
    s.sky.solidColor[1] = 0.5f;
    for (int i = 0; i < 6; ++i) s.sky.textures[i] = names[i];
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.at(f.w / 2, f.h / 2 - 30), 0, 128, 0));
  }

  // Looking toward a corner, every face in view reaches behind the camera;
  // each must still fill its part of the frame (the Sharp3D replay showed
  // such faces dropping out to the fog colour).
  // A wide frame and a narrow field of view, as in that capture (789 by
  // 588, 60 degrees), put the clipped corners far off screen.
  for (float yaw : {kPi / 4, 3 * kPi / 4, -kPi / 3}) {
    TestFrame f(789, 588);
    Scene s = cameraScene({10, 20, 3}, {0, 0, 1}, yaw);
    s.view.fovDegrees = 60;
    // Tilted well up, so the frame stays above the horizon's fog band.
    s.view.cameraToWorld = s.view.cameraToWorld * graalRotation({1, 0, 0}, -1.0f);
    s.sky.present = true;
    for (int i = 0; i < 6; ++i) s.sky.textures[i] = names[i];
    drawScene(f.frame(), s, res);
    int uncovered = 0;
    for (uint32_t p : f.px) {
      bool sky = false;
      for (const auto& c : colors) sky |= isColor(p, c[0], c[1], c[2]);
      uncovered += !sky;
    }
    CHECK(uncovered == 0);
  }
}

bool nearV(const V3& a, const V3& b);

void testSceneFromGhosts() {
  GhostTable ghosts;
  // The recorded Seihai payloads: the Sun, the Sky and a player object.
  {
    BitReader r(fromHexStr(kSun));
    ghosts[0].className = "Sun";
    CHECK(readSunUpdate(r, ghosts[0].sun));
  }
  {
    BitReader r(fromHexStr(kSky));
    ghosts[1].className = "Sky";
    CHECK(readSkyUpdate(r, ghosts[1].sky));
    // The whole Sky is read and it ends inside the last byte.
    const size_t bits = fromHexStr(kSky).size() * 8;
    CHECK(r.pos() <= bits && bits - r.pos() < 8);
    CHECK(ghosts[1].sky.fogVolumes.empty());
  }
  {
    BitReader r(fromHexStr(kGameObject));
    ghosts[2].className = "GameObject";
    CHECK(readGameObjectUpdate(r, ghosts[2].object));
  }
  ghosts[3].className = "Camera";
  ghosts[3].camera.object.position = {0, -5, 2};
  ghosts[3].camera.object.axis = {1, 0, 0};
  ghosts[3].camera.object.angle = 0.38f;
  ghosts[4].className = "GameObject";  // no shape: not drawn

  Scene none = sceneFromGhosts(ghosts, -1, 0);
  CHECK(!none.hasCamera);
  Scene s = sceneFromGhosts(ghosts, 3, 0);
  CHECK(s.hasCamera);
  CHECK(std::fabs(s.view.fovDegrees - 90) < 1e-6f);
  CHECK(s.sun.present && std::fabs(s.sun.direction.z + 0.57735f) < 1e-3f);
  CHECK(s.sky.present && s.sky.textures[0] == "sky_fr" && s.sky.textures[5] == "sky_dn");
  CHECK(std::fabs(s.sky.visibleDistance - 500) < 1e-3f);
  CHECK(s.objects.size() == 1 && s.objects[0].shape == ghosts[2].object.shape);
  CHECK(std::fabs(s.view.cameraToWorld.m[2][3] - 2) < 1e-6f);
  CHECK(sceneFromGhosts(ghosts, 3, 60).view.fovDegrees == 60);
  // An editor object (flag 0x04) is not drawn.
  ghosts[2].object.flags = 0x04;
  CHECK(sceneFromGhosts(ghosts, 3, 0).objects.empty());
  ghosts[2].object.flags = 0x08;
  CHECK(sceneFromGhosts(ghosts, 3, 0).objects.size() == 1);
  ghosts[2].object.flags = 0;
  // A static GameObject shows no tag, whatever its nickname (lab).
  ghosts[4].object.nickname = "Zed";
  ghosts[4].object.nickColor[0] = 7;
  CHECK(sceneFromGhosts(ghosts, 3, 0).tags.empty() || sceneFromGhosts(ghosts, 3, 0).tags[0].ghost != 4);
  // A moving, shapeless GameObject with a nickname is tagged but not drawn.
  ghosts[4].object.hasMovement = true;
  {
    const Scene t = sceneFromGhosts(ghosts, 3, 0);
    CHECK(t.objects.size() == 1);
    int found = 0;
    for (const SceneTag& tag : t.tags)
      if (tag.ghost == 4) found += tag.nickname == "Zed" && tag.color[0] == 7 && tag.shape.empty();
    CHECK(found == 1);
  }
  ghosts[4].object.nickname.clear();
  ghosts[4].object.hasMovement = false;
  // A DynamicShapeReplicator draws its shape like a GameObject; the grass
  // classes draw nothing (lab T3D-048).
  {
    GhostTable rg;
    for (int i = 0; i < 3; ++i) {
      rg[i].className = i == 0 ? "DynamicShapeReplicator" : i == 1 ? "DynamicGrassReplicator" : "DynamicGrass";
      rg[i].object.shape = "rock.3ds";
      rg[i].object.hasTransform = true;
    }
    const Scene rs = sceneFromGhosts(rg, -1, 0);
    CHECK(rs.objects.size() == 1 && rs.objects[0].ghost == 0 && rs.objects[0].shape == "rock.3ds");
  }
  // A WaterBlock's surface is its top: position z plus scale z.
  {
    GhostTable wg;
    wg[0].className = "WaterBlock";
    wg[0].water.init = true;
    wg[0].water.position = {5, 6, 10};
    wg[0].water.scale = {2048, 2048, 3};
    wg[0].water.rotation[3] = 1;
    const Scene ws = sceneFromGhosts(wg, -1, 0);
    CHECK(ws.water.size() == 1 && std::fabs(ws.water[0].transform.m[2][3] - 13) < 1e-4f);
    // Any scale is taken; the block runs from its corner to corner + scale
    // and turns about it: 90 degrees about z puts its +x along world -y
    // (lab, Graal_analysis PR #895).
    wg[0].water.position = {0, 0, 0};
    wg[0].water.scale = {512, 256, 0};
    const float h = std::sqrt(0.5f);
    wg[0].water.rotation[2] = h;
    wg[0].water.rotation[3] = h;
    const Scene turned = sceneFromGhosts(wg, -1, 0);
    CHECK(turned.water.size() == 1 && turned.water[0].width == 512 && turned.water[0].depth == 256);
    if (turned.water.size() == 1) {
      CHECK(nearV(turned.water[0].transform.point({512, 0, 0}), {0, -512, 0}));
      CHECK(nearV(turned.water[0].transform.point({0, 256, 0}), {256, 0, 0}));
    }
    wg[0].water.scale = {0, 256, 0};
    CHECK(sceneFromGhosts(wg, -1, 0).water.empty());
  }
  // Waves (lab grid fit): flat at magnitude 0; on x = y a point swings
  // +-0.5 x magnitude, elsewhere less; one period is 2 pi / 0.984 s; crests
  // travel toward -x.
  CHECK(waveHeight(0, 1, 5, 5) == 0);
  {
    auto swing = [](float x, float y) {
      float lo = 1e9f, hi = -1e9f;
      for (int k = 0; k < 700; ++k) {
        const float h = waveHeight(1, k * 0.01, x, y);
        lo = std::min(lo, h);
        hi = std::max(hi, h);
      }
      return hi - lo;
    };
    CHECK(std::fabs(swing(10, 10) - 1.0f) < 0.01f);
    CHECK(swing(0, 63) < 0.15f);  // half a wavelength apart: nearly cancel
    const double period = 2 * 3.14159265358979 / kWaveOmega;
    CHECK(std::fabs(waveHeight(1, 1.0, 7, 3) - waveHeight(1, 1.0 + period, 7, 3)) < 1e-3f);
    // A crest at x moves to x - c dt (c = w / k).
    const float c = kWaveOmega * kWaveLength / (2 * 3.14159265f);
    CHECK(std::fabs(waveHeight(1, 2.0, 40, 5) - waveHeight(1, 1.0, 40 + c, 5 + c)) < 1e-3f);
  }
  // Section 2 scales the shape about its origin; zeros mean unset.
  {
    GameObjectState o;
    o.position = {1, 2, 3};
    const V3 p = objectTransform(o).point({1, 1, 1});
    CHECK(std::fabs(p.x - 2) < 1e-5f && std::fabs(p.z - 4) < 1e-5f);
    o.scale = {1, 1, 3};
    const V3 q = objectTransform(o).point({1, 1, 1});
    CHECK(std::fabs(q.x - 2) < 1e-5f && std::fabs(q.z - 6) < 1e-5f);
  }

  // "-" leaves a face empty.
  ghosts[1].sky.textures = "a,-,c";
  Scene dash = sceneFromGhosts(ghosts, 3, 0);
  CHECK(dash.sky.textures[0] == "a" && dash.sky.textures[1].empty() && dash.sky.textures[2] == "c");

  // Drawn: the player's shape from a file of the test's own.
  Resources res;
  res.putShape(ghosts[2].object.shape, cubeShape(1, 1, 1, 1, {0, 0, 0}));
  TestFrame f(320, 240);
  const DrawStats st = drawScene(f.frame(), s, res);
  CHECK(st.objectsDrawn == 1);
}

// ---- A .dts writer for the tests (version 24 by default) ---------------
// The layout the reader follows (render/read_dts.hpp): three streams with
// a guard after each section, then the sequences and the material list.
struct DtsStreams {
  std::vector<uint8_t> s32, s16, s8;
  uint32_t guard = 0;
  void i32(int32_t v) {
    for (int i = 0; i < 4; ++i) s32.push_back(uint8_t(uint32_t(v) >> (8 * i)));
  }
  void f32(float f) {
    int32_t v;
    std::memcpy(&v, &f, 4);
    i32(v);
  }
  void i16(int16_t v) {
    s16.push_back(uint8_t(v));
    s16.push_back(uint8_t(uint16_t(v) >> 8));
  }
  void u8(uint8_t v) { s8.push_back(v); }
  void g() {
    i32(int32_t(guard));
    i16(int16_t(guard));
    u8(uint8_t(guard));
    ++guard;
  }
};

struct DtsMesh {
  int type = 0;  // 0 standard, 1 skin, 4 null
  int parent = -1;
  std::vector<V3> verts;
  std::vector<std::pair<float, float>> tverts;
  std::vector<std::array<uint32_t, 3>> prims;  // start, count, material word
  std::vector<int16_t> indices;
};

struct DtsSpec {
  int version = 24;
  // Nodes: parent, rotation (standard quaternion x, y, z, w), translation.
  struct Node {
    int parent;
    float q[4];
    V3 t;
  };
  std::vector<Node> nodes;
  struct Object {
    int node, startMesh, numMeshes;
  };
  std::vector<Object> objects;
  std::vector<std::pair<int, float>> details;  // object detail number, size
  std::vector<DtsMesh> meshes;
  std::vector<std::pair<std::string, uint32_t>> materials;  // name, flags
  int sequences = 1;  // empty sequences, in the version's own layout
};

// Below version 23 a skin mesh is written to the separate skin list (all
// in the first detail level) and a null mesh takes its place.
std::vector<uint8_t> dtsFile(const DtsSpec& spec) {
  DtsSpec d = spec;
  std::vector<DtsMesh> oldSkins;
  if (d.version < 23)
    for (auto& m : d.meshes)
      if (m.type == 1) {
        oldSkins.push_back(m);
        m = DtsMesh();
        m.type = 4;
      }
  const bool encodedNormals = d.version > 21;
  DtsStreams a;
  a.i32(int32_t(d.nodes.size()));
  a.i32(int32_t(d.objects.size()));
  a.i32(0);  // decals
  a.i32(1);  // sub-shapes
  a.i32(0);  // IFL materials
  if (d.version > 21)
    for (int i = 0; i < 5; ++i) a.i32(0);  // node rotations ... arbitrary scales
  else
    a.i32(int32_t(d.nodes.size()));  // node states, the default pose included
  if (d.version > 23) a.i32(0);      // ground frames
  a.i32(0);  // object states
  a.i32(0);  // decal states
  a.i32(0);  // triggers
  a.i32(int32_t(d.details.size()));
  a.i32(int32_t(d.meshes.size()));
  if (d.version < 23) a.i32(int32_t(oldSkins.size()));  // skins
  a.i32(2);  // names
  a.f32(0);
  a.i32(0);
  a.g();
  for (int i = 0; i < 11; ++i) a.f32(0);  // radius, tube radius, centre, bounds
  a.g();
  for (const auto& n : d.nodes) {
    a.i32(0);
    a.i32(n.parent);
    a.i32(-1);
    a.i32(-1);
    a.i32(-1);
  }
  a.g();
  for (const auto& o : d.objects) {
    a.i32(0);
    a.i32(o.numMeshes);
    a.i32(o.startMesh);
    a.i32(o.node);
    a.i32(-1);
    a.i32(-1);
  }
  a.g();
  a.g();  // decals
  a.g();  // IFL materials
  a.i32(0);
  a.i32(0);
  a.i32(0);
  a.g();
  a.i32(int32_t(d.nodes.size()));
  a.i32(int32_t(d.objects.size()));
  a.i32(0);
  a.g();
  for (const auto& n : d.nodes)  // Torque keeps the conjugate
    for (int i = 0; i < 4; ++i) a.i16(int16_t(std::lround((i < 3 ? -n.q[i] : n.q[i]) * 32767)));
  for (const auto& n : d.nodes) {
    a.f32(n.t.x);
    a.f32(n.t.y);
    a.f32(n.t.z);
  }
  a.g();
  if (d.version > 21) a.g();  // scales
  if (d.version > 23) a.g();  // ground frames
  a.g();  // object states
  a.g();  // decal states
  a.g();  // triggers
  for (const auto& [k, size] : d.details) {
    a.i32(0);
    a.i32(0);
    a.i32(k);
    a.f32(size);
    a.f32(0);
    a.f32(0);
    a.i32(0);
  }
  a.g();
  auto writeMesh = [&](const DtsMesh& m) {
    a.g();
    a.i32(1);
    a.i32(1);
    a.i32(m.parent);
    for (int i = 0; i < 10; ++i) a.f32(0);  // bounds, centre, radius
    const bool own = m.parent < 0;
    const bool skin = m.type == 1;
    const size_t nv = skin ? 0 : m.verts.size();
    a.i32(int32_t(nv));
    if (own && !skin)
      for (const auto& v : m.verts) {
        a.f32(v.x);
        a.f32(v.y);
        a.f32(v.z);
      }
    a.i32(int32_t(m.tverts.size()));
    if (own)
      for (const auto& t : m.tverts) {
        a.f32(t.first);
        a.f32(t.second);
      }
    if (own) {
      for (size_t i = 0; i < nv * 3; ++i) a.f32(0);
      if (encodedNormals)
        for (size_t i = 0; i < nv; ++i) a.u8(0);
    }
    a.i32(int32_t(m.prims.size()));
    for (const auto& p : m.prims) {
      a.i16(int16_t(p[0]));
      a.i16(int16_t(p[1]));
      a.i32(int32_t(p[2]));
    }
    a.i32(int32_t(m.indices.size()));
    for (int16_t i : m.indices) a.i16(i);
    a.i32(0);  // merge indices
    a.i32(int32_t(nv));
    a.i32(0);
    a.g();
    if (skin) {
      a.i32(int32_t(m.verts.size()));
      if (own) {
        for (const auto& v : m.verts) {
          a.f32(v.x);
          a.f32(v.y);
          a.f32(v.z);
        }
        for (size_t i = 0; i < m.verts.size() * 3; ++i) a.f32(0);
        if (encodedNormals)
          for (size_t i = 0; i < m.verts.size(); ++i) a.u8(0);
      }
      a.i32(1);  // initial transforms
      if (own)
        for (int i = 0; i < 16; ++i) a.f32(i % 5 == 0 ? 1.0f : 0.0f);
      a.i32(int32_t(m.verts.size()));  // weights
      if (own)
        for (size_t i = 0; i < m.verts.size(); ++i) {
          a.i32(int32_t(i));
          a.i32(0);
          a.f32(1);
        }
      a.i32(1);  // nodes
      if (own) a.i32(0);
      a.g();
    }
    if (m.type == 3) {  // sorted: one cluster over every primitive
      a.i32(1);
      a.i32(0);
      a.i32(int32_t(m.prims.size()));
      for (int i = 0; i < 3; ++i) a.f32(i == 2 ? 1.0f : 0.0f);
      a.f32(0);
      a.i32(-1);
      a.i32(-1);
      for (int arr = 0; arr < 4; ++arr) {
        a.i32(1);
        a.i32(arr == 2 ? int32_t(nv) : 0);
      }
      a.i32(1);  // always write depth
      a.g();
    }
  };
  for (const auto& m : d.meshes) {
    a.i32(m.type);
    if (m.type != 4) writeMesh(m);
  }
  a.g();
  for (const char* name : {"a", "bc"}) {
    for (const char* c = name; *c; ++c) a.u8(uint8_t(*c));
    a.u8(0);
  }
  a.g();  // names
  if (d.version < 23) {
    for (size_t i = 0; i < d.details.size(); ++i) a.i32(i == 0 ? 0 : int32_t(oldSkins.size()));
    for (size_t i = 0; i < d.details.size(); ++i) a.i32(i == 0 ? int32_t(oldSkins.size()) : 0);
    a.g();
    for (const auto& m : oldSkins) writeMesh(m);
    a.g();
  }
  // Pad the 16- and 8-bit streams to whole words and join them.
  while (a.s16.size() % 4) a.s16.push_back(0);
  while (a.s8.size() % 4) a.s8.push_back(0);
  std::vector<uint8_t> f;
  auto u32 = [&](uint32_t v) {
    for (int i = 0; i < 4; ++i) f.push_back(uint8_t(v >> (8 * i)));
  };
  u32(uint32_t(d.version) | (1u << 16));
  u32(uint32_t((a.s32.size() + a.s16.size() + a.s8.size()) / 4));
  u32(uint32_t(a.s32.size() / 4));
  u32(uint32_t((a.s32.size() + a.s16.size()) / 4));
  f.insert(f.end(), a.s32.begin(), a.s32.end());
  f.insert(f.end(), a.s16.begin(), a.s16.end());
  f.insert(f.end(), a.s8.begin(), a.s8.end());
  u32(uint32_t(d.sequences));
  for (int q = 0; q < d.sequences; ++q) {
    const int words = d.version > 21 ? 15 : 12, sets = d.version > 21 ? 8 : 6;
    for (int i = 0; i < 3; ++i) u32(0);  // name, (flags,) key frames ...
    if (d.version < 22) f.insert(f.end(), {1, 0, 1});  // blend, cyclic, make path
    for (int i = 3; i < words; ++i) u32(0);
    for (int i = 0; i < sets; ++i) {
      u32(0);
      u32(1);  // one word
      u32(0xFFFFFFFFu);
    }
  }
  f.push_back(1);
  u32(uint32_t(d.materials.size()));
  for (const auto& [name, flags] : d.materials) {
    f.push_back(uint8_t(name.size()));
    f.insert(f.end(), name.begin(), name.end());
  }
  for (const auto& [name, flags] : d.materials) u32(flags);
  for (int k = 0; k < 5; ++k)
    for (size_t i = 0; i < d.materials.size(); ++i) u32(0);
  return f;
}

// Two nodes (the second turned 90 degrees about z and moved), a triangle
// list on the second node, a strip sharing the first mesh's vertices on
// the root, a skin mesh, and a collision detail level that is not drawn.
DtsSpec sampleDts() {
  DtsSpec d;
  const float h = std::sqrt(0.5f);
  d.nodes = {{-1, {0, 0, 0, 1}, {0, 0, 0}}, {0, {0, 0, h, h}, {1, 2, 3}}};
  d.objects = {{1, 0, 2}, {0, 2, 2}, {1, 4, 2}};
  d.details = {{0, 10.0f}, {1, -1.0f}};
  DtsMesh tri;
  tri.verts = {{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {1, 1, 0}};
  tri.tverts = {{0, 0}, {1, 0}, {0, 1}, {1, 1}};
  tri.prims = {{0, 3, 0}};
  tri.indices = {0, 1, 2};
  DtsMesh strip;
  strip.parent = 0;
  strip.prims = {{0, 4, (1u << 30) | 1}, {4, 3, 1u << 28}};  // a strip; then one with no material
  strip.indices = {0, 1, 2, 3, 0, 1, 3};
  DtsMesh skin;
  skin.type = 1;
  skin.verts = {{5, 5, 5}, {6, 5, 5}, {5, 6, 5}};
  skin.prims = {{0, 3, 0}};
  skin.indices = {0, 1, 2};
  DtsMesh null;
  null.type = 4;
  DtsMesh hull = tri;  // the collision level: never drawn
  d.meshes = {tri, hull, strip, null, skin, null};
  d.materials = {{"base.metal", 0}, {"leaves", 4}};
  return d;
}

bool nearV(const V3& a, const V3& b) { return std::fabs(a.x - b.x) < 1e-3f && std::fabs(a.y - b.y) < 1e-3f && std::fabs(a.z - b.z) < 1e-3f; }

void testReadDts() {
  // A sorted mesh (TSSortedMesh, in the 5.12) draws its faces as a
  // standard one, placed by its node.
  {
    DtsSpec d = sampleDts();
    d.meshes[0].type = 3;
    Shape sorted, plain;
    std::string e1, e2;
    const bool ok1 = readDts(dtsFile(d), sorted, e1), ok2 = readDts(dtsFile(sampleDts()), plain, e2);
    if (!ok1) std::fprintf(stderr, "readDts sorted: %s\n", e1.c_str());
    CHECK(ok1 && ok2 && sorted.meshes.size() == plain.meshes.size());
    if (ok1 && ok2 && sorted.meshes.size() == plain.meshes.size() && !sorted.meshes.empty()) {
      CHECK(sorted.meshes[0].triangles.size() == plain.meshes[0].triangles.size());
      CHECK(nearV(sorted.meshes[0].vertices[1].position, plain.meshes[0].vertices[1].position));
    }
    d.meshes[0].type = 2;  // decal: no such class in the 5.12
    Shape decal;
    CHECK(!readDts(dtsFile(d), decal, e1));
  }
  Shape s;
  std::string error;
  const std::vector<uint8_t> file = dtsFile(sampleDts());
  const bool ok = readDts(file, s, error);
  if (!ok) std::fprintf(stderr, "readDts: %s\n", error.c_str());
  CHECK(ok);
  CHECK(s.materials.size() == 2);
  CHECK(s.materials.size() == 2 && s.materials[0].name == "base.metal" && s.materials[0].texture == "base.metal");
  CHECK(s.materials.size() == 2 && !s.materials[0].alphaTest && s.materials[1].alphaTest);
  CHECK(s.meshes.size() == 3);
  if (s.meshes.size() == 3) {
    // The triangle list on node 1: turned 90 degrees about z, then moved.
    const Mesh& a = s.meshes[0];
    CHECK(a.triangles.size() == 1 && a.triangles[0].material == 0);
    CHECK(nearV(a.vertices[0].position, {1, 2, 3}));
    CHECK(nearV(a.vertices[1].position, {1, 3, 3}));
    CHECK(nearV(a.vertices[2].position, {0, 2, 3}));
    CHECK(a.vertices[1].u == 1 && a.vertices[2].v == 1);
    // The strip on the root shares those vertices: two triangles, the
    // second wound the other way; the no-material primitive is kept with -1.
    const Mesh& b = s.meshes[1];
    CHECK(b.triangles.size() == 3);
    if (b.triangles.size() == 3) {
      CHECK(b.triangles[0].v[0] == 0 && b.triangles[0].v[1] == 1 && b.triangles[0].v[2] == 2);
      CHECK(b.triangles[1].v[0] == 2 && b.triangles[1].v[1] == 1 && b.triangles[1].v[2] == 3);
      CHECK(b.triangles[0].material == 1 && b.triangles[2].material == -1);
    }
    CHECK(nearV(b.vertices[3].position, {1, 1, 0}));
    // The skin mesh: its initial vertices, as they are (shape space).
    const Mesh& c = s.meshes[2];
    CHECK(c.triangles.size() == 1 && nearV(c.vertices[1].position, {6, 5, 5}));
  }

  // Versions outside 19 to 24 are refused by name.
  for (int v : {17, 18, 25, 26}) {
    DtsSpec d = sampleDts();
    d.version = v;
    std::vector<uint8_t> f = dtsFile(d);
    Shape t;
    CHECK(!readDts(f, t, error));
    CHECK(error.find("version " + std::to_string(v)) != std::string::npos);
  }
  // Versions 19 to 23 read: no ground frames below 24; below 23 the skins
  // in a list of their own; below 22 one node-state count, no scales, no
  // encoded normals, and the older sequence layout.
  for (int v : {19, 20, 21, 22, 23}) {
    DtsSpec d = sampleDts();
    d.version = v;
    d.sequences = 2;
    Shape t;
    const bool read = readDts(dtsFile(d), t, error);
    if (!read) std::fprintf(stderr, "readDts version %d: %s\n", v, error.c_str());
    CHECK(read && t.meshes.size() == 3 && t.materials.size() == 2);
    if (t.meshes.size() == 3) {
      CHECK(nearV(t.meshes[0].vertices[1].position, {1, 3, 3}));
      CHECK(t.meshes[2].triangles.size() == 1 && nearV(t.meshes[2].vertices[1].position, {6, 5, 5}));
    }
    CHECK(t.materials.size() == 2 && !t.materials[0].alphaTest && t.materials[1].alphaTest);
    if (v == 21) {
      std::vector<uint8_t> f = dtsFile(d);
      uint32_t seed = 11;
      for (int i = 0; i < 20000; ++i) {
        std::vector<uint8_t> m = f;
        for (int k = 0; k < 4; ++k) {
          seed = seed * 1103515245u + 12345u;
          m[(seed >> 8) % m.size()] = uint8_t(seed >> 3);
        }
        Shape u;
        readDts(m, u, error);
      }
      for (size_t n = 0; n < f.size(); ++n) {
        Shape u;
        readDts(f.data(), n, u, error);
      }
    }
  }
  // A broken guard is caught.
  std::vector<uint8_t> broken = file;
  broken[16 + 19 * 4] ^= 0x55;  // the first guard: after 19 header words
  Shape t;
  CHECK(!readDts(broken, t, error));
  // Every truncation and many byte changes are refused or read safely.
  for (size_t n = 0; n < file.size(); ++n) {
    Shape u;
    readDts(file.data(), n, u, error);
  }
  uint32_t seed = 7;
  for (int i = 0; i < 20000; ++i) {
    std::vector<uint8_t> m = file;
    for (int k = 0; k < 4; ++k) {
      seed = seed * 1103515245u + 12345u;
      m[(seed >> 8) % m.size()] = uint8_t(seed >> 3);
    }
    Shape u;
    readDts(m, u, error);
  }

  // Resources loads a .dts by its extension, and finds a material whose
  // name has a dot of its own by adding the image extension.
  const auto root = std::filesystem::temp_directory_path() / "g3d-render-test-dts";
  std::filesystem::remove_all(root);
  std::filesystem::create_directories(root / "shapes");
  {
    std::ofstream o(root / "shapes" / "Thing.DTS", std::ios::binary);
    o.write(reinterpret_cast<const char*>(file.data()), std::streamsize(file.size()));
    const std::vector<uint8_t> bmp = solidBmp(2, 2, 9, 8, 7);
    std::ofstream t2(root / "shapes" / "base.metal.bmp", std::ios::binary);
    t2.write(reinterpret_cast<const char*>(bmp.data()), std::streamsize(bmp.size()));
  }
  Resources res;
  res.setImageFormats(Resources::ImageFormats::kAll);  // the tests write BMP
  res.addRoot(root.string());
  const Shape* thing = res.shape("thing.dts");
  CHECK(thing && thing->meshes.size() == 3);
  const Texture* metal = res.texture("base.metal");
  CHECK(metal && isColor(metal->pixels[0], 9, 8, 7));
  std::filesystem::remove_all(root);
}

// ---- A .dif writer for the tests (resource 44, interior 0) ------------
struct DifWriter {
  std::vector<uint8_t> b;
  void u8(uint8_t v) { b.push_back(v); }
  void u16(uint16_t v) {
    u8(uint8_t(v));
    u8(uint8_t(v >> 8));
  }
  void u32(uint32_t v) {
    for (int i = 0; i < 4; ++i) u8(uint8_t(v >> (8 * i)));
  }
  void f32(float f) {
    uint32_t v;
    std::memcpy(&v, &f, 4);
    u32(v);
  }
  void str(const std::string& s) {
    u8(uint8_t(s.size()));
    for (char c : s) u8(uint8_t(c));
  }
};

// A 2 by 3 floor (one strip of four points) textured by world x and y,
// and a surface on Torque's NULL material that is never drawn.
// `wideMaps` writes the surfaces' lightmap fields as 16-bit values.
std::vector<uint8_t> difFile(uint32_t resource = 44, int32_t interior = 0, bool narrowWindings = true,
                             bool wideMaps = false, bool preview = false) {
  DifWriter w;
  w.u32(resource);
  w.u8(preview ? 1 : 0);
  if (preview) {
    const uint8_t png[] = {0x89, 'P', 'N', 'G', 1, 2, 3, 0, 0, 0, 0, 'I', 'E', 'N', 'D', 0xAE, 0x42, 0x60, 0x82};
    for (uint8_t c : png) w.u8(c);
  }
  w.u32(1);  // detail levels
  w.u32(uint32_t(interior));
  w.u32(0);
  w.u32(0);
  for (int i = 0; i < 10; ++i) w.f32(0);  // box, sphere
  w.u8(0);
  w.u32(0);
  w.u32(1);  // normals
  w.f32(0);
  w.f32(0);
  w.f32(1);
  w.u32(1);  // planes
  w.u16(0);
  w.f32(0);
  const float pts[4][3] = {{0, 0, 0}, {2, 0, 0}, {0, 3, 0}, {2, 3, 0}};
  w.u32(4);
  for (const auto& p : pts)
    for (float f : p) w.f32(f);
  w.u32(4);  // point visibilities
  for (int i = 0; i < 4; ++i) w.u8(0xFF);
  w.u32(1);  // texgen: u = x / 2, v = y / 3
  const float tg[8] = {0.5f, 0, 0, 0, 0, 1.0f / 3, 0, 0};
  for (float f : tg) w.f32(f);
  w.u32(1);  // BSP nodes
  for (int i = 0; i < 3; ++i) w.u16(0);
  w.u32(1);  // BSP leaves
  w.u32(0);
  w.u16(2);
  w.u8(1);  // material list version
  w.u32(2);
  w.str("floor");
  w.str("NULL");
  const int32_t wind[7] = {0, 1, 2, 3, 0, 1, 2};
  if (narrowWindings) {
    w.u32(7 | 0x80000000u);
    w.u8(1);
    for (int32_t i : wind) w.u16(uint16_t(i));
  } else {
    w.u32(7);
    for (int32_t i : wind) w.u32(uint32_t(i));
  }
  w.u32(0);  // winding indices
  w.u32(0);  // zones
  w.u32(0);  // zone surfaces
  w.u32(0);  // zone portals
  w.u32(0);  // portals
  w.u32(2);  // surfaces
  const uint32_t starts[2] = {0, 4};
  const uint8_t counts[2] = {4, 3};
  for (int k = 0; k < 2; ++k) {
    w.u32(starts[k]);
    w.u8(counts[k]);
    w.u16(k ? 0x8000 : 0);  // the second plane flipped
    w.u16(uint16_t(k));     // material
    w.u32(0);               // texgen
    w.u8(0);
    w.u32(0);
    w.u16(0);
    w.f32(0);
    w.f32(0);
    w.u16(0);
    w.u32(0);
    for (int i = 0; i < 4; ++i) wideMaps ? w.u16(0) : w.u8(0);
  }
  // What follows (null surfaces, lightmaps, other levels) is not read.
  w.u32(0);
  return w.b;
}

void testReadDif() {
  Shape s;
  std::string error;
  const std::vector<uint8_t> file = difFile();
  bool ok = readDif(file, s, error);
  if (!ok) std::fprintf(stderr, "readDif: %s\n", error.c_str());
  CHECK(ok);
  CHECK(s.materials.size() == 2 && s.materials[0].texture == "floor");
  CHECK(s.meshes.size() == 1);  // the NULL surface is not drawn
  if (s.meshes.size() == 1) {
    const Mesh& m = s.meshes[0];
    CHECK(m.triangles.size() == 2);
    CHECK(m.vertices.size() == 4);
    if (m.triangles.size() == 2 && m.vertices.size() == 4) {
      // A strip: (0 1 2), then (2 1 3) wound back.
      CHECK(m.triangles[0].v[0] == 0 && m.triangles[0].v[1] == 1 && m.triangles[0].v[2] == 2);
      CHECK(m.triangles[1].v[0] == 2 && m.triangles[1].v[1] == 1 && m.triangles[1].v[2] == 3);
      CHECK(m.triangles[0].material == 0);
      CHECK(std::fabs(m.vertices[3].u - 1) < 1e-5f && std::fabs(m.vertices[3].v - 1) < 1e-5f);
      CHECK(std::fabs(m.vertices[1].u - 1) < 1e-5f && std::fabs(m.vertices[1].v) < 1e-5f);
    }
  }
  CHECK(nearV(s.boundsMax, {2, 3, 0}));
  // Wide windings, wide lightmap fields and a preview image read the same.
  for (const auto& f : {difFile(44, 0, false), difFile(44, 0, true, true), difFile(44, 0, true, false, true)}) {
    Shape t;
    CHECK(readDif(f, t, error) && t.meshes.size() == 1 && t.meshes[0].triangles.size() == 2);
  }
  // Other versions are refused by name.
  Shape t;
  CHECK(!readDif(difFile(43), t, error) && error.find("resource version 43") != std::string::npos);
  CHECK(!readDif(difFile(44, 14), t, error) && error.find("interior version 14") != std::string::npos);
  // Truncations and byte changes are refused or read safely.
  for (size_t n = 0; n < file.size(); ++n) readDif(file.data(), n, t, error);
  uint32_t seed = 11;
  for (int i = 0; i < 20000; ++i) {
    std::vector<uint8_t> m = file;
    for (int k = 0; k < 3; ++k) {
      seed = seed * 1103515245u + 12345u;
      m[(seed >> 8) % m.size()] = uint8_t(seed >> 3);
    }
    readDif(m, t, error);
  }
}

void testResources() {
  namespace fs = std::filesystem;
  const fs::path root = fs::temp_directory_path() / ("g3d-render-test-" + std::to_string(std::rand()));
  fs::create_directories(root / "shapes");
  fs::create_directories(root / "images" / "sky");
  auto write = [](const fs::path& p, const std::vector<uint8_t>& b) {
    std::ofstream o(p, std::ios::binary);
    o.write(reinterpret_cast<const char*>(b.data()), std::streamsize(b.size()));
  };
  write(root / "shapes" / "Tower.3DS",
        file3ds({material3ds("stone", 1, 1, 1, "Stone.BMP")}, {cubeMesh("tower", {0, 0, 0}, 1, "stone")}));
  write(root / "images" / "stone.bmp", solidBmp(4, 4, 10, 120, 30));
  write(root / "images" / "sky" / "sky_fr.bmp", solidBmp(3, 3, 1, 2, 3));
  write(root / "images" / "junk.png", {1, 2, 3});
  // As a 5.x client stores a download: no extension (Sharp3D capture).
  write(root / "images" / "km001fc0", solidBmp(2, 2, 40, 50, 60));

  Resources res;
  res.setImageFormats(Resources::ImageFormats::kAll);  // the tests write BMP
  std::vector<std::string> logs;
  res.setLog([&](const std::string& l) { logs.push_back(l); });
  res.addRoot(root.string());
  CHECK(!res.find("tower.3ds").empty());
  const Shape* tower = res.shape("TOWER.3ds");
  CHECK(tower && tower->meshes.size() == 1);
  CHECK(res.shape("tower.3ds") == tower);  // cached
  const Texture* stone = res.texture("stone.bmp");
  CHECK(stone && stone->width == 4 && isColor(stone->pixels[0], 10, 120, 30));
  CHECK(res.texture("sky_fr") != nullptr);       // no extension: tried as .bmp
  CHECK(res.texture("sky_fr.png") != nullptr);   // another extension falls back too
  CHECK(res.texture("junk.png") == nullptr);
  const Texture* bare = res.texture("km001fc0.png");  // named with .png, stored without
  CHECK(bare && bare->width == 2 && isColor(bare->pixels[0], 40, 50, 60));
  CHECK(res.shape("later.3ds") == nullptr);
  CHECK(res.shape("tree.dts") == nullptr);

  // The textured cube draws with its texture.
  {
    TestFrame f;
    Scene s = cameraScene({0, -5, 0});
    s.objects.push_back(objectAt("tower.3ds", {0, 0, 0}));
    drawScene(f.frame(), s, res);
    CHECK(isColor(f.centre(), 10, 120, 30));
  }

  // A file that lands later is found after a rescan.
  write(root / "shapes" / "later.3ds", file3ds({material3ds("m", 1, 1, 1)}, {cubeMesh("x", {0, 0, 0}, 1, "m")}));
  CHECK(res.shape("later.3ds") == nullptr);
  res.rescan();
  CHECK(res.shape("later.3ds") != nullptr);
  CHECK(res.shape("tower.3ds") == tower);  // kept across the rescan
  // Every shape looked up is named, found or not (a host asks for each).
  CHECK(res.shapesNamed().count("tower.3ds") && res.shapesNamed().count("later.3ds"));
  // A newer copy over a loaded shape is read again after forget().
  write(root / "shapes" / "later.3ds",
        file3ds({material3ds("m", 1, 1, 1)}, {cubeMesh("x", {0, 0, 0}, 2, "m")}));
  const Shape* before = res.shape("later.3ds");
  const float sideBefore = before ? before->boundsMax.x - before->boundsMin.x : 0;
  res.forget("LATER.3ds");
  res.rescan();
  const Shape* after = res.shape("later.3ds");
  CHECK(after && std::fabs((after->boundsMax.x - after->boundsMin.x) - 2 * sideBefore) < 1e-3f);
  CHECK(!logs.empty());
  fs::remove_all(root);
}

}  // namespace

// What the 5.12 draws (lab, 2026-11-25; Graal_analysis T3D-032): 8-bit
// PNG, JPEG and GIF by content, whatever the name; not BMP or 16-bit PNG;
// GIF transparency as opaque white.
void testClientImageFormats() {
  const auto root = std::filesystem::temp_directory_path() / "g3d-render-test-formats";
  std::filesystem::remove_all(root);
  std::filesystem::create_directories(root);
  auto write = [&](const char* name, const std::vector<uint8_t>& b) {
    std::ofstream o(root / name, std::ios::binary);
    o.write(reinterpret_cast<const char*>(b.data()), std::streamsize(b.size()));
  };
  write("png8", std::vector<uint8_t>{0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,0xde,0x00,0x00,0x00,0x0c,0x49,0x44,0x41,0x54,0x78,0x9c,0x63,0x38,0x91,0x62,0x04,0x00,0x03,0x56,0x01,0x5f,0xe8,0x17,0x84,0x52,0x00,0x00,0x00,0x00,0x49,0x45,0x4e,0x44,0xae,0x42,0x60,0x82});
  write("png16", std::vector<uint8_t>{0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x10,0x02,0x00,0x00,0x00,0xc0,0xe7,0x8f,0x9d,0x00,0x00,0x00,0x0f,0x49,0x44,0x41,0x54,0x78,0x9c,0x63,0x38,0xc1,0x90,0xc2,0x60,0xc4,0x00,0x00,0x06,0xab,0x01,0x5f,0x54,0x9e,0x4c,0x87,0x00,0x00,0x00,0x00,0x49,0x45,0x4e,0x44,0xae,0x42,0x60,0x82});
  write("gif", std::vector<uint8_t>{0x47,0x49,0x46,0x38,0x39,0x61,0x02,0x00,0x01,0x00,0x80,0x00,0x00,0xff,0x00,0x00,0x00,0x00,0x00,0x21,0xf9,0x04,0x01,0x00,0x00,0x01,0x00,0x2c,0x00,0x00,0x00,0x00,0x02,0x00,0x01,0x00,0x00,0x02,0x02,0x44,0x0a,0x00,0x3b});
  write("bmp", solidBmp(2, 2, 1, 2, 3));
  Resources res;
  res.addRoot(root.string());
  const Texture* p8 = res.texture("png8.png");
  CHECK(p8 && isColor(p8->pixels[0], 200, 100, 50));
  CHECK(res.texture("png16.png") == nullptr);
  CHECK(res.texture("bmp.png") == nullptr);
  const Texture* g = res.texture("gif.jpg");  // named as anything: read by content
  CHECK(g && g->width == 2 && isColor(g->pixels[0], 255, 0, 0) && g->pixels[1] == packRgba(255, 255, 255));
  // Up to 1024 a side draws; 2048 does not (lab, live-512-shapes).
  auto greyPng = [](uint32_t w, uint32_t h) {
    auto be = [](std::vector<uint8_t>& v, uint32_t x) {
      for (int i = 3; i >= 0; --i) v.push_back(uint8_t(x >> (8 * i)));
    };
    auto chunk = [&](std::vector<uint8_t>& out, const char* type, const std::vector<uint8_t>& data) {
      be(out, uint32_t(data.size()));
      std::vector<uint8_t> td(type, type + 4);
      td.insert(td.end(), data.begin(), data.end());
      out.insert(out.end(), td.begin(), td.end());
      be(out, uint32_t(crc32(0, td.data(), uInt(td.size()))));
    };
    std::vector<uint8_t> raw;
    for (uint32_t y = 0; y < h; ++y) {
      raw.push_back(0);
      raw.insert(raw.end(), w, 128);
    }
    std::vector<uint8_t> z(compressBound(uLong(raw.size())));
    uLongf zn = uLongf(z.size());
    compress(z.data(), &zn, raw.data(), uLong(raw.size()));
    z.resize(zn);
    std::vector<uint8_t> out{0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
    std::vector<uint8_t> ihdr;
    be(ihdr, w);
    be(ihdr, h);
    ihdr.insert(ihdr.end(), {8, 0, 0, 0, 0});
    chunk(out, "IHDR", ihdr);
    chunk(out, "IDAT", z);
    chunk(out, "IEND", {});
    return out;
  };
  write("side1024", greyPng(1024, 2));
  write("side2048", greyPng(2, 2048));
  res.rescan();
  CHECK(res.texture("side1024") != nullptr);
  CHECK(res.texture("side2048") == nullptr);
  Resources all;
  all.setImageFormats(Resources::ImageFormats::kAll);
  all.addRoot(root.string());
  CHECK(all.texture("bmp") != nullptr && all.texture("png16") != nullptr && all.texture("side2048") != nullptr);
  const Texture* ga = all.texture("gif");
  CHECK(ga && alpha(ga->pixels[1]) == 0);
  std::filesystem::remove_all(root);
}

// ---- A terrain chunk writer for the tests (terrain-512.md section 2) ---
// Wire deltas that decode to exactly `h` (heights small enough that no
// delta needs clamping).
struct ChunkSpec {
  int mode = 2;
  int16_t h[16][16] = {};
  std::vector<int> ids;          // material ids
  int primary[16][16] = {};      // index into ids
  bool blend[16][16] = {};
  int second[16][16] = {};  // index into ids, for a blend
  bool hole[16][16] = {};
};

std::string chunkBytes(const ChunkSpec& c) {
  int dec[16][16];  // decoded deltas
  int8_t wire[16][16];
  for (int y = 0; y < 16; ++y)
    for (int x = 0; x < 16; ++x) {
      if (y == 0 && x == 0) dec[y][x] = 0;
      else if (y == 0) dec[y][x] = c.h[0][x] - c.h[0][x - 1];
      else if (x == 0) dec[y][x] = c.h[y][0] - c.h[y - 1][0];
      else dec[y][x] = c.h[y][x] - (c.h[y - 1][x] + c.h[y][x - 1]) / 2;
      wire[y][x] = int8_t(y == 0 || x == 0 ? dec[y][x] : dec[y][x] - (dec[y - 1][x] + dec[y][x - 1]) / 2);
    }
  BitWriter w;
  w.bits(uint32_t(c.mode), 8);
  w.bits(uint16_t(c.h[0][0]), 16);
  for (auto& row : wire)
    for (int8_t v : row) w.bits(uint8_t(v), 8);
  w.bits(uint32_t(c.ids.size()), 6);
  for (int id : c.ids) w.bits(uint32_t(id), 5);
  if (c.ids.size() > 1) {
    int bitsW = 0;
    while ((1u << bitsW) < c.ids.size()) ++bitsW;
    for (int y = 0; y < 16; ++y)
      for (int x = 0; x < 16; ++x) {
        w.flag(c.blend[y][x]);
        w.bits(uint32_t(c.primary[y][x]), bitsW);
        if (c.blend[y][x]) {
          w.bits(uint32_t(c.second[y][x]), bitsW);
          w.bits(7, 4);
        }
      }
  }
  if (c.mode == 2)
    for (auto& row : c.hole)
      for (bool v : row) w.flag(v);
  return w.bytes();
}

std::vector<uint8_t> zipped(const std::string& raw) {
  uLongf n = compressBound(uLong(raw.size()));
  std::vector<uint8_t> out(n);
  compress(out.data(), &n, reinterpret_cast<const Bytef*>(raw.data()), uLong(raw.size()));
  out.resize(n);
  return out;
}

void testTerrain() {
  // A slope with a bump, two materials (ids 3 and 1), a blend and a hole.
  ChunkSpec c;
  for (int y = 0; y < 16; ++y)
    for (int x = 0; x < 16; ++x) {
      c.h[y][x] = int16_t(40 + x * 2 + y + (x == 5 && y == 6 ? 20 : 0));
      c.primary[y][x] = x < 8 ? 0 : 1;
    }
  c.ids = {3, 1};
  c.blend[2][2] = true;
  c.second[2][2] = 1;  // primary id 3 at share 7, id 1 the rest
  c.hole[15][15] = true;
  const std::string raw = chunkBytes(c);
  Terrain t;
  CHECK(applyTerrainChunk(t, 2, 1, reinterpret_cast<const uint8_t*>(raw.data()), raw.size()));
  auto at = [](int x, int y) { return size_t(y) * kTerrainSize + size_t(x); };
  // Chunk (2, 1) covers squares x 32..47, y 16..31. Stored = wire << 2.
  CHECK(t.heights[at(32, 16)] == 40 * 4);
  CHECK(t.heights[at(32 + 5, 16 + 6)] == (40 + 10 + 6 + 20) * 4);
  CHECK(t.heights[at(47, 31)] == (40 + 30 + 15) * 4);
  CHECK(std::fabs(t.heightMetres(32, 16) - 5.0f) < 1e-6f);  // 40 units of 1/8 m
  CHECK(t.material[at(33, 16)] == 3 && t.material[at(40, 16)] == 1 && t.material[at(34, 17)] == 3);
  CHECK(t.hole[at(47, 31)] == 1 && t.hole[at(46, 31)] == 0);
  // The blend is kept with the larger alpha first: primary 3 at 7 * 16 is
  // less than 1's 255 - 112, so it is saved as primary 1 at share 8.
  CHECK(t.material[at(34, 18)] == 1 && t.secondary[at(34, 18)] == 3 && t.blendShare[at(34, 18)] == 8);
  // The client's re-encoding: mode 2, ids ascending (1, 3), and it reads
  // back to the same terrain, re-encodes to the same bytes and stamps them.
  const std::vector<uint8_t> canon = encodeTerrainChunk(t, 2, 1);
  CHECK(!canon.empty() && canon[0] == 2);
  {
    BitReader cr(std::string(canon.begin(), canon.end()));
    cr.bits(8 + 16 + 2048);
    CHECK(cr.bits(6) == 2 && cr.bits(5) == 1 && cr.bits(5) == 3);
  }
  Terrain again;
  applyTerrainChunk(again, 2, 1, canon.data(), canon.size());
  CHECK(encodeTerrainChunk(again, 2, 1) == canon);
  CHECK(again.heights == t.heights && again.material == t.material && again.hole == t.hole);
  CHECK(t.stamps[1 * 16 + 2] == terrainStamp(canon) && again.stamps[1 * 16 + 2] == t.stamps[1 * 16 + 2]);
  CHECK(t.stamps[0] == 0);
  // The stamp is CRC-32 without the final inversion.
  const std::string check = "123456789";
  CHECK(terrainStamp(std::vector<uint8_t>(check.begin(), check.end())) == (0xCBF43926u ^ 0xFFFFFFFFu));
  CHECK(t.heights[at(31, 16)] == 0 && t.heights[at(32, 15)] == 0);  // neighbours untouched
  CHECK(!applyTerrainChunk(t, 16, 0, reinterpret_cast<const uint8_t*>(raw.data()), raw.size()));
  // Mode 1 clears the chunk's holes; mode 0 leaves them.
  ChunkSpec flat;
  flat.mode = 0;
  std::string f0 = chunkBytes(flat);
  applyTerrainChunk(t, 2, 1, reinterpret_cast<const uint8_t*>(f0.data()), f0.size());
  CHECK(t.hole[at(47, 31)] == 1 && t.heights[at(40, 20)] == 0 && t.material[at(40, 20)] == 0);
  flat.mode = 1;
  std::string f1 = chunkBytes(flat);
  applyTerrainChunk(t, 2, 1, reinterpret_cast<const uint8_t*>(f1.data()), f1.size());
  CHECK(t.hole[at(47, 31)] == 0);
  // Compressed, and corrupt (applied as zeros).
  Terrain z;
  const std::vector<uint8_t> packed = zipped(raw);
  CHECK(applyCompressedTerrainChunk(z, 0, 0, packed.data(), packed.size()) && z.heights[at(0, 0)] == 160);
  std::vector<uint8_t> bad = packed;
  bad[bad.size() / 2] ^= 0xFF;
  bad.resize(bad.size() - 3);
  CHECK(applyCompressedTerrainChunk(z, 0, 0, bad.data(), bad.size()) && z.heights[at(0, 0)] == 0);
  // Short data reads as zeros without faults; random bytes too.
  uint32_t seed = 5;
  for (int i = 0; i < 3000; ++i) {
    std::string m = raw.substr(0, size_t(seed % (raw.size() + 1)));
    for (char& ch : m) {
      seed = seed * 1103515245u + 12345u;
      if ((seed >> 16) % 7 == 0) ch = char(seed >> 8);
    }
    Terrain u;
    applyTerrainChunk(u, int(seed % 16), int((seed >> 4) % 16), reinterpret_cast<const uint8_t*>(m.data()), m.size());
  }

  // heights.info: one name per line; a comma is part of a name.
  const auto names = parseHeightsInfo("grass\r\nrock,dirt\n\nsand\n");
  CHECK(names.size() == 4 && names[0] == "grass" && names[1] == "rock,dirt" && names[2].empty() && names[3] == "sand");

  // The cache folder: heights.info and heights<x>-<y>.dat.
  const auto root = std::filesystem::temp_directory_path() / "g3d-render-test-terrain";
  std::filesystem::remove_all(root);
  std::filesystem::create_directories(root);
  {
    std::ofstream(root / "heights.info") << "a\nb\nc\nd\n";
    std::ofstream o(root / "heights15-3.dat", std::ios::binary);
    o.write(reinterpret_cast<const char*>(packed.data()), std::streamsize(packed.size()));
  }
  Terrain cached;
  CHECK(loadTerrainCache(root.string(), cached) == 1 && cached.present && cached.chunksLoaded == 1);
  CHECK(cached.materials.size() == 4 && cached.materials[3] == "d");
  CHECK(cached.heights[at(15 * 16, 3 * 16)] == 160);
  std::filesystem::remove_all(root);

  // The mesh: centred on the origin, 8 m squares, one hole left out.
  const Shape s = terrainShape(cached);
  CHECK(s.meshes.size() == 1 && s.materials.size() == 4 && s.materials[3].texture == "d");
  if (s.meshes.size() == 1) {
    const Mesh& m = s.meshes[0];
    CHECK(m.vertices.size() == 257u * 257u);
    CHECK(m.triangles.size() == 2u * (256u * 256u - 1u));
    CHECK(nearV(m.vertices[0].position, {-1024, -1024, 0}));
    const Vertex& v = m.vertices[size_t(3 * 16) * 257 + size_t(15 * 16)];
    CHECK(nearV(v.position, {(240 - 128) * 8.0f, (48 - 128) * 8.0f, 5.0f}));
    CHECK(nearV(m.vertices[256].position, {1024, -1024, 0}));  // wraps to point 0
    // Every square draws with the first texture, whatever its material
    // (the 5.12 on Mesa: grass and sand squares drew as water).
    bool allFirst = true;
    for (const auto& tri : m.triangles) allFirst = allFirst && tri.material == 0;
    CHECK(allFirst);
  }

  // Drawn from above: the terrain fills the view in its texture's colour.
  Resources res;
  // A terrain texture that is not 256 by 256 is not used: white.
  Texture small;
  small.width = small.height = 1;
  small.pixels = {packRgba(30, 200, 40)};
  for (const char* n : {"a", "b", "c", "d"}) res.putTexture(n, small);
  Texture green;
  green.width = green.height = 256;
  green.pixels.assign(256 * 256, packRgba(30, 200, 40));
  Scene scene;
  scene.hasCamera = true;
  scene.view.fovDegrees = 60;
  scene.view.cameraToWorld = graalTransform({0, 0, 50}, {1, 0, 0}, 1.5708f);  // looking down
  scene.sun.present = true;
  SceneObject obj;
  obj.direct = &s;
  obj.transform = M4::identity();
  scene.objects.push_back(obj);
  std::vector<uint32_t> px(64 * 48);
  drawScene({px.data(), 64, 48, 64}, scene, res);
  CHECK(isColor(px[24 * 64 + 32], 255, 255, 255));
  for (const char* n : {"a", "b", "c", "d"}) res.putTexture(n, green);
  drawScene({px.data(), 64, 48, 64}, scene, res);
  CHECK(isColor(px[24 * 64 + 32], 30, 200, 40));
  // Water above it at half opacity, in its texture's colour, blended.
  Texture blue;
  blue.width = blue.height = 1;
  blue.pixels = {packRgba(0, 0, 220)};
  res.putTexture("lake", blue);
  WaterSurface w;
  w.transform = M4::translation({-1024, -1024, 10});
  w.width = w.depth = 2048;
  w.texture = "lake";
  w.opacity = 0.5f;
  scene.water.push_back(w);
  drawScene({px.data(), 64, 48, 64}, scene, res);
  CHECK(isColor(px[24 * 64 + 32], 15, 100, 130));
}

void testStreamedTerrain() {
  ChunkSpec c;
  for (int y = 0; y < 16; ++y)
    for (int x = 0; x < 16; ++x) c.h[y][x] = int16_t(8 * (x + y));
  c.ids = {0};
  const std::vector<uint8_t> z = zipped(chunkBytes(c));
  std::map<int, std::string> chunks;
  chunks[1 * 16 + 2] = std::string(z.begin(), z.end());
  StreamedTerrain st;
  CHECK(updateStreamedTerrain(st, 8, false, "", chunks, 1));
  CHECK(!st.shape.meshes.empty());
  // Square (32 + 3, 16 + 4): wire 8 * 7 = 56, stored 224, 7 m.
  CHECK(std::fabs(st.terrain.heightMetres(35, 20) - 7) < 1e-4f);
  // Nothing changed: no rebuild. A new chunk or new settings: rebuilt.
  CHECK(!updateStreamedTerrain(st, 8, false, "", chunks, 1));
  chunks[0] = chunks[1 * 16 + 2];
  CHECK(updateStreamedTerrain(st, 8, false, "", chunks, 2));
  CHECK(std::fabs(st.terrain.heightMetres(3, 4) - 7) < 1e-4f);
  CHECK(updateStreamedTerrain(st, 4, false, "", chunks, 2));
  CHECK(st.terrain.squareSize == 4);
}

void testFtTrees() {
  // The made-up lab file from torque/ft-trees-512.md, plus a leaf term.
  const std::string lab =
      "// lab tree\n"
      "width 0.4 0.3\n"
      "length 2\n"
      "defaultLevels 4\n"
      "billboard \"far tree\"   // a quoted word\n"
      "gramma\n{\n  A B[RA][LA]\n  A 2 B[RA]\n}\n"
      "term B branch\n{\n  texBranch 0\n  lengthRatio 0.7 0.9\n  widthRatio 0.7\n}\n"
      "term [ push\n"
      "term ] pop\n"
      "term R rotate\n{\n  yaw 20 40\n  pitch 25\n}\n"
      "term L rotate\n{\n  yaw -40 -20\n  pitch 25\n}\n"
      "term F leaf\n{\n  texLeaf 1\n  size 300\n}\n"
      "term Q unknowntype\n{\n  yaw 5\n}\n"
      "texture 0 bark.png\n{\n  0 0 1 1\n}\n"
      "texture 1 leaves\n"
      "mystery\n{\n  { \n  }\n  width 9 9\n}\n";
  FtTree t;
  std::string error;
  CHECK(parseFt(lab, t, error));
  CHECK(t.width[0] == 0.4f && t.width[1] == 0.3f && t.length == 2 && t.defaultLevels == 4);
  CHECK(t.billboard == "far tree");
  CHECK(t.start == 'A' && t.rules['A'].size() == 2 && t.rules['A'][1].weight == 2);
  CHECK(t.terms.size() == 6 && !t.terms.count('Q'));  // an unknown type is skipped
  CHECK(t.terms['B'].lengthRatio[0] == 0.7f && t.terms['B'].lengthRatio[1] == 0.9f);
  CHECK(t.terms['R'].yaw[0] == 20 && t.terms['R'].pitch[1] == 25);
  CHECK(t.terms['F'].size == 100);  // clamped
  CHECK(t.textures[0] == "bark.png" && t.textures[1] == "leaves");
  // Growing rewrites A each round; the result is made of the rules' text.
  const std::string g = growFt(t, 7, 0);
  CHECK(!g.empty() && g.size() <= kFtMaxString);
  CHECK(g.find_first_not_of("AB[]RL") == std::string::npos && g[0] == 'B');
  CHECK(growFt(t, 7, 0) == g);  // repeatable
  CHECK(growFt(t, 7, 1).size() < g.size());
  // Levels clamp to 15, and the string stops at 512.
  CHECK(growFt(t, 7, 99).size() <= kFtMaxString);
  // The shape: tubes for branches, rising from the origin.
  const Shape sh = ftShape(t, 7, 3);
  CHECK(sh.materials.size() == 8 && sh.materials[0].texture == "bark.png");
  CHECK(sh.meshes.size() == 1 && !sh.meshes[0].triangles.empty());
  CHECK(sh.boundsMin.z > -0.5f && sh.boundsMax.z > 2);
  for (const Triangle& tri : sh.meshes[0].triangles) CHECK(tri.material == 0);
  // A symbol with neither a rule nor a term is dropped in the next round.
  FtTree drop;
  CHECK(parseFt("gramma\n{\n  A BZ\n}\nterm B branch\n", drop, error));
  CHECK(growFt(drop, 1, 1) == "BZ" && growFt(drop, 1, 2) == "B");
  // No rules: refused.
  FtTree none;
  CHECK(!parseFt("width 1 1\n", none, error));
  // Through Resources by extension.
  Resources res;
  const std::string dir = (std::filesystem::temp_directory_path() / "g3d-ft-test").string();
  std::filesystem::create_directories(dir);
  { std::ofstream(dir + "/labtree.ft") << lab; }
  res.addRoot(dir);
  const Shape* loaded = res.shape("labtree.ft");
  CHECK(loaded && !loaded->meshes.empty() && !loaded->meshes[0].triangles.empty());
  std::filesystem::remove_all(dir);
  // The real 5.12 draws no .ft GameObject; the tree draws only when asked.
  {
    TestFrame f;
    Scene sc = cameraScene({0, 0, 0});
    sc.objects.push_back(objectAt("labtree.ft", {0, 6, -1}));
    CHECK(drawScene(f.frame(), sc, res).objectsDrawn == 0);
    gDrawFtTrees = true;
    CHECK(drawScene(f.frame(), sc, res).objectsDrawn == 1);
    gDrawFtTrees = false;
  }
}

void testLabels() {
  Resources res;
  res.putShape("red.3ds", cubeShape(1, 0, 0));
  Scene s = cameraScene({0, -5, 0});
  auto tagAt = [](const std::string& shape, V3 pos, const std::string& nick, const std::string& chat) {
    SceneTag t;
    t.shape = shape;
    t.transform = M4::translation(pos);
    t.nickname = nick;
    t.chat = chat;
    return t;
  };
  s.tags.push_back(tagAt("red.3ds", {0, 0, 0}, "Bob", "hi"));
  s.tags[0].ghost = 9;
  s.tags[0].color[0] = 10;
  s.tags.push_back(tagAt("", {2, 0, 0}, "Ann", ""));   // no shape: 2 m up
  s.tags.push_back(tagAt("", {0, -10, 0}, "Gone", ""));  // behind the camera
  s.tags.push_back(tagAt("", {-1, -1, 0}, "", "near"));  // chat only, nearer
  s.tags.push_back(tagAt("", {0, -4, 0}, "Up", ""));     // above the frame
  TestFrame f;
  const DrawStats st = drawScene(f.frame(), s, res);
  // 160 by 120 at 90 degrees: 80 pixels per unit at depth 1.
  CHECK(st.labels.size() == 4);
  if (st.labels.size() == 4) {
    // Farthest first: Bob, his chat and Ann at depth 5, the chat at depth 4.
    const Label& bob = st.labels[0];
    CHECK(bob.kind == Label::kNickname && bob.text == "Bob" && bob.ghost == 9 && bob.color[0] == 10);
    CHECK(std::fabs(bob.x - 80) < 0.01f && std::fabs(bob.y - 52) < 0.01f && std::fabs(bob.depth - 5) < 1e-4f);
    const Label& said = st.labels[1];
    CHECK(said.kind == Label::kChat && said.text == "hi" && std::fabs(said.y - 36) < 0.01f && said.color[0] == 255);
    const Label& ann = st.labels[2];
    CHECK(ann.text == "Ann" && std::fabs(ann.x - 112) < 0.01f && std::fabs(ann.y - 28) < 0.01f);
    const Label& near = st.labels[3];
    CHECK(near.kind == Label::kChat && near.text == "near" && std::fabs(near.x - 60) < 0.01f &&
          std::fabs(near.y - 20) < 0.01f);
  }
  // No camera: no labels.
  Scene dark = s;
  dark.hasCamera = false;
  CHECK(drawScene(f.frame(), dark, res).labels.empty());
}

void testBilinear() {
  // One black and one white texel side by side.
  Texture t;
  t.width = 2;
  t.height = 1;
  t.pixels = {packRgba(0, 0, 0), packRgba(255, 255, 255)};
  // Between the two texel centres: half way.
  CHECK(red(t.sampleBilinear(0.5f, 0.5f)) == 128 && alpha(t.sampleBilinear(0.5f, 0.5f)) == 255);
  // On a texel centre: that texel.
  CHECK(red(t.sampleBilinear(0.25f, 0.5f)) == 0 && red(t.sampleBilinear(0.75f, 0.5f)) == 255);
  // At the left edge: wrapping blends in the right texel; clamping does not.
  CHECK(red(t.sampleBilinear(0.0f, 0.5f)) == 128);
  CHECK(red(t.sampleBilinear(0.0f, 0.5f, true)) == 0);
  CHECK(red(t.sampleBilinear(1.0f, 0.5f, true)) == 255);
  // Repeats past 1 and below 0.
  CHECK(t.sampleBilinear(2.25f, 7.5f) == t.sampleBilinear(0.25f, 0.5f));
  CHECK(t.sampleBilinear(-0.75f, -3.5f) == t.sampleBilinear(0.25f, 0.5f));
  // Bad coordinates do not read outside the texture.
  t.sampleBilinear(std::nanf(""), 1e30f);
  t.sampleBilinear(-1e30f, std::numeric_limits<float>::infinity());
}

// Movement (lab E#505): list jumps onto each target; interpolate glides
// toward it over the time since the previous target.
void testMotion() {
  auto near = [](const V3& a, float x, float y, float z) {
    return std::fabs(a.x - x) < 1e-3f && std::fabs(a.y - y) < 1e-3f && std::fabs(a.z - z) < 1e-3f;
  };
  GhostTable ghosts;
  Ghost& g = ghosts[5];
  g.className = "GameObject";
  GameObjectState& o = g.object;
  o.shape = "box.3ds";
  o.position = {1, 2, 3};
  MotionTracker m;
  // No movetype: section 5.
  CHECK(near(m.position(5, o, 0), 1, 2, 3));
  o.movetype = "interpolate";
  o.hasMovement = o.hasMovementData = true;
  o.movement.position = {0, 10, 0};
  o.movementSerial = 1;
  CHECK(near(m.position(5, o, 0), 0, 10, 0));  // the first target: drawn there
  o.movement.position = {0, 10.5f, 0};
  o.movementSerial = 2;
  CHECK(near(m.position(5, o, 1.0), 0, 10, 0));  // a new target a second later
  CHECK(near(m.position(5, o, 1.5), 0, 10.25f, 0));
  CHECK(near(m.position(5, o, 2.0), 0, 10.5f, 0));
  CHECK(near(m.position(5, o, 9.0), 0, 10.5f, 0));
  // A target that comes mid-glide starts from where the object is drawn.
  o.movement.position = {0, 11, 0};
  o.movementSerial = 3;
  CHECK(near(m.position(5, o, 9.0), 0, 10.5f, 0));
  CHECK(near(m.position(5, o, 9.5), 0, 10.75f, 0));  // glide capped at 1 s
  // list: jumps.
  o.movetype = "list";
  o.movement.position = {4, 4, 4};
  o.movementSerial = 4;
  CHECK(near(m.position(5, o, 9.6), 4, 4, 4));
  // applyMotion moves the scene's object and tag; prune forgets gone ghosts.
  Scene scene;
  SceneObject so;
  so.ghost = 5;
  so.transform = M4::translation({1, 2, 3});
  scene.objects.push_back(so);
  SceneTag tag;
  tag.ghost = 5;
  tag.transform = so.transform;
  scene.tags.push_back(tag);
  applyMotion(scene, ghosts, m, 10);
  CHECK(near(scene.objects[0].transform.point({0, 0, 0}), 4, 4, 4));
  CHECK(near(scene.tags[0].transform.point({0, 0, 0}), 4, 4, 4));

  // Camera mode 1 looks at the control object (lab T3D-023); mode 0 keeps
  // the camera's own turn.
  Ghost& cg = ghosts[7];
  cg.className = "Camera";
  cg.camera.object.position = {4, 0, 4};
  Scene view;
  view.hasCamera = true;
  view.view.cameraToWorld = M4::translation({4, 0, 4});
  applyMotion(view, ghosts, m, 10, 7, 5);
  CHECK(near(view.view.cameraToWorld.vector({0, 1, 0}), 0, 1, 0));
  cg.camera.mode = 1;
  applyMotion(view, ghosts, m, 10, 7, 5);
  CHECK(near(view.view.cameraToWorld.vector({0, 1, 0}), 0, 1, 0));  // straight ahead at (4, 4, 4)
  CHECK(near(view.view.cameraToWorld.vector({1, 0, 0}), 1, 0, 0));
  ghosts[5].object.movetype = "";
  ghosts[5].object.hasMovement = false;
  ghosts[5].object.position = {4, 0, 0};  // below: looking straight down
  applyMotion(view, ghosts, m, 10, 7, 5);
  CHECK(near(view.view.cameraToWorld.vector({0, 1, 0}), 0, 0, -1));
  CHECK(near(view.view.cameraToWorld.point({0, 0, 0}), 4, 0, 4));

  ghosts.clear();
  applyMotion(scene, ghosts, m, 11);
  CHECK(m.size() == 0);
}

void testReplicators() {
  // The update after the GameObject part (terrain thread note, T3D-048).
  {
    BitWriter w;
    w.flag(true);
    for (float f : {10.f, 20.f, 30.f}) w.f32(f);
    for (float f : {0.f, 0.f, 0.f}) w.f32(f);
    w.flag(false);
    w.bits(0xFFFFFFFEu, 32);
    w.pstring("rock.3ds,bush.dts");
    w.bits(3, 8);
    w.bits(1, 8);
    w.bits(4, 8);
    for (int v : {-100, -200, 0}) { w.flag(v < 0); w.bits(uint32_t(std::abs(v)), 15); }
    for (int v : {100, 200, 50}) { w.flag(v < 0); w.bits(uint32_t(std::abs(v)), 15); }
    for (int i = 0; i < 12; ++i) w.f32(float(i));
    w.f32(-0.5f);
    for (bool b : {true, false, false, true, false}) w.flag(b);
    w.flag(false); w.bits(30, 7);
    w.flag(true);
    for (float f : {0.f, 0.f, 1.f}) w.f32(f);
    w.flag(false);
    w.flag(true); w.bits(2, 7);
    w.flag(true);
    const std::string bytes = w.bytes();
    BitReader r(bytes);
    ReplicatorState s;
    CHECK(readReplicatorUpdate(r, s));
    CHECK(s.init && s.position.x == 10 && s.position.z == 30 && s.rotation[3] == 1);
    CHECK(s.seed == -2 && s.shapeFiles == "rock.3ds,bush.dts");
    CHECK(s.radius == 3 && s.minObjects == 1 && s.maxObjects == 4);
    CHECK(s.boxMin[0] == -100 && s.boxMin[1] == -200 && s.boxMax[2] == 50);
    CHECK(s.scaleMin.x == 0 && s.scaleMax.x == 3 && s.rotateMax.z == 11 && s.offsetZ == -0.5f);
    CHECK(s.allowTerrain && !s.allowInteriors && s.allowWater && s.allowedSlope == 30);
    CHECK(s.alignToTerrain && s.terrainAlignment.z == 1 && !s.surfaceExclusion);
    CHECK(s.surfaceType == -2 && s.hide);
    BitWriter end;
    end.flag(false);
    const std::string eb = end.bytes();
    BitReader er(eb);
    ReplicatorState none;
    CHECK(readReplicatorUpdate(er, none) && !none.init);
  }
  // R250: one stream per seed; cell counts stay in [min, max].
  {
    R250 a(1234), b(1234), c(1235);
    bool differs = false;
    for (int i = 0; i < 600; ++i) {
      const uint32_t x = a.next();
      CHECK(x == b.next());
      differs |= x != c.next();
    }
    CHECK(differs);
    for (int i = 0; i < 100; ++i) {
      const float u = a.unit();
      CHECK(u >= 0 && u < 1);
    }
    int seen[5] = {};
    for (int cy = -20; cy < 20; ++cy)
      for (int cx = -20; cx < 20; ++cx) {
        const int n = replicatorCellCount(77, cx, cy, 1, 4);
        CHECK(n >= 1 && n <= 4);
        if (n >= 0 && n <= 4) ++seen[n];
        CHECK(n == replicatorCellCount(77, cx, cy, 1, 4));
      }
    CHECK(seen[0] == 0 && seen[1] && seen[2] && seen[3] && seen[4]);
    CHECK(replicatorCellCount(77, 3, 3, 2, 2) == 2);
    CHECK(replicatorCellCount(77, 3, 3, 5, 1) == 5);  // a larger minimum raises the maximum
    // Cells 256 apart share a seed (cx & 255, cy & 255).
    CHECK(replicatorCellCount(9, 4, 7, 0, 20) == replicatorCellCount(9, 260, 7, 0, 20));
  }
  // The height under a point, on the same triangles as the drawn terrain.
  Terrain t;
  t.present = true;
  for (int y = 0; y < kTerrainSize; ++y)
    for (int x = 0; x < kTerrainSize; ++x) t.heights[size_t(y) * kTerrainSize + size_t(x)] = 64;  // 2 m
  {
    float z = 0;
    V3 n;
    CHECK(terrainHeightAt(t, 3.3f, -7.1f, z, &n) && std::fabs(z - 2) < 1e-4f && std::fabs(n.z - 1) < 1e-5f);
    CHECK(!terrainHeightAt(t, 128 * 8 + 1, 0, z));
    Terrain slope = t;
    for (int y = 0; y < kTerrainSize; ++y)
      for (int x = 0; x < kTerrainSize; ++x) slope.heights[size_t(y) * kTerrainSize + size_t(x)] = uint16_t(x * 32);
    const float wx = (10.5f - 128) * 8, wy = (20.25f - 128) * 8;
    CHECK(terrainHeightAt(slope, wx, wy, z, &n) && std::fabs(z - 10.5f) < 1e-3f);
    CHECK(std::fabs(n.x + 0.124035f) < 1e-4f && std::fabs(n.y) < 1e-5f);
    slope.hole[size_t(20) * kTerrainSize + 10] = 1;
    CHECK(!terrainHeightAt(slope, wx, wy, z));
  }
  // Cover on 8-unit cells around the control object, inside the box.
  {
    Resources res;
    res.putShape("rock.3ds", cubeShape(1, 0, 0));
    GhostTable g;
    Ghost& d = g[5];
    d.className = "DynamicShapeReplicator";
    ReplicatorState& s = d.replicator;
    s.init = true;
    s.seed = 42;
    s.shapeFiles = "rock.3ds";
    s.radius = 1;
    s.minObjects = s.maxObjects = 2;
    s.boxMin[0] = s.boxMin[1] = -100;
    s.boxMax[0] = s.boxMax[1] = 100;
    s.boxMin[2] = -10;
    s.boxMax[2] = 10;
    s.scaleMin = s.scaleMax = {1, 1, 1};
    s.offsetZ = 0.5f;
    s.allowTerrain = true;
    Scene sc;
    CHECK(scatterReplicators(sc, g, t, {3, 11, 0}, res) == 18);  // 3 x 3 cells, 2 each
    {
      // No cover while the avatar's cell (cut toward zero) is (0, 0).
      Scene dead;
      CHECK(scatterReplicators(dead, g, t, {-4, -4, 0}, res) == 0);
      CHECK(scatterReplicators(dead, g, t, {7, 7, 0}, res) == 0);
      CHECK(scatterReplicators(dead, g, t, {9, 4, 0}, res) == 18);
      // The block centres on the cell rounded half up: (12, -12) is cell
      // (2, -1), so copies lie within 4 of corners x 8..24, y -16..0.
      Scene mid;
      CHECK(scatterReplicators(mid, g, t, {12, -12, 0}, res) == 18);
      for (const SceneObject& o : mid.objects) {
        CHECK(o.transform.m[0][3] >= 4 && o.transform.m[0][3] < 28);
        CHECK(o.transform.m[1][3] >= -20 && o.transform.m[1][3] < 4);
      }
    }
    CHECK(sc.objects.size() == 18);
    for (const SceneObject& o : sc.objects) {
      CHECK(o.ghost == -1 && o.shape == "rock.3ds");
      CHECK(std::fabs(o.transform.m[2][3] - 2.5f) < 1e-4f);
      CHECK(o.transform.m[0][3] >= -12 && o.transform.m[0][3] < 12);  // within 4 of a corner -8, 0 or 8
    }
    Scene again;
    scatterReplicators(again, g, t, {3, 11, 0}, res);
    CHECK(again.objects[7].transform.m[0][3] == sc.objects[7].transform.m[0][3]);
    // Lab 15 on the real 5.12 (seed 1, radius 1, 2 per cell, avatar at
    // 128, -128): every measured cube has a copy of ours within 0.5 m.
    {
      GhostTable lab = g;
      ReplicatorState& l = lab[5].replicator;
      l.seed = 1;
      l.boxMin[0] = l.boxMin[1] = -1024;
      l.boxMax[0] = l.boxMax[1] = 1024;
      l.boxMin[2] = -100;
      l.boxMax[2] = 100;
      Scene ls;
      CHECK(scatterReplicators(ls, lab, t, {128, -128, 0}, res) == 18);
      const float measured[][2] = {{119.62f, -137.28f}, {119.12f, -136.08f}, {130.76f, -136.18f},
                                   {124.89f, -133.10f}, {138.72f, -134.09f}, {133.84f, -137.48f},
                                   {124.00f, -125.44f}, {122.21f, -123.35f}, {124.10f, -129.02f},
                                   {129.57f, -124.24f}, {139.12f, -130.51f}, {136.63f, -123.65f},
                                   {120.81f, -124.94f}, {118.92f, -117.48f}, {125.39f, -123.75f},
                                   {130.96f, -121.86f}, {132.85f, -119.77f}};
      for (const auto& m : measured) {
        float best = 1e9f;
        for (const SceneObject& o : ls.objects)
          best = std::min(best, std::hypot(o.transform.m[0][3] - m[0], o.transform.m[1][3] - m[1]));
        CHECK(best < 0.5f);
      }
    }
    // A listed shape we cannot load is still picked, and not drawn.
    s.shapeFiles = "rock.3ds, missing.dts";
    Scene partial;
    const int some = scatterReplicators(partial, g, t, {3, 11, 0}, res);
    CHECK(some > 0 && some < 18);
    s.shapeFiles = "rock.3ds";
    s.boxMin[0] = 0;  // the cell at x -8 has its corner outside
    Scene boxed;
    CHECK(scatterReplicators(boxed, g, t, {3, 11, 0}, res) == 12);
    s.radius = 0;  // clamped to 1
    Scene clamped;
    CHECK(scatterReplicators(clamped, g, t, {3, 11, 0}, res) == 12);
    s.boxMax[2] = 1;  // the ground at z 2 is above the box
    Scene high;
    CHECK(scatterReplicators(high, g, t, {3, 11, 0}, res) == 0);
    s.boxMax[2] = 10;
    // A minimum above its maximum is swapped: scale 2..1 stays in 1..2.
    s.scaleMin = {2, 2, 2};
    s.scaleMax = {1, 1, 1};
    Scene swapped;
    scatterReplicators(swapped, g, t, {3, 11, 0}, res);
    for (const SceneObject& o : swapped.objects) {
      const float len = std::sqrt(o.transform.m[0][0] * o.transform.m[0][0] + o.transform.m[1][0] * o.transform.m[1][0] +
                                  o.transform.m[2][0] * o.transform.m[2][0]);
      CHECK(len >= 1 - 1e-4f && len <= 2 + 1e-4f);
    }
    s.scaleMin = s.scaleMax = {1, 1, 1};
    s.hide = true;
    Scene hidden;
    CHECK(scatterReplicators(hidden, g, t, {3, 11, 0}, res) == 0);
    s.hide = false;
    s.allowTerrain = false;
    CHECK(scatterReplicators(hidden, g, t, {3, 11, 0}, res) == 0);
    s.allowTerrain = true;
    s.shapeFiles = "missing.dts";
    CHECK(scatterReplicators(hidden, g, t, {3, 11, 0}, res) == 0);
    // The control object's place after motion: its object, else its tag.
    Scene where;
    where.objects.push_back(objectAt("rock.3ds", {4, 5, 6}));
    where.objects.back().ghost = 9;
    V3 at;
    CHECK(scenePositionOf(where, 9, at) && at.x == 4 && at.y == 5 && at.z == 6);
    CHECK(!scenePositionOf(where, 8, at) && !scenePositionOf(where, -1, at));
    // A shapeless control object is not in the scene: its ghost position.
    GhostTable shapeless;
    shapeless[8].className = "GameObject";
    shapeless[8].object.position = {128, -128, 3};
    CHECK(scenePositionOf(where, 8, at, &shapeless) && at.x == 128 && at.y == -128 && at.z == 3);
    CHECK(!scenePositionOf(where, 7, at, &shapeless));
    // Grass (Graal_analysis PR #931): flat pieces over the same cells, a
    // texture named in shapefiles, counts up to 100, one owned shape.
    for (const char* cls : {"DynamicGrassReplicator", "DynamicGrass"}) {
      d.className = cls;
      s.shapeFiles = "grass.png";
      s.boxMin[0] = -100;
      s.radius = 1;
      s.minObjects = s.maxObjects = 50;
      Scene gs;
      CHECK(scatterReplicators(gs, g, t, {3, 11, 0}, res) == 441);  // 9 cells, 7 x 7 of 50 each
      CHECK(gs.objects.size() == 1 && gs.owned.size() == 1 && gs.objects[0].direct == gs.owned[0].get());
      const Shape& gshape = *gs.owned[0];
      CHECK(gshape.materials.size() == 1 && gshape.materials[0].texture == "grass.png");
      CHECK(gshape.meshes.size() == 1 && gshape.meshes[0].triangles.size() == 882);
      // Flat cards on the ground (z 2 + offset 0.5 + lift), 0.6 across.
      for (const Vertex& v : gshape.meshes[0].vertices) CHECK(std::fabs(v.position.z - 2.52f) < 1e-3f);
      {
        const auto& v = gshape.meshes[0].vertices;
        const float dx = v[1].position.x - v[0].position.x, dy = v[1].position.y - v[0].position.y;
        CHECK(std::fabs(std::sqrt(dx * dx + dy * dy) - 0.6f) < 1e-3f);
      }
      CHECK(gshape.boundsMax.x - gshape.boundsMin.x < 26);
      s.minObjects = s.maxObjects = 250;  // clamped to 100
      Scene many;
      CHECK(scatterReplicators(many, g, t, {3, 11, 0}, res) == 900);  // clamped to 100: 10 x 10
      s.minObjects = s.maxObjects = 5;  // 2 x 2
      Scene five;
      CHECK(scatterReplicators(five, g, t, {3, 11, 0}, res) == 36);
      // The sub-grid: piece k of a cell at (k % cols / cols - 0.5) * 8.
      const auto& fv = five.owned[0]->meshes[0].vertices;
      float centreX = 0, centreY = 0;
      for (int c = 0; c < 4; ++c) { centreX += fv[size_t(c)].position.x / 4; centreY += fv[size_t(c)].position.y / 4; }
      CHECK(std::fabs(centreX - -12) < 1e-3f && std::fabs(centreY - -4) < 1e-3f);  // cell (-1, 0), piece 0
      s.minObjects = s.maxObjects = 250;
      Scene again2;
      scatterReplicators(again2, g, t, {3, 11, 0}, res);
      CHECK(again2.owned[0]->meshes[0].vertices[123].position.x == many.owned[0]->meshes[0].vertices[123].position.x);
      s.minObjects = s.maxObjects = 0;
      Scene none2;
      CHECK(scatterReplicators(none2, g, t, {3, 11, 0}, res) == 0 && none2.objects.empty());
    }
    CHECK(replicatorCellCount(77, 3, 3, 150, 150, kMaxGrassCount) == 100);
    // Two shapes in the list: each copy picks one.
    d.className = "DynamicShapeReplicator";
    res.putShape("bush.3ds", cubeShape(0, 1, 0));
    s.shapeFiles = "rock.3ds,bush.3ds";
    s.minObjects = s.maxObjects = 10;
    Scene two;
    CHECK(scatterReplicators(two, g, t, {3, 11, 0}, res) == 90);
    int rocks = 0;
    for (const SceneObject& o : two.objects) rocks += o.shape == "rock.3ds";
    CHECK(rocks > 0 && rocks < 90);
  }
}

int main() {
  testRead3ds();
  testMotion();
  testRotationRule();
  testDrawObjects();
  testSunAndFog();
  testSkyBox();
  testSceneFromGhosts();
  testResources();
  testReadDts();
  testReadDif();
  testBilinear();
  testLabels();
  testFtTrees();
  testStreamedTerrain();
  testTerrain();
  testClientImageFormats();
  testReplicators();
  if (failures) {
    std::fprintf(stderr, "render-test: %d failure(s)\n", failures);
    return 1;
  }
  std::printf("render-test: ok\n");
  return 0;
}
