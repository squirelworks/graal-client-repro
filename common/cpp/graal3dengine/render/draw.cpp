#include "draw.hpp"

#include <algorithm>
#include <cmath>

namespace graal3d::render {

namespace {

uint32_t colorOf(const float c[3]) {
  auto b = [](float x) { return uint32_t(x <= 0 ? 0 : (x >= 1 ? 255 : x * 255.0f + 0.5f)); };
  return packRgba(b(c[0]), b(c[1]), b(c[2]));
}

void drawSkyBox(Rasterizer& r, const Scene& scene, Resources& res, float farPlane) {
  const V3 eye{scene.view.cameraToWorld.m[0][3], scene.view.cameraToWorld.m[1][3], scene.view.cameraToWorld.m[2][3]};
  const float s = farPlane * 0.5f;
  // Corners of each face seen from inside: top-left, top-right,
  // bottom-right, bottom-left (draw.hpp).
  const V3 faces[6][4] = {
      {{-s, s, s}, {s, s, s}, {s, s, -s}, {-s, s, -s}},      // front, +y
      {{s, s, s}, {s, -s, s}, {s, -s, -s}, {s, s, -s}},      // right, +x
      {{s, -s, s}, {-s, -s, s}, {-s, -s, -s}, {s, -s, -s}},  // back, -y
      {{-s, -s, s}, {-s, s, s}, {-s, s, -s}, {-s, -s, -s}},  // left, -x
      {{-s, s, s}, {s, s, s}, {s, -s, s}, {-s, -s, s}},      // top, +z
      {{-s, s, -s}, {s, s, -s}, {s, -s, -s}, {-s, -s, -s}},  // bottom, -z
  };
  const float uv[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};
  RasterState st;
  st.depthTest = false;
  st.depthWrite = false;
  st.clampTexture = true;
  for (int f = 0; f < 6; ++f) {
    const Texture* tex = res.texture(scene.sky.textures[f]);
    if (!tex) continue;
    st.texture = tex;
    RasterVertex q[4];
    for (int i = 0; i < 4; ++i) {
      q[i].position = eye + faces[f][i];
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
  const float farPlane = scene.sky.present && scene.sky.visibleDistance > 0 ? scene.sky.visibleDistance : 1000.0f;
  view.farPlane = farPlane;
  r.setView(view);
  const uint32_t fogColor = scene.sky.present ? colorOf(scene.sky.fogColor) : packRgba(0, 0, 0);
  r.clear(fogColor);
  if (scene.sky.present) drawSkyBox(r, scene, res, farPlane);
  r.clearDepth();

  const V3 eye{view.cameraToWorld.m[0][3], view.cameraToWorld.m[1][3], view.cameraToWorld.m[2][3]};
  const float fogStart = farPlane * 0.5f;
  const bool fog = scene.sky.present;
  const V3 toLight = -scene.sun.direction;

  for (const SceneObject& obj : scene.objects) {
    const Shape* shape = obj.direct ? obj.direct : res.shape(obj.shape);
    if (!shape) {
      ++stats.objectsMissing;
      continue;
    }
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
        if (scene.sun.present) {
          const V3 n = normalize(obj.transform.vector(mv.normal));
          const float d = std::max(0.0f, dot(n, toLight));
          for (int j = 0; j < 3; ++j) rv.light[j] = std::min(1.0f, scene.sun.ambient[j] + scene.sun.color[j] * d);
        }
        if (fog) {
          const float dist = length(rv.position - eye);
          rv.fog = dist <= fogStart ? 0 : (dist - fogStart) / (farPlane - fogStart);
        }
      }
      for (const Triangle& t : mesh.triangles) {
        if (t.material < 0 || size_t(t.material) >= shape->materials.size()) continue;  // not drawn (read_3ds.hpp)
        const Material& m = shape->materials[t.material];
        RasterState st;
        st.fogColor = fogColor;
        st.texture = m.texture.empty() ? nullptr : res.texture(m.texture);
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
    const float corners[4][2] = {{0, 0}, {w.width, 0}, {w.width, w.depth}, {0, w.depth}};
    RasterVertex q[4];
    for (int i = 0; i < 4; ++i) {
      q[i].position = w.transform.point({corners[i][0], corners[i][1], 0});
      q[i].u = corners[i][0] / 16.0f;
      q[i].v = corners[i][1] / 16.0f;
      if (fog) {
        const float dist = length(q[i].position - eye);
        q[i].fog = dist <= fogStart ? 0 : (dist - fogStart) / (farPlane - fogStart);
      }
    }
    r.drawTriangle(q[0], q[1], q[2], st);
    r.drawTriangle(q[0], q[2], q[3], st);
    stats.triangles += 2;
  }
  stats.labels = sceneLabels(scene, res, frame.width, frame.height);
  return stats;
}

std::vector<Label> sceneLabels(const Scene& scene, Resources& res, int width, int height) {
  std::vector<Label> out;
  if (!scene.hasCamera || width <= 0 || height <= 0) return out;
  View view = scene.view;
  view.farPlane = scene.sky.present && scene.sky.visibleDistance > 0 ? scene.sky.visibleDistance : 1000.0f;
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
