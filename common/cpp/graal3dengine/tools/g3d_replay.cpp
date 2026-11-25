// g3d-replay: what a recorded 3D session sent the client, and the world it
// drew.
//
//   g3d-replay [options] capture.pcap
//     --port N        the server's UDP port (default: from the challenge)
//     --protocol N    19, 21 or 24 (default 24, the 5.x clients)
//     --at SECONDS    stop that long after the client's challenge
//     --render FILE   draw the world as the client's camera saw it (PNG)
//     --size WxH      the image size (default 800x600)
//     --res DIR       where the session's files are (repeat for more);
//                     the client's levels3d folder, for example
//     --fov DEGREES   the field of view when the server sent none
//     --quiet         no event log, only the summary and the ghosts
//
// Prints the session (addresses, the class tables, the login steps, the
// commands and texts the server sent, with times) and then every ghost the
// client held at the end. Captures and the files they name are real
// server content: keep them and this tool's output out of the repository.
#include "capture.hpp"
#include "draw.hpp"
#include "motion.hpp"
#include "png.hpp"
#include "resources.hpp"
#include "scene.hpp"
#include "terrain.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>

using namespace graal3d;

namespace {

std::string fmt(float v) {
  char b[32];
  std::snprintf(b, sizeof b, "%.4g", double(v));
  return b;
}
std::string fmt(const Vec3& v) { return "(" + fmt(v.x) + ", " + fmt(v.y) + ", " + fmt(v.z) + ")"; }
std::string rgba(const float* c) { return "(" + fmt(c[0]) + ", " + fmt(c[1]) + ", " + fmt(c[2]) + ", " + fmt(c[3]) + ")"; }

std::string quote(const std::string& s) {
  std::string o = "\"";
  for (unsigned char c : s) {
    if (c == '"' || c == '\\') o += '\\', o += char(c);
    else if (c >= 32 && c < 127) o += char(c);
    else {
      char b[8];
      std::snprintf(b, sizeof b, "\\x%02x", c);
      o += b;
    }
  }
  return o + "\"";
}

void printObject(const GameObjectState& o, const char* indent) {
  std::printf("%sname %s\n", indent, quote(o.name).c_str());
  if (!o.shape.empty()) std::printf("%sshape %s\n", indent, quote(o.shape).c_str());
  if (!o.skin.empty()) std::printf("%sskin %s\n", indent, quote(o.skin).c_str());
  if (o.hasTransform)
    std::printf("%sposition %s axis %s angle %s rad\n", indent, fmt(o.position).c_str(), fmt(o.axis).c_str(),
                fmt(o.angle).c_str());
  if (o.scale.x != 0 || o.scale.y != 0 || o.scale.z != 0)
    std::printf("%sscale %s\n", indent, fmt(o.scale).c_str());
  if (!o.movetype.empty()) std::printf("%smovetype %s\n", indent, quote(o.movetype).c_str());
  if (o.hasMovementData)
    std::printf("%smovement position %s, %zu list entries, %u payloads\n", indent, fmt(o.movement.position).c_str(),
                o.movement.list.size(), o.movementSerial);
  if (o.flags) std::printf("%sflags 0x%x\n", indent, o.flags);
  if (!o.nickname.empty())
    std::printf("%snickname %s colour (%u, %u, %u, %u)\n", indent, quote(o.nickname).c_str(), o.nickColor[0],
                o.nickColor[1], o.nickColor[2], o.nickColor[3]);
  if (!o.chat.empty()) std::printf("%schat %s\n", indent, quote(o.chat).c_str());
  if (!o.scriptClasses.empty()) std::printf("%sscript classes %s\n", indent, quote(o.scriptClasses).c_str());
  for (size_t i = 0; i < o.attr.size(); ++i)
    if (!o.attr[i].empty()) std::printf("%sattr%zu %s\n", indent, i + 1, quote(o.attr[i]).c_str());
}

void printGhosts(const Link& link) {
  std::printf("\nGhosts held at the end (%zu):\n", link.ghosts().size());
  for (const auto& [idx, g] : link.ghosts()) {
    std::printf("  [%d] %s, %d update%s%s%s\n", idx, g.className.c_str(), g.updates, g.updates == 1 ? "" : "s",
                idx == link.controlGhost() ? ", control object" : "", idx == link.cameraGhost() ? ", camera" : "");
    if (g.className == "GameObject") {
      printObject(g.object, "      ");
    } else if (g.className == "Camera") {
      printObject(g.camera.object, "      ");
      std::printf("      mode %d follow %d\n", g.camera.mode, g.camera.followGhost);
    } else if (g.className == "Sun") {
      const SunState& s = g.sun;
      std::printf("      name %s\n      direction %s\n      colour %s ambient %s\n", quote(s.name).c_str(),
                  fmt(s.direction).c_str(), rgba(s.color).c_str(), rgba(s.ambient).c_str());
    } else if (g.className == "Sky") {
      const SkyState& s = g.sky;
      std::printf("      name %s\n      visible distance %s\n      textures %s\n      fog colour %s\n",
                  quote(s.name).c_str(), fmt(s.visibleDistance).c_str(), quote(s.textures).c_str(),
                  fmt(s.fogColor).c_str());
      for (const auto& v : s.fogVolumes)
        std::printf("      fog volume %s %s %s %s %s %s flag %u\n", fmt(v.values[0]).c_str(), fmt(v.values[1]).c_str(),
                    fmt(v.values[2]).c_str(), fmt(v.values[3]).c_str(), fmt(v.values[4]).c_str(),
                    fmt(v.values[5]).c_str(), v.flag);
      std::printf("      options %u %u %u, solid colour %s\n", s.options[0], s.options[1], s.options[2],
                  fmt(s.solidColor).c_str());
      for (const auto& c : s.clouds)
        if (!c.texture.empty())
          std::printf("      cloud %s height %s speed %s\n", quote(c.texture).c_str(), fmt(c.height).c_str(),
                      fmt(c.speed).c_str());
      std::printf("      wind %s\n", fmt(s.windVelocity).c_str());
    } else if (g.className == "TerrainBlock") {
      const TerrainBlockState& t = g.terrain;
      std::printf("      name %s, square size %u, repeat %d\n", quote(t.name).c_str(), t.squareSize, t.repeat ? 1 : 0);
    } else if (g.className == "WaterBlock") {
      const WaterBlockState& w = g.water;
      std::printf("      name %s\n      position %s scale %s rotation (%s, %s, %s, %s)\n", quote(w.name).c_str(),
                  fmt(w.position).c_str(), fmt(w.scale).c_str(), fmt(w.rotation[0]).c_str(), fmt(w.rotation[1]).c_str(),
                  fmt(w.rotation[2]).c_str(), fmt(w.rotation[3]).c_str());
      std::printf("      surface %s shore %s liquid type %u opacity %s\n", quote(w.textures[0]).c_str(),
                  quote(w.textures[4]).c_str(), w.liquidType, fmt(w.opacity).c_str());
    }
  }
}

int usage() {
  std::fprintf(stderr,
               "usage: g3d-replay [--port N] [--protocol N] [--at SECONDS] [--render FILE.png] [--size WxH]\n"
               "                  [--res DIR]... [--fov DEGREES] [--quiet] capture.pcap\n");
  return 2;
}

}  // namespace

int main(int argc, char** argv) {
  capture::ReplayOptions opt;
  std::string path, renderPath;
  std::vector<std::string> roots;
  int width = 800, height = 600, fovOverride = 0;
  bool quiet = false;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    auto next = [&]() -> const char* { return i + 1 < argc ? argv[++i] : nullptr; };
    const char* v = nullptr;
    if (a == "--quiet") quiet = true;
    else if (a == "--port" && (v = next())) opt.serverPort = uint16_t(std::atoi(v));
    else if (a == "--protocol" && (v = next())) opt.protocol = std::atoi(v);
    else if (a == "--at" && (v = next())) opt.stopAt = std::atof(v);
    else if (a == "--render" && (v = next())) renderPath = v;
    else if (a == "--res" && (v = next())) roots.push_back(v);
    else if (a == "--fov" && (v = next())) fovOverride = std::atoi(v);
    else if (a == "--size" && (v = next())) {
      if (std::sscanf(v, "%dx%d", &width, &height) != 2 || width <= 0 || height <= 0 || width > 8192 ||
          height > 8192)
        return usage();
    } else if (!a.empty() && a[0] != '-' && path.empty()) path = a;
    else return usage();
  }
  if (path.empty()) return usage();

  std::ifstream f(path, std::ios::binary);
  if (!f) {
    std::fprintf(stderr, "g3d-replay: cannot open %s\n", path.c_str());
    return 1;
  }
  std::stringstream ss;
  ss << f.rdbuf();
  std::vector<capture::Datagram> datagrams;
  capture::CaptureStats st;
  std::string error;
  if (!capture::readCapture(ss.str(), datagrams, st, error)) {
    std::fprintf(stderr, "g3d-replay: %s\n", error.c_str());
    return 1;
  }
  std::printf("Capture: %zu frames, %zu UDP, %zu TCP, %zu fragments and %zu others skipped\n", st.frames, st.udp,
              st.tcp, st.fragments, st.skipped);

  std::unique_ptr<Link> link;
  const capture::ReplayResult res = capture::replay(datagrams, opt, link);
  if (!res.found) {
    std::fprintf(stderr, "g3d-replay: no challenge request (0x1A) in the capture%s\n",
                 opt.serverPort ? " to that port" : "");
    return 1;
  }
  std::printf("Session: client %s:%u, server %s:%u, connect sequence 0x%x, protocol %d\n",
              capture::ipText(res.clientIp).c_str(), res.clientPort, capture::ipText(res.serverIp).c_str(),
              res.serverPort, res.sequence, opt.protocol);
  std::printf("Fed %zu server packets over %.2f s (the client sent %zu); link %s, login step %d\n",
              res.serverPackets, res.lastTime, res.clientPackets,
              link->state() == Link::State::Connected ? "connected" : "not connected", link->loginStep());
  std::printf("\nObject classes:");
  for (const auto& [id, name] : link->objectClasses()) std::printf(" %d=%s", id, name.c_str());
  std::printf("\nEvent classes:");
  for (const auto& [id, name] : link->eventClasses()) std::printf(" %d=%s", id, name.c_str());
  std::printf("\n");
  if (!quiet) {
    std::printf("\nEvents:\n");
    for (const auto& e : res.events) std::printf("  %8.3f  %s\n", e.time, e.what.c_str());
  }
  std::printf("\nCommands:");
  for (const auto& c : link->commandsReceived()) std::printf(" %s", c.c_str());
  std::printf("\nServer time %u, control ghost %d, camera ghost %d, field of view %d\n", link->serverTime(),
              link->controlGhost(), link->cameraGhost(), link->fieldOfView());
  printGhosts(*link);
  if (link->terrainChunkCount() > 0)
    std::printf("\nTerrain chunks: %d received, %zu distinct\n", link->terrainChunkCount(), link->terrainChunks().size());

  if (!renderPath.empty()) {
    render::Resources resources;
    resources.setLog([](const std::string& s) { std::printf("  render: %s\n", s.c_str()); });
    for (const auto& r : roots) resources.addRoot(r);
    const int fov = link->fieldOfView() > 0 ? link->fieldOfView() : fovOverride;
    render::Scene scene = render::sceneFromGhosts(link->ghosts(), link->cameraGhost(), float(fov));
    // At the capture's last moment: moving objects at their section 7
    // targets, a Camera in mode 1 aimed at the control object, the water's
    // waves at that time (the clock's origin is the capture's start).
    render::MotionTracker motion;
    scene.time = res.lastTime;
    render::applyMotion(scene, link->ghosts(), motion, res.lastTime, link->cameraGhost(), link->controlGhost());
    // The streamed terrain: the chunks the session sent, over the client's
    // cache (levels3d/heights/<server>/) when a --res folder holds one.
    render::StreamedTerrain terrain;
    if (scene.terrain.present) {
      const std::string info = resources.find("heights.info");
      const std::string cacheDir = info.empty() ? "" : std::filesystem::path(info).parent_path().string();
      render::updateStreamedTerrain(terrain, scene.terrain.squareSize, scene.terrain.repeat, cacheDir,
                                    link->terrainChunks(), link->terrainChunkCount());
      if (!cacheDir.empty())
        std::printf("  terrain cache %s: %d chunk files\n", cacheDir.c_str(), terrain.terrain.chunksLoaded);
      render::SceneObject so;
      so.shape = "(terrain)";
      so.transform = render::M4::identity();
      so.direct = &terrain.shape;
      scene.objects.push_back(so);
    }
    std::vector<uint32_t> pixels(size_t(width) * height, 0);
    std::printf("\nRendering %dx%d to %s\n", width, height, renderPath.c_str());
    const render::DrawStats ds = render::drawScene({pixels.data(), width, height, width}, scene, resources);
    std::printf("  %s; %d objects drawn, %d missing, %ld triangles\n",
                scene.hasCamera ? "camera found" : "no camera: the frame is black", ds.objectsDrawn,
                ds.objectsMissing, ds.triangles);
    for (const render::Label& l : ds.labels)
      std::printf("  %s of ghost %d at (%.0f, %.0f), %.1f m: \"%s\"\n",
                  l.kind == render::Label::kChat ? "chat" : "name", l.ghost, l.x, l.y, l.depth, l.text.c_str());
    if (!tools::writePng(renderPath, pixels.data(), width, height, width)) {
      std::fprintf(stderr, "g3d-replay: cannot write %s\n", renderPath.c_str());
      return 1;
    }
  }
  return 0;
}
