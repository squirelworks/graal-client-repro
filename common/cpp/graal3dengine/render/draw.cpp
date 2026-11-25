#include "draw.hpp"

#include <algorithm>
#include <cmath>

namespace graal3d::render {

namespace {

const V3 kFixedLight = normalize(V3{-1, -1, 1});

uint32_t colorOf(const float c[3]) {
  auto b = [](float x) { return uint32_t(x <= 0 ? 0 : (x >= 1 ? 255 : x * 255.0f + 0.5f)); };
  return packRgba(b(c[0]), b(c[1]), b(c[2]));
}

void drawSkyBox(Rasterizer& r, const Scene& scene, Resources& res, float farPlane, uint32_t fogColor) {
  const V3 eye{scene.view.cameraToWorld.m[0][3], scene.view.cameraToWorld.m[1][3], scene.view.cameraToWorld.m[2][3]};
  const float s = farPlane * 0.5f;
  const SkyBox& sky = scene.sky;
  RasterState st;
  st.depthTest = false;
  st.depthWrite = false;
  st.clampTexture = true;
  st.fogColor = fogColor;
  // The face a sky entry draws on (T3D-046): its outward direction, and
  // the direction of the image's left edge as seen from inside. The side
  // faces draw mirrored, so their left edge is on the viewer's right.
  struct Side {
    V3 out, left;
  };
  const Side sides[4] = {
      {{0, -1, 0}, {-1, 0, 0}},  // entry 0, -y (viewer's right is -x)
      {{1, 0, 0}, {0, -1, 0}},   // entry 1, +x
      {{0, 1, 0}, {1, 0, 0}},    // entry 2, +y
      {{-1, 0, 0}, {0, 1, 0}},   // entry 3, -x
  };
  auto faceState = [&](int entry) -> bool {
    if (!sky.useTextures) {
      st.texture = nullptr;
      for (int j = 0; j < 3; ++j) st.color[j] = sky.solidColor[j];
      return true;
    }
    st.texture = res.texture(sky.textures[entry]);
    for (int j = 0; j < 3; ++j) st.color[j] = 1;
    return st.texture != nullptr;
  };
  // Sides: only the half above the horizon (below it stays the clear
  // colour, the fog colour). The lowest band fades from the fog colour at the
  // horizon into the image (band height: the rebuild's own).
  const float band = s * kSkyFogBand;
  for (int f = 0; f < 4; ++f) {
    if (!faceState(f)) continue;
    const V3 c = sides[f].out * s, l = sides[f].left * s;
    const float zs[3] = {s, band, 0};
    for (int k = 0; k < 2; ++k) {
      RasterVertex q[4];
      const float z0 = zs[k], z1 = zs[k + 1];
      const V3 pos[4] = {c + l + V3{0, 0, z0}, c - l + V3{0, 0, z0}, c - l + V3{0, 0, z1}, c + l + V3{0, 0, z1}};
      const float zz[4] = {z0, z0, z1, z1};
      for (int i = 0; i < 4; ++i) {
        q[i].position = eye + pos[i];
        q[i].u = (i == 0 || i == 3) ? 0.0f : 1.0f;
        q[i].v = 0.5f - zz[i] / s * 0.5f;
        q[i].fog = zz[i] >= band ? 0.0f : 1.0f - zz[i] / band;
      }
      r.drawTriangle(q[0], q[1], q[2], st);
      r.drawTriangle(q[0], q[2], q[3], st);
    }
  }
  // Up (entry 4), its image's top toward +y. Entry 5, the floor, only
  // when the Sky asks for it (its orientation is the rebuild's own).
  for (int f = 4; f < 6; ++f) {
    if (f == 5 && !sky.drawBottom) break;
    if (!faceState(f)) continue;
    const float z = f == 4 ? s : -s;
    const V3 up[4] = {{-s, s, z}, {s, s, z}, {s, -s, z}, {-s, -s, z}};
    const float uv[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
    RasterVertex q[4];
    for (int i = 0; i < 4; ++i) {
      q[i].position = eye + up[i];
      q[i].u = uv[i][0];
      q[i].v = uv[i][1];
    }
    r.drawTriangle(q[0], q[1], q[2], st);
    r.drawTriangle(q[0], q[2], q[3], st);
  }
}

}  // namespace

DrawStats drawScene(Frame frame, const Scene& scene, Resources& res) {
  DrawStats stats;
  Rasterizer r(frame);
  if (!scene.hasCamera) {
    r.clear(packRgba(0, 0, 0));
    return stats;
  }
  View view = scene.view;
  // The 5.12 never fogs or distance-clips objects; the Sky's visible
  // distance changed nothing in the lab (Mesa, fog run).
  const float farPlane = kFarPlane;
  view.farPlane = farPlane;
  r.setView(view);
  const uint32_t fogColor = scene.sky.present ? colorOf(scene.sky.fogColor) : packRgba(0, 0, 0);
  // Below the horizon is the fog colour (T3D-046 under Mesa; the black
  // seen under GDI Generic 1.1 was that driver's).
  r.clear(fogColor);
  if (scene.sky.present) drawSkyBox(r, scene, res, farPlane, fogColor);
  r.clearDepth();

  const V3 eye{view.cameraToWorld.m[0][3], view.cameraToWorld.m[1][3], view.cameraToWorld.m[2][3]};

  for (const SceneObject& obj : scene.objects) {
    const Shape* shape = obj.direct ? obj.direct : res.shape(obj.shape);
    if (!shape) {
      ++stats.objectsMissing;
      continue;
    }
    if (shape->kind == Shape::kFt && !gDrawFtTrees) continue;
    ++stats.objectsDrawn;
    for (const Mesh& mesh : shape->meshes) {
      // World-space vertices, lit and fogged once per vertex.
      std::vector<RasterVertex> vs(mesh.vertices.size());
      for (size_t i = 0; i < vs.size(); ++i) {
        const Vertex& mv = mesh.vertices[i];
        RasterVertex& rv = vs[i];
        rv.position = obj.transform.point(mv.position);
        rv.u = mv.u;
        rv.v = mv.v;
        // draw.hpp: the 5.12's lighting by kind of shape.
        float light = 1;
        if (shape->kind == Shape::k3ds) {
          const V3 n = normalize(obj.transform.vector(mv.normal));
          light = scene.sun.present ? std::min(1.0f, kFixedLightFloor + std::max(0.0f, dot(n, kFixedLight)))
                                    : kNoSunLight;
        } else if (!scene.sun.present && (shape->kind == Shape::kDts || shape->kind == Shape::kDif)) {
          light = 0;
        }
        for (float& l : rv.light) l = light;
      }
      for (const Triangle& t : mesh.triangles) {
        if (t.material < 0 || size_t(t.material) >= shape->materials.size()) continue;  // not drawn (read_3ds.hpp)
        const Material& m = shape->materials[t.material];
        RasterState st;
        st.fogColor = fogColor;
        st.texture = m.texture.empty() ? nullptr : res.texture(m.texture);
        // A terrain texture must be 256 by 256, or the 5.12 logs "Terrain
        // texture of bad format" and uses its default (terrain-512.md
        // section 4; drawn white here).
        if (st.texture && shape->kind == Shape::kTerrain && (st.texture->width != 256 || st.texture->height != 256))
          st.texture = nullptr;
        st.alphaTest = m.alphaTest;
        // A material with no texture draws its colour. One whose texture is
        // missing or not drawable draws white, as the 5.12 does (T3D-032).
        if (!st.texture && m.texture.empty())
          for (int j = 0; j < 3; ++j) st.color[j] = m.color[j];
        r.drawTriangle(vs[t.v[0]], vs[t.v[1]], vs[t.v[2]], st);
        ++stats.triangles;
      }
    }
  }

  // Water last, blended over what is beneath (the rebuild's own: a flat,
  // unlit surface, its texture repeating every 16 m).
  for (const WaterSurface& w : scene.water) {
    RasterState st;
    st.fogColor = fogColor;
    st.texture = w.texture.empty() ? nullptr : res.texture(w.texture);
    st.alphaTest = false;
    st.depthWrite = false;
    st.opacity = w.opacity;
    // A grid of cells about 8 m a side (at most 64 by 64), so the waves
    // can bend the surface; a calm block is one cell.
    const bool calm = !(w.waveMagnitude > 0);
    const int nx = calm ? 1 : std::clamp(int(std::ceil(w.width / 8.0f)), 1, 64);
    const int ny = calm ? 1 : std::clamp(int(std::ceil(w.depth / 8.0f)), 1, 64);
    std::vector<RasterVertex> grid(size_t(nx + 1) * (ny + 1));
    for (int j = 0; j <= ny; ++j)
      for (int i = 0; i <= nx; ++i) {
        const float bx = w.width * i / nx, by = w.depth * j / ny;
        RasterVertex& v = grid[size_t(j) * (nx + 1) + i];
        v.position = w.transform.point({bx, by, 0});
        v.position.z += waveHeight(w.waveMagnitude, scene.time, v.position.x, v.position.y);
        v.u = bx / 16.0f;
        v.v = by / 16.0f;
      }
    for (int j = 0; j < ny; ++j)
      for (int i = 0; i < nx; ++i) {
        const RasterVertex& a = grid[size_t(j) * (nx + 1) + i];
        const RasterVertex& b = grid[size_t(j) * (nx + 1) + i + 1];
        const RasterVertex& c = grid[size_t(j + 1) * (nx + 1) + i + 1];
        const RasterVertex& d = grid[size_t(j + 1) * (nx + 1) + i];
        r.drawTriangle(a, b, c, st);
        r.drawTriangle(a, c, d, st);
        stats.triangles += 2;
      }
  }
  stats.labels = sceneLabels(scene, res, frame.width, frame.height);
  return stats;
}

std::vector<Label> sceneLabels(const Scene& scene, Resources& res, int width, int height) {
  std::vector<Label> out;
  if (!scene.hasCamera || width <= 0 || height <= 0) return out;
  View view = scene.view;
  view.farPlane = kFarPlane;
  constexpr float kLineHeight = 16;  // pixels between the nickname and chat lines
  for (const SceneTag& tag : scene.tags) {
    V3 anchor = tag.transform.point({0, 0, 2});
    if (const Shape* shape = tag.shape.empty() ? nullptr : res.shape(tag.shape)) {
      // The top centre of the shape's bounds, turned with the object; the
      // highest of the top corners carries the height.
      const V3 lo = shape->boundsMin, hi = shape->boundsMax;
      anchor = tag.transform.point({(lo.x + hi.x) * 0.5f, (lo.y + hi.y) * 0.5f, hi.z});
      for (int i = 0; i < 4; ++i) {
        const V3 c = tag.transform.point({i & 1 ? hi.x : lo.x, i & 2 ? hi.y : lo.y, hi.z});
        if (c.z > anchor.z) anchor.z = c.z;
      }
    }
    float sx, sy, depth;
    if (!projectPoint(view, width, height, anchor, sx, sy, depth) || depth > view.farPlane) continue;
    if (sx < 0 || sx >= width || sy < 0 || sy >= height) continue;
    Label nick;
    nick.ghost = tag.ghost;
    nick.x = sx;
    nick.y = sy;
    nick.depth = depth;
    for (int i = 0; i < 4; ++i) nick.color[i] = tag.color[i];
    if (!tag.nickname.empty()) {
      nick.text = tag.nickname;
      out.push_back(nick);
    }
    if (!tag.chat.empty()) {
      Label chat = nick;
      chat.kind = Label::kChat;
      chat.text = tag.chat;
      chat.y = sy - (tag.nickname.empty() ? 0 : kLineHeight);
      for (int i = 0; i < 4; ++i) chat.color[i] = 255;
      out.push_back(chat);
    }
  }
  std::stable_sort(out.begin(), out.end(), [](const Label& a, const Label& b) { return a.depth > b.depth; });
  return out;
}

}  // namespace graal3d::render
