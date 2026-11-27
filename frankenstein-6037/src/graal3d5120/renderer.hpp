// The 3D view's backends: one interface, the frame drawn by the 5.12
// renderer's software rasteriser or by the GPU through OpenGL.
//
// Both draw the same Scene into the same pixels and make the same choices
// (common/cpp/graal3dengine/render/draw.hpp: what is lit how, which
// texture a material takes, the sky box and the water); only the
// rasterising differs. A Metal backend would be a third implementation of
// SceneRenderer. The software one stays the fallback when no OpenGL 3.2
// core context can be made.
#pragma once

#include <memory>
#include <string>

#include "../../../common/cpp/graal3dengine/render/draw.hpp"

namespace Frank {

class SceneRenderer {
 public:
  virtual ~SceneRenderer() = default;
  // "software", "opengl".
  virtual const char* name() const = 0;
  // What it draws with ("software rasteriser", "OpenGL 4.5 (llvmpipe, Mesa)").
  virtual std::string description() const = 0;
  // One frame of `scene` into `frame`, as graal3d::render::drawScene.
  virtual graal3d::render::DrawStats draw(graal3d::render::Frame frame, const graal3d::render::Scene& scene,
                                          graal3d::render::Resources& resources) = 0;
};

enum class RendererChoice { Auto, OpenGL, Software };

// "auto", "opengl" (also "gl"), "software"; false for anything else.
bool parse_renderer(const std::string& text, RendererChoice& out);

std::unique_ptr<SceneRenderer> make_software_renderer();
// Null, with `why`, when no OpenGL 3.2 core context can be made.
std::unique_ptr<SceneRenderer> make_gl_renderer(std::string& why);

// Auto: OpenGL, else software. OpenGL: OpenGL or null. `note` says what
// was chosen and, on a fallback, why.
std::unique_ptr<SceneRenderer> make_renderer(RendererChoice choice, std::string& note);

}  // namespace Frank
