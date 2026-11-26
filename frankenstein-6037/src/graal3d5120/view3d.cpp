#include "view3d.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <sstream>

#include "../../../common/cpp/graal3dengine/render/draw.hpp"
#include "../../../common/cpp/graal3dengine/render/replicate.hpp"
#include "../../../common/cpp/quattro/draw/ui_font.hpp"
#include "../../../common/torque/gui/canvas.hpp"

namespace Frank {

using Torque::Gui::Color;
using Torque::Gui::Image;

namespace {

std::string trim(const std::string& s) {
  const auto a = s.find_first_not_of(" \t\r\n"), b = s.find_last_not_of(" \t\r\n");
  return a == std::string::npos ? std::string() : s.substr(a, b - a + 1);
}

void plot(Image& img, int x, int y, Color c) {
  if (x < 0 || y < 0 || x >= img.width || y >= img.height) return;
  img.at(x, y) = c;
}

}  // namespace

float visible_distance_from_config(const std::string& text) {
  std::istringstream in(text);
  std::string line;
  float found = 0;
  while (std::getline(in, line)) {
    const auto eq = line.find('=');
    if (eq == std::string::npos) continue;
    std::string key = trim(line.substr(0, eq));
    std::transform(key.begin(), key.end(), key.begin(), [](unsigned char c) { return char(std::tolower(c)); });
    if (key != "visibledistance3d") continue;
    char* end = nullptr;
    const std::string v = trim(line.substr(eq + 1));
    const float d = std::strtof(v.c_str(), &end);
    if (end != v.c_str()) found = d;
  }
  return found;
}

float load_visible_distance(const std::vector<std::string>& paths) {
  float d = 0;
  for (const std::string& path : paths) {
    std::ifstream f(path, std::ios::binary);
    if (!f) continue;
    std::ostringstream ss;
    ss << f.rdbuf();
    d = visible_distance_from_config(ss.str());
    if (d > 0) break;
  }
  return graal3d::render::setVisibleDistance3D(d);
}

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
  if (!scene.hasCamera) {
    // The 5.12 draws black until the server names a Camera.
    for (auto& p : frame.pixels) p = Color{0, 0, 0, 255};
    if (stats) {
      *stats = View3DStats{};
      stats->control = control >= 0 && ghosts.count(control);
    }
    return false;
  }
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
    R::V3 at;
    if (R::scenePositionOf(scene, control, at)) R::scatterReplicators(scene, ghosts, world.terrain.terrain, at, world.resources);
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
