#include "scene.hpp"

#include <cmath>

namespace graal3d::render {

namespace {
V3 v(const Vec3& a) { return {a.x, a.y, a.z}; }

float clamp01(float x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
}  // namespace

float waveHeight(float magnitude, double seconds, float x, float y) {
  constexpr double kPi = 3.14159265358979323846;
  if (!(magnitude > 0) || !std::isfinite(seconds) || !std::isfinite(x) || !std::isfinite(y)) return 0;
  const double phase = seconds / kWavePeriod;
  return static_cast<float>(kWaveAmplitude * magnitude * std::sin(2 * kPi * (phase - std::floor(phase))));
}

M4 objectTransform(const GameObjectState& o) {
  M4 m = graalShapeTransform(v(o.position), v(o.axis), o.angle);
  // Section 2 scales the shape about its origin; all zeros is unset (lab
  // T3D-015).
  const Vec3& s = o.scale;
  if ((s.x != 0 || s.y != 0 || s.z != 0) && std::isfinite(s.x) && std::isfinite(s.y) && std::isfinite(s.z))
    m = m * M4::scale({s.x, s.y, s.z});
  return m;
}
M4 cameraTransform(const GameObjectState& o) { return graalTransform(v(o.position), v(o.axis), o.angle); }

Scene sceneFromGhosts(const GhostTable& ghosts, int cameraGhost, float fovDegrees) {
  Scene scene;
  scene.view.fovDegrees = fovDegrees > 0 ? fovDegrees : 90.0f;
  for (const auto& [index, g] : ghosts) {
    if (g.className == "GameObject") {
      // Flag 0x04 (an editor object) is not drawn (lab LAB-QUEUE 5).
      if (g.object.flags & kGameObjectEditorFlag) continue;
      // The real 5.12 shows no tag on a static GameObject, whatever its
      // nickname or chat (lab T3D-015). Tags go only on objects that move
      // (a movetype set): the rebuild's own reading of "a player" until a
      // lab shot of one.
      if (g.object.hasMovement && (!g.object.nickname.empty() || !g.object.chat.empty())) {
        SceneTag tag;
        tag.ghost = index;
        tag.shape = g.object.shape;
        tag.transform = objectTransform(g.object);
        tag.nickname = g.object.nickname;
        tag.chat = g.object.chat;
        for (int i = 0; i < 4; ++i) tag.color[i] = g.object.nickColor[i];
        scene.tags.push_back(tag);
      }
      if (g.object.shape.empty()) continue;
      SceneObject so;
      so.ghost = index;
      so.shape = g.object.shape;
      so.transform = objectTransform(g.object);
      scene.objects.push_back(so);
    } else if (g.className == "DynamicShapeReplicator") {
      // Drawn as a GameObject with its shape; no copies were scattered in
      // any lab variant (worlds without terrain), and DynamicGrass and
      // DynamicGrassReplicator draw nothing (lab T3D-048, real 5.12).
      if ((g.object.flags & kGameObjectEditorFlag) || g.object.shape.empty()) continue;
      SceneObject so;
      so.ghost = index;
      so.shape = g.object.shape;
      so.transform = objectTransform(g.object);
      scene.objects.push_back(so);
    } else if (g.className == "Camera") {
      if (index == cameraGhost) {
        scene.hasCamera = true;
        scene.view.cameraToWorld = cameraTransform(g.camera.object);
      }
    } else if (g.className == "TerrainBlock" && g.terrain.init) {
      // A later block replaces the first only when it is named Terrain.
      if (!scene.terrain.present || g.terrain.name == "Terrain") {
        scene.terrain.present = true;
        scene.terrain.squareSize = g.terrain.squareSize > 0 && g.terrain.squareSize <= 1024 ? float(g.terrain.squareSize) : 8.0f;
        scene.terrain.repeat = g.terrain.repeat;
      }
    } else if (g.className == "WaterBlock" && g.water.init) {
      const WaterBlockState& w = g.water;
      if (!std::isfinite(w.scale.x) || !std::isfinite(w.scale.y) || w.scale.x <= 0 || w.scale.y <= 0) continue;
      WaterSurface ws;
      // The block runs from its position (a corner) to position + scale and
      // turns about its position: turned 90 degrees about z its +x lies
      // along world -y (lab, real 5.12; Graal_analysis torque/terrain-512.md
      // section 5). That is Torque's quaternion, the conjugate of the
      // textbook one (as read_dts.cpp), so the matrix is the transpose.
      const float qx = w.rotation[0], qy = w.rotation[1], qz = w.rotation[2], qw = w.rotation[3];
      M4 m = M4::identity();
      m.m[0][0] = 1 - 2 * (qy * qy + qz * qz);
      m.m[1][0] = 2 * (qx * qy - qz * qw);
      m.m[2][0] = 2 * (qx * qz + qy * qw);
      m.m[0][1] = 2 * (qx * qy + qz * qw);
      m.m[1][1] = 1 - 2 * (qx * qx + qz * qz);
      m.m[2][1] = 2 * (qy * qz - qx * qw);
      m.m[0][2] = 2 * (qx * qz - qy * qw);
      m.m[1][2] = 2 * (qy * qz + qx * qw);
      m.m[2][2] = 1 - 2 * (qx * qx + qy * qy);
      m.m[0][3] = w.position.x;
      m.m[1][3] = w.position.y;
      m.m[2][3] = w.position.z;
      // The surface is the top of the block: position z plus scale z
      // (lab, real 5.12 under GDI).
      ws.transform = std::isfinite(w.scale.z) ? m * M4::translation({0, 0, w.scale.z}) : m;
      ws.width = w.scale.x;
      ws.depth = w.scale.y;
      ws.texture = w.textures[0];
      ws.opacity = std::isfinite(w.opacity) ? clamp01(w.opacity) : 1.0f;
      ws.waveMagnitude = std::isfinite(w.waveMagnitude) ? std::fabs(w.waveMagnitude) : 0.0f;
      scene.water.push_back(ws);
    } else if (g.className == "Sun" && !scene.sun.present && g.sun.init) {
      scene.sun.present = true;
      scene.sun.direction = normalize(v(g.sun.direction));
      if (length(scene.sun.direction) == 0) scene.sun.direction = {0, 0, -1};
      for (int i = 0; i < 3; ++i) {
        scene.sun.color[i] = clamp01(g.sun.color[i]);
        scene.sun.ambient[i] = clamp01(g.sun.ambient[i]);
      }
    } else if (g.className == "Sky" && !scene.sky.present && g.sky.init) {
      scene.sky.present = true;
      scene.sky.visibleDistance = g.sky.visibleDistance;
      scene.sky.fogColor[0] = clamp01(g.sky.fogColor.x);
      scene.sky.fogColor[1] = clamp01(g.sky.fogColor.y);
      scene.sky.fogColor[2] = clamp01(g.sky.fogColor.z);
      scene.sky.useTextures = g.sky.options[0] != 0;
      scene.sky.drawBottom = g.sky.options[1] != 0;
      scene.sky.solidColor[0] = clamp01(g.sky.solidColor.x);
      scene.sky.solidColor[1] = clamp01(g.sky.solidColor.y);
      scene.sky.solidColor[2] = clamp01(g.sky.solidColor.z);
      // The texture field is a comma list; the first six are the box.
      size_t start = 0;
      for (int i = 0; i < 6 && start <= g.sky.textures.size(); ++i) {
        size_t comma = g.sky.textures.find(',', start);
        if (comma == std::string::npos) comma = g.sky.textures.size();
        std::string name = g.sky.textures.substr(start, comma - start);
        while (!name.empty() && name.front() == ' ') name.erase(name.begin());
        while (!name.empty() && name.back() == ' ') name.pop_back();
        if (name != "-") scene.sky.textures[i] = name;
        start = comma + 1;
      }
    }
  }
  return scene;
}

}  // namespace graal3d::render
