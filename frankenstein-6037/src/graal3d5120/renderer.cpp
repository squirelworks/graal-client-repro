#include "renderer.hpp"

namespace Frank {

namespace {

class SoftwareRenderer : public SceneRenderer {
 public:
  const char* name() const override { return "software"; }
  std::string description() const override { return "software rasteriser"; }
  graal3d::render::DrawStats draw(graal3d::render::Frame frame, const graal3d::render::Scene& scene,
                                  graal3d::render::Resources& resources) override {
    return graal3d::render::drawScene(frame, scene, resources);
  }
};

}  // namespace

bool parse_renderer(const std::string& text, RendererChoice& out) {
  if (text == "auto") out = RendererChoice::Auto;
  else if (text == "opengl" || text == "gl") out = RendererChoice::OpenGL;
  else if (text == "software" || text == "sw") out = RendererChoice::Software;
  else return false;
  return true;
}

std::unique_ptr<SceneRenderer> make_software_renderer() { return std::make_unique<SoftwareRenderer>(); }

std::unique_ptr<SceneRenderer> make_renderer(RendererChoice choice, std::string& note) {
  if (choice == RendererChoice::Software) {
    note = "Graal3D: software renderer";
    return make_software_renderer();
  }
  std::string why;
  if (auto gl = make_gl_renderer(why)) {
    note = "Graal3D: OpenGL renderer, " + gl->description();
    return gl;
  }
  if (choice == RendererChoice::OpenGL) {
    note = "Graal3D: no OpenGL renderer: " + why;
    return nullptr;
  }
  note = "Graal3D: software renderer (no OpenGL 3.2: " + why + ")";
  return make_software_renderer();
}

}  // namespace Frank
