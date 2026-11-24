#include "scene.hpp"

namespace graal3d::render {

namespace {
V3 v(const Vec3& a) { return {a.x, a.y, a.z}; }

float clamp01(float x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
}  // namespace

M4 objectTransform(const GameObjectState& o) { return graalTransform(v(o.position), v(o.axis), o.angle); }

Scene sceneFromGhosts(const GhostTable& ghosts, int cameraGhost, float fovDegrees) {
  Scene scene;
  scene.view.fovDegrees = fovDegrees > 0 ? fovDegrees : 90.0f;
  for (const auto& [index, g] : ghosts) {
    if (g.className == "GameObject") {
      if (g.object.shape.empty()) continue;
      SceneObject so;
      so.ghost = index;
      so.shape = g.object.shape;
      so.transform = objectTransform(g.object);
      scene.objects.push_back(so);
    } else if (g.className == "Camera") {
      if (index == cameraGhost) {
        scene.hasCamera = true;
        scene.view.cameraToWorld = objectTransform(g.camera.object);
      }
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
