#include "bench.hpp"

#include "../../common/cpp/graal3dengine/render/terrain.hpp"
#include "../../common/torque/gui/image.hpp"

#include <zlib.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <random>

namespace Frank {

namespace R = graal3d::render;
using Torque::Gui::Color;
using Torque::Gui::Image;

namespace {

// ------------------------------------------------ content (gen_content.py)

const uint8_t kRed[3] = {220, 0, 0}, kGreen[3] = {0, 200, 0}, kMagenta[3] = {255, 0, 255},
              kTan[3] = {200, 160, 90}, kWater[3] = {20, 40, 160}, kWhite[3] = {255, 255, 255};
const uint8_t kSky[6][3] = {{255, 128, 0}, {0, 160, 255}, {255, 255, 0}, {0, 255, 160}, {160, 0, 255}, {90, 60, 30}};

void put16(std::string& s, unsigned v) {
  s += char(v & 0xFF);
  s += char((v >> 8) & 0xFF);
}
void put32(std::string& s, uint32_t v) {
  for (int i = 0; i < 4; ++i) s += char((v >> (8 * i)) & 0xFF);
}
void putf(std::string& s, float f) {
  uint32_t v;
  std::memcpy(&v, &f, 4);
  put32(s, v);
}
std::string chunk3ds(unsigned id, const std::string& body) {
  std::string s;
  put16(s, id);
  put32(s, uint32_t(body.size() + 6));
  return s + body;
}

// gen_content.cube_3ds: a unit cube centred on the origin, optionally with
// one material (diffuse colour, texture) on every face.
std::string cube3ds(const char* material, const uint8_t colour[3], const char* texture) {
  static const float V[8][3] = {{-0.5f, -0.5f, -0.5f}, {0.5f, -0.5f, -0.5f}, {0.5f, 0.5f, -0.5f}, {-0.5f, 0.5f, -0.5f},
                                {-0.5f, -0.5f, 0.5f},  {0.5f, -0.5f, 0.5f},  {0.5f, 0.5f, 0.5f},  {-0.5f, 0.5f, 0.5f}};
  static const int F[12][3] = {{0, 2, 1}, {0, 3, 2}, {4, 5, 6}, {4, 6, 7}, {0, 1, 5}, {0, 5, 4},
                               {1, 2, 6}, {1, 6, 5}, {2, 3, 7}, {2, 7, 6}, {3, 0, 4}, {3, 4, 7}};
  static const float UV[8][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}, {0, 0}, {1, 0}, {1, 1}, {0, 1}};
  std::string editor;
  if (material) {
    std::string mat = chunk3ds(0xA000, std::string(material) + '\0');
    mat += chunk3ds(0xA020, chunk3ds(0x0011, std::string(reinterpret_cast<const char*>(colour), 3)));
    if (texture) mat += chunk3ds(0xA200, chunk3ds(0xA300, std::string(texture) + '\0'));
    editor += chunk3ds(0xAFFF, mat);
  }
  std::string verts;
  put16(verts, 8);
  for (const auto& v : V)
    for (float f : v) putf(verts, f);
  std::string mesh = chunk3ds(0x4110, verts);
  if (texture) {
    std::string uv;
    put16(uv, 8);
    for (const auto& t : UV)
      for (float f : t) putf(uv, f);
    mesh += chunk3ds(0x4140, uv);
  }
  std::string faces;
  put16(faces, 12);
  for (const auto& f : F) {
    put16(faces, unsigned(f[0]));
    put16(faces, unsigned(f[1]));
    put16(faces, unsigned(f[2]));
    put16(faces, 7);
  }
  if (material) {
    std::string group = std::string(material) + '\0';
    put16(group, 12);
    for (unsigned i = 0; i < 12; ++i) put16(group, i);
    faces += chunk3ds(0x4130, group);
  }
  mesh += chunk3ds(0x4120, faces);
  std::string version;
  put32(version, 3);
  editor += chunk3ds(0x3D3E, version);
  editor += chunk3ds(0x4000, std::string("conf_cube") + '\0' + chunk3ds(0x4100, mesh));
  return chunk3ds(0x4D4D, chunk3ds(0x0002, version) + chunk3ds(0x3D3D, editor));
}

std::vector<uint8_t> solid_png(int w, int h, const uint8_t rgb[3]) {
  return Torque::Gui::encode_png(Image(w, h, Color{rgb[0], rgb[1], rgb[2], 255}));
}

// --------------------------------------------------------------- worlds

graal3d::Ghost& add(BenchWorld& w, int id, const char* cls) {
  graal3d::Ghost& g = w.ghosts[id];
  g.className = cls;
  g.updates = 1;
  return g;
}

void object(BenchWorld& w, int id, const char* shape, float x, float y, float z) {
  graal3d::Ghost& g = add(w, id, "GameObject");
  g.object.name = "Obj" + std::to_string(id);
  g.object.shape = shape;
  g.object.position = {x, y, z};
  g.object.hasTransform = true;
}

// Every world: the cases' Sun and Sky lines, the player's object (a cube
// with no material, not drawn) at the spawn, and a camera behind it.
void base(BenchWorld& w, float sx, float sy, float sz, float back, float up, float pitch) {
  graal3d::Ghost& sun = add(w, 1, "Sun");
  sun.sun.init = true;
  sun.sun.name = "Sun";
  sun.sun.direction = {0.57735f, 0.57735f, -0.57735f};
  for (int i = 0; i < 3; ++i) sun.sun.color[i] = 0.8f;
  sun.sun.color[3] = 1;
  sun.sun.ambient[0] = sun.sun.ambient[1] = 0.3f;
  sun.sun.ambient[2] = 0.35f;
  sun.sun.ambient[3] = 1;
  graal3d::Ghost& sky = add(w, 2, "Sky");
  sky.sky.init = true;
  sky.sky.name = "Sky";
  sky.sky.textures = "conf_sky0,conf_sky1,conf_sky2,conf_sky3,conf_sky4,conf_sky5";
  sky.sky.visibleDistance = 500;
  sky.sky.options[0] = 1;
  sky.sky.solidColor = {0.4f, 0.6f, 0.9f};
  object(w, 3, "conf_nomat.3ds", sx, sy, sz);
  w.control = 3;
  graal3d::Ghost& cam = add(w, 4, "Camera");
  cam.camera.object.name = "Camera";
  cam.camera.object.position = {sx, sy - back, sz + up};
  cam.camera.object.axis = {1, 0, 0};
  cam.camera.object.angle = pitch;  // positive tilts the view down
  w.camera = 4;
}

void flat_terrain(BenchWorld& w) {
  graal3d::Ghost& t = add(w, 5, "TerrainBlock");
  t.terrain.init = true;
  t.terrain.name = "Terrain";
  t.terrain.squareSize = 8;
  // gen_content.flat_terrain: 256 flat chunks at height 0, material 0
  // (heights.info: conf_ground.png), sent as the session's chunks.
  R::Terrain flat;
  for (int cy = 0; cy < R::kTerrainChunks; ++cy)
    for (int cx = 0; cx < R::kTerrainChunks; ++cx) {
      const std::vector<uint8_t> plain = R::encodeTerrainChunk(flat, cx, cy);
      uLongf n = compressBound(uLong(plain.size()));
      std::string z(n, '\0');
      compress2(reinterpret_cast<Bytef*>(z.data()), &n, plain.data(), uLong(plain.size()), 9);
      z.resize(n);
      w.chunks[cy * R::kTerrainChunks + cx] = z;
    }
  w.chunkCount = int(w.chunks.size());
}

void water(BenchWorld& w) {
  graal3d::Ghost& g = add(w, 6, "WaterBlock");
  g.water.init = true;
  g.water.name = "Water";
  g.water.position = {-1024, -1024, -19.5f};
  g.water.scale = {2048, 2048, 20};
  g.water.textures[0] = "conf_water";
  g.water.opacity = 0.6f;  // the bench's own: the case line does not set it
}

void grass(BenchWorld& w, int id, float x, float y) {
  graal3d::Ghost& d = add(w, id, "DynamicGrass");
  d.object.name = "Grass";
  d.object.position = {x, y, 0};
  graal3d::ReplicatorState& s = d.replicator;
  s.init = true;
  s.position = {x, y, 0};
  s.seed = 1;
  s.shapeFiles = "conf_grass.png";
  s.radius = 4;
  s.minObjects = 40;
  s.maxObjects = 60;
  for (int i = 0; i < 2; ++i) {
    s.boxMin[i] = -1024;
    s.boxMax[i] = 1024;
  }
  s.boxMin[2] = -32767;
  s.boxMax[2] = 32767;
  s.allowTerrain = true;
  s.allowedSlope = 90;
}

void dense(BenchWorld& w) {
  // C024: a 32 x 32 grid of red cubes, 2.5 apart, at z 1.
  int id = 100;
  for (int j = 0; j < 32; ++j)
    for (int i = 0; i < 32; ++i) object(w, id++, "conf_red.3ds", i * 2.5f, j * 2.5f, 1);
}

}  // namespace

std::vector<std::string> bench_world_names() {
  return {"sky", "cube", "texture", "terrain", "water", "dense", "grass", "mix"};
}

bool make_bench_world(const std::string& name, BenchWorld& w) {
  w = BenchWorld();
  w.name = name;
  if (name == "sky") {
    w.title = "C004 sky faces";
    base(w, 0, 0, 1, 6, 1.5f, 0.1f);
  } else if (name == "cube") {
    w.title = "C005 red cube";
    base(w, 0, -3, 1, 6, 1.5f, 0.1f);
    object(w, 10, "conf_red.3ds", 0, 0, 1);
  } else if (name == "texture") {
    w.title = "C006 textured cube";
    base(w, 0, -3, 1, 6, 1.5f, 0.1f);
    object(w, 10, "conf_tex.3ds", 0, 0, 1);
  } else if (name == "terrain") {
    w.title = "C018 flat streamed terrain";
    base(w, 0, 0, 1, 6, 2.5f, 0.25f);
    flat_terrain(w);
  } else if (name == "water") {
    w.title = "C019 water";
    base(w, 0, 0, 1, 6, 2.5f, 0.25f);
    water(w);
  } else if (name == "dense") {
    w.title = "C024 1024 cubes";
    base(w, 38.75f, -10, 1, 10, 20, 0.45f);
    dense(w);
  } else if (name == "grass") {
    w.title = "C035 grass on terrain";
    base(w, 20, 20, 1, 8, 3, 0.3f);
    flat_terrain(w);
    grass(w, 7, 20, 20);
  } else if (name == "mix") {
    w.title = "terrain, grass, water and 1024 cubes";
    base(w, 20, 20, 1, 12, 6, 0.3f);
    flat_terrain(w);
    water(w);
    grass(w, 7, 20, 20);
    dense(w);
  } else {
    return false;
  }
  return true;
}

bool write_bench_content(const std::string& dir, std::string& error) {
  namespace fs = std::filesystem;
  std::error_code ec;
  fs::create_directories(dir, ec);
  auto put = [&](const std::string& name, const std::string& bytes) {
    std::ofstream f(fs::path(dir) / name, std::ios::binary | std::ios::trunc);
    f.write(bytes.data(), std::streamsize(bytes.size()));
    if (!f) {
      error = "could not write " + name + " in " + dir;
      return false;
    }
    return true;
  };
  auto png = [&](const std::string& name, int w, int h, const uint8_t rgb[3]) {
    const std::vector<uint8_t> b = solid_png(w, h, rgb);
    return put(name, std::string(b.begin(), b.end()));
  };
  bool ok = put("conf_red.3ds", cube3ds("conf_red", kRed, nullptr)) &&
            put("conf_nomat.3ds", cube3ds(nullptr, kRed, nullptr)) &&
            put("conf_tex.3ds", cube3ds("conf_texmat", kWhite, "conf_tex.png")) &&
            png("conf_tex.png", 256, 256, kGreen) && png("conf_ground.png", 256, 256, kTan) &&
            png("conf_water.png", 64, 64, kWater) && png("conf_grass.png", 256, 256, kMagenta) &&
            put("heights.info", "conf_ground.png\n");
  for (int i = 0; ok && i < 6; ++i) ok = png("conf_sky" + std::to_string(i) + ".png", 64, 64, kSky[i]);
  return ok;
}

std::vector<ColourShare> colour_shares(const Image& frame) {
  std::vector<ColourShare> out = {
      {"red", {kRed[0], kRed[1], kRed[2]}},           {"green", {kGreen[0], kGreen[1], kGreen[2]}},
      {"tan", {kTan[0], kTan[1], kTan[2]}},           {"water", {kWater[0], kWater[1], kWater[2]}},
      {"magenta", {kMagenta[0], kMagenta[1], kMagenta[2]}}, {"sky0", {kSky[0][0], kSky[0][1], kSky[0][2]}},
      {"sky1", {kSky[1][0], kSky[1][1], kSky[1][2]}}, {"sky2", {kSky[2][0], kSky[2][1], kSky[2][2]}},
      {"sky3", {kSky[3][0], kSky[3][1], kSky[3][2]}}, {"sky4", {kSky[4][0], kSky[4][1], kSky[4][2]}},
  };
  if (frame.pixels.empty()) return out;
  for (ColourShare& c : out) {
    size_t n = 0;
    for (const Color& p : frame.pixels)
      if (std::abs(p.r - c.rgb[0]) <= 24 && std::abs(p.g - c.rgb[1]) <= 24 && std::abs(p.b - c.rgb[2]) <= 24) ++n;
    c.share = double(n) / double(frame.pixels.size());
  }
  return out;
}

FrameDiff diff_frames(const Image& a, const Image& b) {
  FrameDiff d;
  if (a.width != b.width || a.height != b.height || a.pixels.empty()) {
    d.mismatched = 1;
    d.largest = 255;
    return d;
  }
  size_t n = 0;
  for (size_t i = 0; i < a.pixels.size(); ++i) {
    const Color& p = a.pixels[i];
    const Color& q = b.pixels[i];
    const int m = std::max({std::abs(p.r - q.r), std::abs(p.g - q.g), std::abs(p.b - q.b)});
    if (m > 24) ++n;
    d.largest = std::max(d.largest, m);
  }
  d.mismatched = double(n) / double(a.pixels.size());
  return d;
}

namespace {

double now_s() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

struct Timing {
  int frames = 0;
  double seconds = 0, mean = 0, p50 = 0, p95 = 0;
  long triangles = 0;
};

// Draws `w` for `seconds` (at least 3 frames), the way the client draws a
// 3D frame (scene, terrain, cover, render, tags). `out` is the last frame.
Timing time_world(const BenchWorld& w, World3D& world, int width, int height, int seconds, Image& out) {
  Timing t;
  out = Image(width, height);
  View3DStats st;
  // One frame first: shapes and textures load, the terrain is built, the
  // GPU copies are made.
  draw_world3d(out, w.ghosts, w.camera, w.control, 0, w.chunks, w.chunkCount, world, 0, &st);
  std::vector<double> ms;
  const double start = now_s();
  while (true) {
    const double t0 = now_s();
    draw_world3d(out, w.ghosts, w.camera, w.control, 0, w.chunks, w.chunkCount, world, t0 - start, &st);
    const double t1 = now_s();
    ms.push_back((t1 - t0) * 1000.0);
    if (t1 - start >= seconds && ms.size() >= 3) break;
  }
  t.seconds = now_s() - start;
  t.frames = int(ms.size());
  t.triangles = st.triangles;
  double sum = 0;
  for (double v : ms) sum += v;
  t.mean = sum / double(ms.size());
  std::sort(ms.begin(), ms.end());
  t.p50 = ms[ms.size() / 2];
  t.p95 = ms[std::min(ms.size() - 1, size_t(0.95 * double(ms.size() - 1) + 0.5))];
  return t;
}

}  // namespace

int run_bench(const BenchOptions& o) {
  std::vector<std::string> names;
  if (o.world == "all") names = bench_world_names();
  else names.push_back(o.world);
  for (const auto& n : names) {
    BenchWorld probe;
    if (!make_bench_world(n, probe)) {
      std::fprintf(stderr, "no bench world %s (worlds: all", n.c_str());
      for (const auto& k : bench_world_names()) std::fprintf(stderr, " %s", k.c_str());
      std::fprintf(stderr, ")\n");
      return 2;
    }
  }
  namespace fs = std::filesystem;
  std::error_code ec;
  const fs::path dir = fs::temp_directory_path(ec) /
                       ("frankenstein-bench-" + std::to_string(std::random_device{}() & 0xFFFFFF));
  std::string error;
  if (!write_bench_content(dir.string(), error)) {
    std::fprintf(stderr, "%s\n", error.c_str());
    return 1;
  }
  std::string note;
  std::unique_ptr<SceneRenderer> renderer = make_renderer(o.renderer, note);
  std::printf("%s\n", note.c_str());
  if (!renderer) {
    fs::remove_all(dir, ec);
    return 1;
  }
  std::printf("bench: %d x %d, %d s a world, %s\n", o.width, o.height, o.seconds, renderer->description().c_str());
  int status = 0;
  for (const auto& n : names) {
    BenchWorld w;
    make_bench_world(n, w);
    World3D world;
    world.roots = {dir.string()};
    world.renderer = std::move(renderer);
    Image frame;
    const Timing t = time_world(w, world, o.width, o.height, o.seconds, frame);
    std::printf("bench %-8s %-8s %6d frames %7.1f fps  mean %7.2f ms  p50 %7.2f ms  p95 %7.2f ms  %ld triangles  (%s)\n",
                n.c_str(), world.renderer->name(), t.frames, t.frames / t.seconds, t.mean, t.p50, t.p95, t.triangles,
                w.title.c_str());
    if (!o.shot_dir.empty()) {
      fs::create_directories(o.shot_dir, ec);
      Torque::Gui::write_file((fs::path(o.shot_dir) / (n + "-" + world.renderer->name() + ".png")).string(),
                              Torque::Gui::encode_png(frame), error);
    }
    if (o.compare && std::string(world.renderer->name()) != "software") {
      World3D sw;
      sw.roots = {dir.string()};
      sw.renderer = make_software_renderer();
      Image ref;
      const Timing ts = time_world(w, sw, o.width, o.height, 1, ref);
      // The two frames are compared at the same moment of the water's waves.
      Image a(o.width, o.height), b(o.width, o.height);
      draw_world3d(a, w.ghosts, w.camera, w.control, 0, w.chunks, w.chunkCount, world, 0);
      draw_world3d(b, w.ghosts, w.camera, w.control, 0, w.chunks, w.chunkCount, sw, 0);
      const FrameDiff d = diff_frames(a, b);
      std::printf("compare  %-8s software %6.1f fps, %.2f%% of pixels apart (largest %d)", n.c_str(),
                  ts.frames / ts.seconds, d.mismatched * 100.0, d.largest);
      const auto ca = colour_shares(a), cb = colour_shares(b);
      for (size_t i = 0; i < ca.size(); ++i)
        if (ca[i].share > 0.0005 || cb[i].share > 0.0005)
          std::printf("  %s %.2f%%/%.2f%%", ca[i].name, ca[i].share * 100.0, cb[i].share * 100.0);
      std::printf("\n");
      if (!o.shot_dir.empty())
        Torque::Gui::write_file((fs::path(o.shot_dir) / (n + "-software.png")).string(),
                                Torque::Gui::encode_png(b), error);
    }
    renderer = std::move(world.renderer);
  }
  fs::remove_all(dir, ec);
  return status;
}

}  // namespace Frank
