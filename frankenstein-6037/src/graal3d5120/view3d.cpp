#include "view3d.hpp"

#include <algorithm>
#include <cmath>

#include "../../../common/cpp/graal3dengine/render/draw.hpp"
#include "../../../common/cpp/quattro/draw/ui_font.hpp"
#include "../../../common/torque/gui/canvas.hpp"

namespace Frank {

using graal3d::Vec3;
using Torque::Gui::Color;
using Torque::Gui::Image;

namespace {

Vec3 add(Vec3 a, Vec3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
Vec3 sub(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
Vec3 mul(Vec3 a, float k) { return {a.x * k, a.y * k, a.z * k}; }
float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
Vec3 cross(Vec3 a, Vec3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
Vec3 norm(Vec3 a) {
  float l = std::sqrt(dot(a, a));
  return l > 1e-6f ? mul(a, 1.0f / l) : Vec3{0, 1, 0};
}

uint8_t channel(float v) { return static_cast<uint8_t>(std::clamp(v, 0.0f, 1.0f) * 255.0f + 0.5f); }

// Torque is z up, y forward. The camera sits behind and above its target.
struct Camera {
  Vec3 eye, right, up, fwd;
  float focal = 1;
  int w = 0, h = 0;
  static constexpr float kNear = 0.1f;

  Vec3 to_view(Vec3 p) const {
    Vec3 d = sub(p, eye);
    return {dot(d, right), dot(d, up), dot(d, fwd)};
  }
  void project(Vec3 v, float& sx, float& sy) const {
    sx = w * 0.5f + v.x / v.z * focal;
    sy = h * 0.5f - v.y / v.z * focal;
  }
};

void plot(Image& img, int x, int y, Color c) {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) return;
  img.at(x, y) = c;
}

void line2d(Image& img, float x0, float y0, float x1, float y1, Color c) {
  // Far-off points are pulled in first so the step count stays small.
  const float lim = 4.0f * static_cast<float>(std::max(img.width, img.height));
  if (std::fabs(x0) > lim || std::fabs(y0) > lim || std::fabs(x1) > lim || std::fabs(y1) > lim) {
    float t0 = 0, t1 = 1;
    auto clip = [&](float p, float q) {
      if (std::fabs(p) < 1e-9f) return q >= 0;
      float r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    };
    const float dx = x1 - x0, dy = y1 - y0;
    if (!clip(-dx, x0 + lim) || !clip(dx, lim - x0) || !clip(-dy, y0 + lim) || !clip(dy, lim - y0)) return;
    const float nx0 = x0 + t0 * dx, ny0 = y0 + t0 * dy;
    x1 = x0 + t1 * dx;
    y1 = y0 + t1 * dy;
    x0 = nx0;
    y0 = ny0;
  }
  const int steps = static_cast<int>(std::max(std::fabs(x1 - x0), std::fabs(y1 - y0))) + 1;
  for (int i = 0; i <= steps; ++i) {
    const float t = static_cast<float>(i) / static_cast<float>(steps);
    plot(img, static_cast<int>(std::lround(x0 + (x1 - x0) * t)), static_cast<int>(std::lround(y0 + (y1 - y0) * t)), c);
  }
}

void line3d(Image& img, const Camera& cam, Vec3 a, Vec3 b, Color c) {
  Vec3 va = cam.to_view(a), vb = cam.to_view(b);
  if (va.z < Camera::kNear && vb.z < Camera::kNear) return;
  // Clip against the near plane.
  if (va.z < Camera::kNear || vb.z < Camera::kNear) {
    const float t = (Camera::kNear - va.z) / (vb.z - va.z);
    Vec3 m = add(va, mul(sub(vb, va), t));
    if (va.z < Camera::kNear) va = m;
    else vb = m;
  }
  float x0, y0, x1, y1;
  cam.project(va, x0, y0);
  cam.project(vb, x1, y1);
  line2d(img, x0, y0, x1, y1, c);
}

void box(Image& img, const Camera& cam, Vec3 at, float half, float height, float yaw, Color c) {
  const float cs = std::cos(yaw), sn = std::sin(yaw);
  auto corner = [&](float dx, float dy, float dz) {
    return Vec3{at.x + dx * cs - dy * sn, at.y + dx * sn + dy * cs, at.z + dz};
  };
  const float xs[4] = {-half, half, half, -half}, ys[4] = {-half, -half, half, half};
  for (int i = 0; i < 4; ++i) {
    const int j = (i + 1) % 4;
    line3d(img, cam, corner(xs[i], ys[i], 0), corner(xs[j], ys[j], 0), c);
    line3d(img, cam, corner(xs[i], ys[i], height), corner(xs[j], ys[j], height), c);
    line3d(img, cam, corner(xs[i], ys[i], 0), corner(xs[i], ys[i], height), c);
  }
  // A nose on the facing side (+y).
  line3d(img, cam, corner(0, half, height * 0.5f), corner(0, half * 2.0f, height * 0.5f), c);
}

float yaw_of(const graal3d::GameObjectState& o) {
  // A rotation about z; any other axis is drawn upright.
  if (!o.hasTransform) return 0;
  return o.axis.z < 0 ? -o.angle : o.angle;
}

}  // namespace

bool draw_world3d(Image& frame, const graal3d::Link& link, World3D& world, double now, View3DStats* stats) {
  return draw_world3d(frame, link.ghosts(), link.cameraGhost(), link.controlGhost(), link.fieldOfView(),
                      link.terrainChunks(), link.terrainChunkCount(), world, now, stats);
}

bool draw_world3d(Image& frame, const graal3d::GhostTable& ghosts, int camera, int control, int fov,
                  const std::map<int, std::string>& chunks, int chunkCount, World3D& world, double now,
                  View3DStats* stats) {
  namespace R = graal3d::render;
  if (frame.empty()) return false;
  R::Scene scene = R::sceneFromGhosts(ghosts, camera, static_cast<float>(fov));
  if (!scene.hasCamera) return false;
  if (!world.rooted) {
    if (world.roots.empty()) world.resources.addRoot("levels3d");
    for (const auto& r : world.roots) world.resources.addRoot(r);
    world.rooted = true;
  }
  scene.time = now;
  R::applyMotion(scene, ghosts, world.motion, now, camera, control);
  if (scene.terrain.present) {
    // The session's chunks over the client's own cache, when a resource
    // folder holds one (levels3d/heights/<server>/), as exports.cpp does.
    const std::string info = world.resources.find("heights.info");
    const std::string dir = info.empty() ? "" : info.substr(0, info.find_last_of("/\\"));
    R::updateStreamedTerrain(world.terrain, scene.terrain.squareSize, scene.terrain.repeat, dir, chunks, chunkCount);
    R::SceneObject so;
    so.shape = "(terrain)";
    so.transform = R::M4::identity();
    so.direct = &world.terrain.shape;
    scene.objects.push_back(so);
  }
  std::vector<uint32_t> px(std::size_t(frame.width) * frame.height);
  const R::DrawStats ds = R::drawScene({px.data(), frame.width, frame.height, frame.width}, scene, world.resources);
  Torque::Gui::Canvas canvas(frame.width, frame.height);
  {
    Image img(frame.width, frame.height);
    for (std::size_t i = 0; i < px.size(); ++i) {
      const uint32_t p = px[i];
      img.pixels[i] = {uint8_t(p), uint8_t(p >> 8), uint8_t(p >> 16), 255};
    }
    canvas.blit(img, 0, 0);
  }
  // Name tags, farthest first, centred above their anchor with a shadow.
  for (const R::Label& l : ds.labels) {
    const int w = Quattro::Draw::ui_text_width(l.text, l.kind == R::Label::kNickname);
    const int x = static_cast<int>(std::lround(l.x)) - w / 2;
    const int y = static_cast<int>(std::lround(l.y)) - Quattro::Draw::kUiLineHeight;
    const bool bold = l.kind == R::Label::kNickname;
    Quattro::Draw::ui_draw_text(canvas, x + 1, y + 1, l.text, Color{0, 0, 0, 255}, bold);
    Quattro::Draw::ui_draw_text(canvas, x, y, l.text, Color{l.color[0], l.color[1], l.color[2], 255}, bold);
  }
  frame.pixels = canvas.surface().pixels;
  if (stats) {
    stats->objects = ds.objectsDrawn;
    stats->control = control >= 0 && ghosts.count(control);
  }
  return true;
}

View3DStats draw_view3d(Image& frame, const graal3d::GhostTable& ghosts, int control, const Vec3& control_at) {
  View3DStats st;
  if (frame.empty()) return st;

  // The sky's fog colour (0..1), else a plain blue.
  Color sky{96, 136, 200, 255};
  for (const auto& [id, g] : ghosts) {
    (void)id;
    if (g.className == "Sky" && g.sky.init)
      sky = {channel(g.sky.fogColor.x), channel(g.sky.fogColor.y), channel(g.sky.fogColor.z), 255};
  }
  const Color ground{60, 92, 52, 255};
  for (int y = 0; y < frame.height; ++y)
    for (int x = 0; x < frame.width; ++x) frame.at(x, y) = y < frame.height / 2 ? sky : ground;

  Vec3 target = control_at;
  float heading = 0;
  auto c = ghosts.find(control);
  if (c != ghosts.end()) heading = yaw_of(c->second.object);
  const Vec3 fwd_flat{-std::sin(heading), std::cos(heading), 0};

  Camera cam;
  cam.w = frame.width;
  cam.h = frame.height;
  cam.focal = static_cast<float>(frame.height) * 0.5f / std::tan(0.5f * 1.0472f);  // 60 degrees
  cam.eye = add(sub(target, mul(fwd_flat, 8.0f)), Vec3{0, 0, 4.0f});
  cam.fwd = norm(sub(add(target, Vec3{0, 0, 1.0f}), cam.eye));
  cam.right = norm(cross(cam.fwd, Vec3{0, 0, 1}));
  cam.up = cross(cam.right, cam.fwd);

  // The horizon follows the camera's pitch.
  {
    Vec3 far = add(cam.eye, mul(fwd_flat, 10000.0f));
    far.z = 0;
    Vec3 v = cam.to_view(far);
    if (v.z > Camera::kNear) {
      float sx, sy;
      cam.project(v, sx, sy);
      const int hz = std::clamp(static_cast<int>(sy), 0, frame.height);
      for (int y = 0; y < frame.height; ++y)
        for (int x = 0; x < frame.width; ++x) frame.at(x, y) = y < hz ? sky : ground;
    }
  }

  // A 2-unit grid around the target.
  const Color grid{88, 128, 76, 255};
  const float gx = std::floor(target.x / 2.0f) * 2.0f, gy = std::floor(target.y / 2.0f) * 2.0f;
  for (int i = -20; i <= 20; ++i) {
    const float o = static_cast<float>(i) * 2.0f;
    line3d(frame, cam, {gx + o, gy - 40, 0}, {gx + o, gy + 40, 0}, grid);
    line3d(frame, cam, {gx - 40, gy + o, 0}, {gx + 40, gy + o, 0}, grid);
  }

  for (const auto& [id, g] : ghosts) {
    if (g.className != "GameObject" && g.className != "Camera") continue;
    const graal3d::GameObjectState& o = g.className == "Camera" ? g.camera.object : g.object;
    if (!o.hasTransform && id != control) continue;
    ++st.objects;
    const bool me = id == control;
    if (me) st.control = true;
    const Vec3 at = me ? control_at : o.position;
    const Color col = me ? Color{255, 220, 64, 255}
                         : Color{o.nickColor[0], o.nickColor[1], o.nickColor[2], 255};
    box(frame, cam, at, 0.5f, 1.8f, yaw_of(o), col);
  }
  return st;
}

void draw_inset(Image& frame, const Image& inset, int div) {
  if (frame.empty() || inset.empty() || div < 1) return;
  const int w = inset.width / div, h = inset.height / div;
  const int x0 = 8, y0 = frame.height - h - 8;
  if (w <= 0 || h <= 0 || y0 < 0 || x0 + w > frame.width) return;
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) frame.at(x0 + x, y0 + y) = inset.at(x * div, y * div);
  const Color edge{255, 255, 255, 255};
  for (int x = -1; x <= w; ++x) {
    plot(frame, x0 + x, y0 - 1, edge);
    plot(frame, x0 + x, y0 + h, edge);
  }
  for (int y = -1; y <= h; ++y) {
    plot(frame, x0 - 1, y0 + y, edge);
    plot(frame, x0 + w, y0 + y, edge);
  }
}

}  // namespace Frank
