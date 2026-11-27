// The OpenGL backend of the 3D view (renderer.hpp).
//
// The frame is drawn offscreen into a framebuffer object and read back
// into the caller's pixels, so the program's windows (Xlib, GDI, AppKit)
// and its headless runs present it as they present the software frame, and
// the name tags and the 6.x inset go on top as before.
//
// Same choices as drawScene (common/cpp/graal3dengine/render/draw.cpp),
// through the functions it shares: sceneFogColor, materialState,
// skyBoxTriangles, waterTriangles; vertexLight's rules are repeated in the
// vertex shader with draw.hpp's constants. The rasteriser's own rules map
// onto GL state:
//   - its depth test keeps strictly nearer pixels (GL_LESS), an additive
//     terrain layer passes where the depth is no nearer (GL_LEQUAL, the
//     same vertices through the same invariant shader);
//   - texels under half alpha are discarded where the material tests alpha;
//   - water below full opacity blends over what is there, a terrain layer
//     adds its weighted colour (GL_ONE, GL_ONE);
//   - textures filter linearly with no mipmaps, wrap, or clamp on the sky;
//   - both sides of every triangle draw (no culling).
// Meshes that last (shapes from the resource cache, the terrain) are kept
// on the GPU between frames, with their transform as a uniform; shapes
// built for one frame (grass cards) and the sky and water are streamed.
#include "../renderer.hpp"
#include "gl_api.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace Frank {

namespace R = graal3d::render;
using namespace gl;

namespace {

const char* kVertexShader = R"(#version 150
in vec3 aPos;
in vec3 aNormal;
in vec2 aUV;
in vec2 aLightFog;
uniform mat4 uMVP;
uniform mat3 uNormalM;
uniform int uLightMode;  // 0: aLightFog.x, 1: .3ds with a Sun, 2: terrain with a Sun, 3: uLight
uniform float uLight;
uniform vec3 uFixedLight;
uniform vec3 uTerrainLight;
uniform vec4 uLightRule;  // fixed floor, terrain ambient, terrain diffuse, terrain cap
out vec2 vUV;
out float vLight;
out float vFog;
invariant gl_Position;
void main() {
  gl_Position = uMVP * vec4(aPos, 1.0);
  vUV = aUV;
  vFog = aLightFog.y;
  float l = aLightFog.x;
  if (uLightMode == 1 || uLightMode == 2) {
    vec3 n = uNormalM * aNormal;
    float len = length(n);
    n = len > 1e-12 ? n / len : vec3(0.0);
    if (uLightMode == 1)
      l = min(1.0, uLightRule.x + max(0.0, dot(n, uFixedLight)));
    else
      l = min(uLightRule.w, uLightRule.y + uLightRule.z * max(0.0, dot(n, uTerrainLight)));
  } else if (uLightMode == 3) {
    l = uLight;
  }
  vLight = l;
}
)";

const char* kFragmentShader = R"(#version 150
in vec2 vUV;
in float vLight;
in float vFog;
uniform sampler2D uTex;
uniform sampler2D uWeight;
uniform int uTextured;
uniform int uAlphaTest;
uniform int uAdditive;
uniform vec3 uColor;
uniform vec3 uFogColor;
uniform float uOpacity;
uniform float uWeightScale;
uniform float uWeightSize;
out vec4 oColor;
void main() {
  vec4 t = uTextured != 0 ? texture(uTex, vUV) : vec4(1.0);
  if (uAlphaTest != 0 && t.a < 0.5) discard;
  vec3 c = t.rgb * uColor * vLight;
  c = mix(c, uFogColor, clamp(vFog, 0.0, 1.0));
  float a = uOpacity;
  if (uAdditive != 0) {
    // Value (i, j) of the map sits exactly at (i, j), wrapping.
    float w = texture(uWeight, (vUV * uWeightScale + vec2(0.5)) / uWeightSize).r;
    c *= w;
    a = 1.0;
  }
  oColor = vec4(c, clamp(a, 0.0, 1.0));
}
)";

enum Attr : GLuint { kPos = 0, kNormal = 1, kUV = 2, kLightFog = 3 };

// A cheap identity for data the renderer does not own: where it is, how
// big, and a sample of what is in it, so a freed and reloaded shape at the
// same address is not mistaken for the old one.
template <class T>
uint64_t fingerprint(const std::vector<T>& v, uint64_t h = 1469598103934665603ull) {
  auto mix = [&h](const void* p, size_t n) {
    const auto* b = static_cast<const unsigned char*>(p);
    for (size_t i = 0; i < n; ++i) h = (h ^ b[i]) * 1099511628211ull;
  };
  const void* data = v.data();
  const size_t size = v.size();
  mix(&data, sizeof data);
  mix(&size, sizeof size);
  if (!v.empty()) {
    const size_t step = std::max<size_t>(1, v.size() / 31);
    for (size_t i = 0; i < v.size(); i += step) mix(&v[i], sizeof(T));
    mix(&v.back(), sizeof(T));
  }
  return h;
}

uint64_t mesh_fingerprint(const R::Mesh& m) {
  uint64_t h = fingerprint(m.vertices);
  h = fingerprint(m.triangles, h);
  return fingerprint(m.weightMap, h);
}

// Column-major 4 x 4 for GL from the renderer's row-style M4.
void to_gl(const R::M4& m, float out[16]) {
  for (int c = 0; c < 4; ++c)
    for (int r = 0; r < 4; ++r) out[c * 4 + r] = m.m[r][c];
}

struct StreamVertex {
  float pos[3], normal[3], uv[2], lightFog[2];
};

bool same_state(const R::RasterState& a, const R::RasterState& b) {
  return a.texture == b.texture && a.color[0] == b.color[0] && a.color[1] == b.color[1] && a.color[2] == b.color[2] &&
         a.fogColor == b.fogColor && a.depthTest == b.depthTest && a.depthWrite == b.depthWrite &&
         a.alphaTest == b.alphaTest && a.bilinear == b.bilinear && a.clampTexture == b.clampTexture &&
         a.opacity == b.opacity && a.additive == b.additive && a.weightMap == b.weightMap &&
         a.weightSize == b.weightSize && a.weightScale == b.weightScale;
}

class GlRenderer : public SceneRenderer {
 public:
  explicit GlRenderer(std::unique_ptr<Context> ctx) : ctx_(std::move(ctx)), g_(ctx_->api()) {}
  ~GlRenderer() override {
    ctx_->make_current();
    for (auto& [k, m] : meshes_) release(m);
    for (auto& [k, t] : textures_) g_.DeleteTextures(1, &t.tex);
    g_.DeleteTextures(1, &streamWeight_);
    if (blank_) g_.DeleteTextures(1, &blank_);
    g_.DeleteBuffers(1, &streamVbo_);
    g_.DeleteBuffers(1, &streamIbo_);
    g_.DeleteVertexArrays(1, &vao_);
    g_.DeleteFramebuffers(1, &fbo_);
    g_.DeleteRenderbuffers(1, &colorRb_);
    g_.DeleteRenderbuffers(1, &depthRb_);
    g_.DeleteProgram(program_);
  }

  bool init(std::string& why) {
    GLuint vs = compile(VERTEX_SHADER, kVertexShader, why);
    if (!vs) return false;
    GLuint fs = compile(FRAGMENT_SHADER, kFragmentShader, why);
    if (!fs) {
      g_.DeleteShader(vs);
      return false;
    }
    program_ = g_.CreateProgram();
    g_.AttachShader(program_, vs);
    g_.AttachShader(program_, fs);
    g_.BindAttribLocation(program_, kPos, "aPos");
    g_.BindAttribLocation(program_, kNormal, "aNormal");
    g_.BindAttribLocation(program_, kUV, "aUV");
    g_.BindAttribLocation(program_, kLightFog, "aLightFog");
    g_.BindFragDataLocation(program_, 0, "oColor");
    g_.LinkProgram(program_);
    g_.DeleteShader(vs);
    g_.DeleteShader(fs);
    GLint ok = 0;
    g_.GetProgramiv(program_, LINK_STATUS, &ok);
    if (!ok) {
      why = "shader link failed: " + program_log();
      return false;
    }
    g_.UseProgram(program_);
    auto u = [this](const char* n) { return g_.GetUniformLocation(program_, n); };
    uMVP_ = u("uMVP");
    uNormalM_ = u("uNormalM");
    uLightMode_ = u("uLightMode");
    uLight_ = u("uLight");
    uTextured_ = u("uTextured");
    uAlphaTest_ = u("uAlphaTest");
    uAdditive_ = u("uAdditive");
    uColor_ = u("uColor");
    uFogColor_ = u("uFogColor");
    uOpacity_ = u("uOpacity");
    uWeightScale_ = u("uWeightScale");
    uWeightSize_ = u("uWeightSize");
    g_.Uniform1i(u("uTex"), 0);
    g_.Uniform1i(u("uWeight"), 1);
    const R::V3 fl = R::fixedLightDirection(), tl = R::terrainLightDirection();
    g_.Uniform3f(u("uFixedLight"), fl.x, fl.y, fl.z);
    g_.Uniform3f(u("uTerrainLight"), tl.x, tl.y, tl.z);
    g_.Uniform4f(u("uLightRule"), R::kFixedLightFloor, R::kTerrainAmbient, R::kTerrainDiffuse, R::kTerrainLightCap);
    g_.GenVertexArrays(1, &vao_);
    g_.BindVertexArray(vao_);
    g_.GenBuffers(1, &streamVbo_);
    g_.GenBuffers(1, &streamIbo_);
    g_.GenTextures(1, &streamWeight_);
    // Both samplers always have a complete texture behind them, whatever
    // the driver makes of a sampler the frame does not use.
    {
      static const float one = 1.0f;
      static const uint8_t white[4] = {255, 255, 255, 255};
      g_.ActiveTexture(TEXTURE0 + 1);
      uploadWeight(streamWeight_, &one, 1);
      g_.ActiveTexture(TEXTURE0);
      g_.GenTextures(1, &blank_);
      g_.BindTexture(TEXTURE_2D, blank_);
      g_.TexImage2D(TEXTURE_2D, 0, RGBA8, 1, 1, 0, RGBA, UNSIGNED_BYTE, white);
      g_.TexParameteri(TEXTURE_2D, TEXTURE_MIN_FILTER, NEAREST);
      g_.TexParameteri(TEXTURE_2D, TEXTURE_MAG_FILTER, NEAREST);
    }
    g_.GenFramebuffers(1, &fbo_);
    g_.GenRenderbuffers(1, &colorRb_);
    g_.GenRenderbuffers(1, &depthRb_);
    g_.PixelStorei(UNPACK_ALIGNMENT, 4);
    g_.PixelStorei(PACK_ALIGNMENT, 4);
    g_.Disable(CULL_FACE);
    if (g_.GetError() != NO_ERROR) {
      why = "GL error while setting up";
      return false;
    }
    return true;
  }

  const char* name() const override { return "opengl"; }
  std::string description() const override { return ctx_->description(); }

  R::DrawStats draw(R::Frame frame, const R::Scene& scene, R::Resources& res) override {
    R::DrawStats stats;
    if (frame.width <= 0 || frame.height <= 0 || !frame.pixels) return stats;
    if (!scene.hasCamera) {
      for (int y = 0; y < frame.height; ++y)
        for (int x = 0; x < frame.width; ++x) frame.at(x, y) = R::packRgba(0, 0, 0);
      return stats;
    }
    ctx_->make_current();
    ++frameNo_;
    if (!framebuffer(frame.width, frame.height)) {
      // Should not happen once set up; draw nothing rather than garbage.
      for (int y = 0; y < frame.height; ++y)
        for (int x = 0; x < frame.width; ++x) frame.at(x, y) = R::packRgba(0, 0, 0);
      return stats;
    }
    g_.UseProgram(program_);
    g_.BindVertexArray(vao_);

    R::View view = scene.view;
    const float farPlane = R::gVisibleDistance3D;
    view.farPlane = farPlane;
    viewProj_ = viewProjection(view, frame.width, frame.height);
    const uint32_t fog = R::sceneFogColor(scene);

    // The fog colour below the horizon, alpha kept at full.
    g_.ColorMask(1, 1, 1, 1);
    g_.DepthMask(1);
    g_.ClearColor(R::red(fog) / 255.0f, R::green(fog) / 255.0f, R::blue(fog) / 255.0f, 1.0f);
    g_.ClearDepth(1.0);
    g_.Clear(COLOR_BUFFER_BIT | DEPTH_BUFFER_BIT);
    g_.ColorMask(1, 1, 1, 0);

    if (scene.sky.present) {
      Batch batch(*this);
      R::skyBoxTriangles(scene, res, farPlane, fog, batch.sink());
      batch.flush();
      g_.DepthMask(1);
      g_.Clear(DEPTH_BUFFER_BIT);
      checkError("sky");
    }

    std::unordered_set<const R::Shape*> owned;
    for (const auto& s : scene.owned) owned.insert(s.get());

    for (const R::SceneObject& obj : scene.objects) {
      const R::Shape* shape = obj.direct ? obj.direct : res.shape(obj.shape, !obj.replica);
      if (!shape) {
        ++stats.objectsMissing;
        continue;
      }
      if (shape->kind == R::Shape::kFt && !R::gDrawFtTrees) continue;
      ++stats.objectsDrawn;
      const bool stream = owned.count(shape) != 0;
      for (const R::Mesh& mesh : shape->meshes)
        stats.triangles += drawMesh(*shape, mesh, obj, scene, res, fog, stream);
    }

    {
      Batch batch(*this);
      for (const R::WaterSurface& w : scene.water) stats.triangles += R::waterTriangles(w, scene.time, fog, res, batch.sink());
      batch.flush();
    }
    checkError("shapes and water");

    readBack(frame);
    checkError("read-back");
    evict();
    stats.labels = R::sceneLabels(scene, res, frame.width, frame.height);
    return stats;
  }

 private:
  struct Run {
    int material;
    uint32_t first, count;  // in indices
  };
  struct MeshGpu {
    uint64_t fp = 0;
    GLuint vbo = 0, ibo = 0, weight = 0;
    std::vector<Run> runs;
    int used = 0;
  };
  struct TexGpu {
    uint64_t fp = 0;
    GLuint tex = 0;
    GLint wrap = -1, filter = -1;
    int used = 0;
  };

  // Streams the sky's and water's triangles, one draw per run of the same
  // state, in order.
  class Batch {
   public:
    explicit Batch(GlRenderer& r) : r_(r) {}
    R::TriangleSink sink() {
      return [this](const R::RasterVertex& a, const R::RasterVertex& b, const R::RasterVertex& c,
                    const R::RasterState& st) {
        if (!verts_.empty() && !same_state(st, state_)) flush();
        state_ = st;
        for (const R::RasterVertex* v : {&a, &b, &c})
          verts_.push_back({{v->position.x, v->position.y, v->position.z},
                            {0, 0, 0},
                            {v->u, v->v},
                            {v->light[0], v->fog}});
      };
    }
    void flush() {
      if (verts_.empty()) return;
      r_.drawStream(verts_, state_);
      verts_.clear();
    }

   private:
    GlRenderer& r_;
    R::RasterState state_;
    std::vector<StreamVertex> verts_;
  };

  GLuint compile(GLenum type, const char* src, std::string& why) {
    GLuint s = g_.CreateShader(type);
    g_.ShaderSource(s, 1, &src, nullptr);
    g_.CompileShader(s);
    GLint ok = 0;
    g_.GetShaderiv(s, COMPILE_STATUS, &ok);
    if (!ok) {
      GLint n = 0;
      g_.GetShaderiv(s, INFO_LOG_LENGTH, &n);
      std::string log(size_t(std::max(1, n)), '\0');
      g_.GetShaderInfoLog(s, n, nullptr, log.data());
      why = std::string(type == VERTEX_SHADER ? "vertex" : "fragment") + " shader failed: " + log.c_str();
      g_.DeleteShader(s);
      return 0;
    }
    return s;
  }
  std::string program_log() {
    GLint n = 0;
    g_.GetProgramiv(program_, INFO_LOG_LENGTH, &n);
    std::string log(size_t(std::max(1, n)), '\0');
    g_.GetProgramInfoLog(program_, n, nullptr, log.data());
    return log.c_str();
  }

  bool framebuffer(int w, int h) {
    if (w == fbw_ && h == fbh_) {
      g_.BindFramebuffer(FRAMEBUFFER, fbo_);
      g_.Viewport(0, 0, w, h);
      return true;
    }
    g_.BindFramebuffer(FRAMEBUFFER, fbo_);
    g_.BindRenderbuffer(RENDERBUFFER, colorRb_);
    g_.RenderbufferStorage(RENDERBUFFER, RGBA8, w, h);
    g_.BindRenderbuffer(RENDERBUFFER, depthRb_);
    g_.RenderbufferStorage(RENDERBUFFER, DEPTH24_STENCIL8, w, h);
    g_.FramebufferRenderbuffer(FRAMEBUFFER, COLOR_ATTACHMENT0, RENDERBUFFER, colorRb_);
    g_.FramebufferRenderbuffer(FRAMEBUFFER, DEPTH_STENCIL_ATTACHMENT, RENDERBUFFER, depthRb_);
    if (g_.CheckFramebufferStatus(FRAMEBUFFER) != FRAMEBUFFER_COMPLETE) return false;
    fbw_ = w;
    fbh_ = h;
    g_.Viewport(0, 0, w, h);
    return true;
  }

  // World to clip, matching the rasteriser's projection (raster.cpp): the
  // horizontal field of view sets the focal length, the camera's +y is
  // forward and +z up, and image row 0 is the top (so the read-back needs
  // no flip; y is negated, which only mirrors the winding, and nothing is
  // culled).
  R::M4 viewProjection(const R::View& view, int w, int h) const {
    float fov = view.fovDegrees;
    if (!(fov > 1.0f)) fov = 1.0f;
    if (fov > 179.0f) fov = 179.0f;
    const double halfTan = std::tan(double(fov) * 3.14159265358979 / 360.0);
    const double aspect = double(w) / double(h);
    const double n = view.nearPlane, f = view.farPlane;
    R::M4 p;
    for (auto& row : p.m)
      for (float& v : row) v = 0;
    p.m[0][0] = float(1.0 / halfTan);               // x right
    p.m[1][2] = float(-aspect / halfTan);           // z up, rows top first
    p.m[2][1] = float((f + n) / (f - n));           // y forward is depth
    p.m[2][3] = float(-2.0 * f * n / (f - n));
    p.m[3][1] = 1.0f;
    return p * view.cameraToWorld.rigidInverse();
  }

  void setMatrices(const R::M4& model) {
    float mvp[16];
    to_gl(viewProj_ * model, mvp);
    g_.UniformMatrix4fv(uMVP_, 1, 0, mvp);
    float n[9];
    for (int c = 0; c < 3; ++c)
      for (int r = 0; r < 3; ++r) n[c * 3 + r] = model.m[r][c];
    g_.UniformMatrix3fv(uNormalM_, 1, 0, n);
  }

  // The texture's GL object, uploaded on first use; null for none.
  GLuint texture(const R::Texture* t, bool clamp, bool bilinear) {
    if (!t || t->empty()) return 0;
    TexGpu& e = textures_[t];
    const uint64_t fp = fingerprint(t->pixels, uint64_t(t->width) * 65537u + uint64_t(t->height));
    if (!e.tex || e.fp != fp) {
      if (!e.tex) g_.GenTextures(1, &e.tex);
      g_.BindTexture(TEXTURE_2D, e.tex);
      g_.TexImage2D(TEXTURE_2D, 0, RGBA8, t->width, t->height, 0, RGBA, UNSIGNED_BYTE, t->pixels.data());
      e.fp = fp;
      e.wrap = e.filter = -1;
    } else {
      g_.BindTexture(TEXTURE_2D, e.tex);
    }
    const GLint wrap = clamp ? GLint(CLAMP_TO_EDGE) : GLint(REPEAT);
    const GLint filter = bilinear ? GLint(LINEAR) : GLint(NEAREST);
    if (e.wrap != wrap) {
      g_.TexParameteri(TEXTURE_2D, TEXTURE_WRAP_S, wrap);
      g_.TexParameteri(TEXTURE_2D, TEXTURE_WRAP_T, wrap);
      e.wrap = wrap;
    }
    if (e.filter != filter) {
      g_.TexParameteri(TEXTURE_2D, TEXTURE_MIN_FILTER, filter);
      g_.TexParameteri(TEXTURE_2D, TEXTURE_MAG_FILTER, filter);
      e.filter = filter;
    }
    e.used = frameNo_;
    return e.tex;
  }

  void uploadWeight(GLuint tex, const float* map, int size) {
    g_.BindTexture(TEXTURE_2D, tex);
    g_.TexImage2D(TEXTURE_2D, 0, R32F, size, size, 0, RED, FLOAT, map);
    g_.TexParameteri(TEXTURE_2D, TEXTURE_WRAP_S, REPEAT);
    g_.TexParameteri(TEXTURE_2D, TEXTURE_WRAP_T, REPEAT);
    g_.TexParameteri(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);
    g_.TexParameteri(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
  }

  // GL state for one RasterState. `weightTex` is the layer's weight map
  // when the state is additive.
  void apply(const R::RasterState& st, GLuint weightTex) {
    if (st.depthTest) {
      g_.Enable(DEPTH_TEST);
      g_.DepthFunc(st.additive ? LEQUAL : LESS);
    } else {
      g_.Disable(DEPTH_TEST);
    }
    g_.DepthMask(st.depthWrite ? 1 : 0);
    if (st.additive) {
      g_.Enable(BLEND);
      g_.BlendFunc(ONE, ONE);
    } else if (st.opacity < 1) {
      g_.Enable(BLEND);
      g_.BlendFunc(SRC_ALPHA, ONE_MINUS_SRC_ALPHA);
    } else {
      g_.Disable(BLEND);
    }
    g_.Uniform1f(uOpacity_, st.opacity < 0 ? 0.0f : st.opacity);
    g_.ActiveTexture(TEXTURE0);
    const GLuint tex = texture(st.texture, st.clampTexture, st.bilinear);
    if (!tex) g_.BindTexture(TEXTURE_2D, blank_);
    g_.Uniform1i(uTextured_, tex ? 1 : 0);
    g_.Uniform1i(uAlphaTest_, st.alphaTest ? 1 : 0);
    g_.Uniform3f(uColor_, st.color[0], st.color[1], st.color[2]);
    g_.Uniform3f(uFogColor_, R::red(st.fogColor) / 255.0f, R::green(st.fogColor) / 255.0f,
                 R::blue(st.fogColor) / 255.0f);
    const bool weighted = st.additive && st.weightMap && st.weightSize > 0 && weightTex;
    g_.Uniform1i(uAdditive_, st.additive ? 1 : 0);
    if (st.additive) {
      g_.ActiveTexture(TEXTURE0 + 1);
      if (weighted) {
        g_.BindTexture(TEXTURE_2D, weightTex);
        g_.Uniform1f(uWeightScale_, st.weightScale);
        g_.Uniform1f(uWeightSize_, float(st.weightSize));
      } else {
        // No map: weight 1 everywhere.
        static const float one = 1.0f;
        uploadWeight(streamWeight_, &one, 1);
        g_.Uniform1f(uWeightScale_, 1.0f);
        g_.Uniform1f(uWeightSize_, 1.0f);
      }
      g_.ActiveTexture(TEXTURE0);
    }
  }

  void pointAttributes(bool lightFog) {
    const GLsizei stride = lightFog ? GLsizei(sizeof(StreamVertex)) : GLsizei(8 * sizeof(float));
    g_.EnableVertexAttribArray(kPos);
    g_.VertexAttribPointer(kPos, 3, FLOAT, 0, stride, reinterpret_cast<const void*>(0));
    g_.EnableVertexAttribArray(kNormal);
    g_.VertexAttribPointer(kNormal, 3, FLOAT, 0, stride, reinterpret_cast<const void*>(3 * sizeof(float)));
    g_.EnableVertexAttribArray(kUV);
    g_.VertexAttribPointer(kUV, 2, FLOAT, 0, stride, reinterpret_cast<const void*>(6 * sizeof(float)));
    if (lightFog) {
      g_.EnableVertexAttribArray(kLightFog);
      g_.VertexAttribPointer(kLightFog, 2, FLOAT, 0, stride, reinterpret_cast<const void*>(8 * sizeof(float)));
    } else {
      g_.DisableVertexAttribArray(kLightFog);
      g_.VertexAttrib2f(kLightFog, 1.0f, 0.0f);
    }
  }

  void drawStream(const std::vector<StreamVertex>& verts, const R::RasterState& st) {
    setMatrices(R::M4::identity());
    g_.Uniform1i(uLightMode_, 0);
    GLuint weight = 0;
    if (st.additive && st.weightMap && st.weightSize > 0) {
      uploadWeight(streamWeight_, st.weightMap, st.weightSize);
      weight = streamWeight_;
    }
    apply(st, weight);
    g_.BindBuffer(ARRAY_BUFFER, streamVbo_);
    g_.BufferData(ARRAY_BUFFER, GLsizeiptr(verts.size() * sizeof(StreamVertex)), verts.data(), STREAM_DRAW);
    pointAttributes(true);
    g_.DrawArrays(TRIANGLES, 0, GLsizei(verts.size()));
  }

  // Builds a mesh's vertex and index data: runs of consecutive triangles
  // with the same drawable material, in the mesh's order.
  static void meshData(const R::Shape& shape, const R::Mesh& mesh, std::vector<float>& verts,
                       std::vector<uint32_t>& idx, std::vector<Run>& runs) {
    verts.resize(mesh.vertices.size() * 8);
    for (size_t i = 0; i < mesh.vertices.size(); ++i) {
      const R::Vertex& v = mesh.vertices[i];
      float* o = &verts[i * 8];
      o[0] = v.position.x;
      o[1] = v.position.y;
      o[2] = v.position.z;
      o[3] = v.normal.x;
      o[4] = v.normal.y;
      o[5] = v.normal.z;
      o[6] = v.u;
      o[7] = v.v;
    }
    idx.clear();
    runs.clear();
    idx.reserve(mesh.triangles.size() * 3);
    for (const R::Triangle& t : mesh.triangles) {
      if (t.material < 0 || size_t(t.material) >= shape.materials.size()) continue;  // not drawn
      if (t.v[0] >= mesh.vertices.size() || t.v[1] >= mesh.vertices.size() || t.v[2] >= mesh.vertices.size())
        continue;
      if (runs.empty() || runs.back().material != t.material)
        runs.push_back({t.material, uint32_t(idx.size()), 0});
      idx.insert(idx.end(), {t.v[0], t.v[1], t.v[2]});
      runs.back().count += 3;
    }
  }

  long drawMesh(const R::Shape& shape, const R::Mesh& mesh, const R::SceneObject& obj, const R::Scene& scene,
                R::Resources& res, uint32_t fog, bool stream) {
    if (mesh.triangles.empty() || mesh.vertices.empty()) return 0;
    const std::vector<Run>* runs = nullptr;
    GLuint weight = 0;
    std::vector<Run> streamRuns;
    if (stream) {
      std::vector<float> verts;
      std::vector<uint32_t> idx;
      meshData(shape, mesh, verts, idx, streamRuns);
      if (streamRuns.empty()) return 0;
      g_.BindBuffer(ARRAY_BUFFER, streamVbo_);
      g_.BufferData(ARRAY_BUFFER, GLsizeiptr(verts.size() * sizeof(float)), verts.data(), STREAM_DRAW);
      g_.BindBuffer(ELEMENT_ARRAY_BUFFER, streamIbo_);
      g_.BufferData(ELEMENT_ARRAY_BUFFER, GLsizeiptr(idx.size() * sizeof(uint32_t)), idx.data(), STREAM_DRAW);
      if (!mesh.weightMap.empty() && mesh.weightSize > 0) {
        uploadWeight(streamWeight_, mesh.weightMap.data(), mesh.weightSize);
        weight = streamWeight_;
      }
      runs = &streamRuns;
    } else {
      MeshGpu& m = meshes_[&mesh];
      const uint64_t fp = mesh_fingerprint(mesh);
      if (!m.vbo || m.fp != fp) {
        release(m);
        std::vector<float> verts;
        std::vector<uint32_t> idx;
        meshData(shape, mesh, verts, idx, m.runs);
        g_.GenBuffers(1, &m.vbo);
        g_.GenBuffers(1, &m.ibo);
        g_.BindBuffer(ARRAY_BUFFER, m.vbo);
        g_.BufferData(ARRAY_BUFFER, GLsizeiptr(verts.size() * sizeof(float)), verts.data(), STATIC_DRAW);
        g_.BindBuffer(ELEMENT_ARRAY_BUFFER, m.ibo);
        g_.BufferData(ELEMENT_ARRAY_BUFFER, GLsizeiptr(idx.size() * sizeof(uint32_t)), idx.data(), STATIC_DRAW);
        if (!mesh.weightMap.empty() && mesh.weightSize > 0 &&
            mesh.weightMap.size() >= size_t(mesh.weightSize) * size_t(mesh.weightSize)) {
          g_.GenTextures(1, &m.weight);
          uploadWeight(m.weight, mesh.weightMap.data(), mesh.weightSize);
        }
        m.fp = fp;
      }
      m.used = frameNo_;
      g_.BindBuffer(ARRAY_BUFFER, m.vbo);
      g_.BindBuffer(ELEMENT_ARRAY_BUFFER, m.ibo);
      weight = m.weight;
      runs = &m.runs;
    }
    pointAttributes(false);
    setMatrices(obj.transform);
    // The lighting rule of this kind of shape (draw.cpp vertexLight).
    const bool sun = scene.sun.present;
    if (shape.kind == R::Shape::k3ds && sun) {
      g_.Uniform1i(uLightMode_, 1);
    } else if (shape.kind == R::Shape::kTerrain && sun) {
      g_.Uniform1i(uLightMode_, 2);
    } else {
      g_.Uniform1i(uLightMode_, 3);
      g_.Uniform1f(uLight_, R::vertexLight(shape.kind, sun, R::V3{0, 0, 1}));
    }
    long triangles = 0;
    for (const Run& run : *runs) {
      const R::RasterState st = R::materialState(shape, mesh, shape.materials[size_t(run.material)], res,
                                                 !obj.replica, fog);
      apply(st, weight);
      g_.DrawElements(TRIANGLES, GLsizei(run.count), UNSIGNED_INT,
                      reinterpret_cast<const void*>(size_t(run.first) * sizeof(uint32_t)));
      triangles += run.count / 3;
    }
    return triangles;
  }

  void readBack(R::Frame frame) {
    if (frame.stride == frame.width) {
      g_.ReadPixels(0, 0, frame.width, frame.height, RGBA, UNSIGNED_BYTE, frame.pixels);
      return;
    }
    readBuf_.resize(size_t(frame.width) * frame.height);
    g_.ReadPixels(0, 0, frame.width, frame.height, RGBA, UNSIGNED_BYTE, readBuf_.data());
    for (int y = 0; y < frame.height; ++y)
      std::memcpy(&frame.at(0, y), &readBuf_[size_t(y) * frame.width], size_t(frame.width) * 4);
  }

  // A GL error is a renderer bug: the first few go to stderr.
  void checkError(const char* where) {
    for (GLenum e = g_.GetError(); e != NO_ERROR; e = g_.GetError())
      if (errorsLogged_ < 8) {
        ++errorsLogged_;
        std::fprintf(stderr, "opengl: GL error 0x%04x (%s, frame %d)\n", unsigned(e), where, frameNo_);
      }
  }

  void release(MeshGpu& m) {
    if (m.vbo) g_.DeleteBuffers(1, &m.vbo);
    if (m.ibo) g_.DeleteBuffers(1, &m.ibo);
    if (m.weight) g_.DeleteTextures(1, &m.weight);
    m.vbo = m.ibo = m.weight = 0;
  }

  // GPU copies not drawn for a few frames go: their shape may be gone.
  void evict() {
    constexpr int kKeepFrames = 3;
    for (auto it = meshes_.begin(); it != meshes_.end();) {
      if (frameNo_ - it->second.used > kKeepFrames) {
        release(it->second);
        it = meshes_.erase(it);
      } else {
        ++it;
      }
    }
    for (auto it = textures_.begin(); it != textures_.end();) {
      if (frameNo_ - it->second.used > kKeepFrames) {
        g_.DeleteTextures(1, &it->second.tex);
        it = textures_.erase(it);
      } else {
        ++it;
      }
    }
  }

  std::unique_ptr<Context> ctx_;
  const Api& g_;
  GLuint program_ = 0, vao_ = 0, streamVbo_ = 0, streamIbo_ = 0, streamWeight_ = 0;
  GLuint fbo_ = 0, colorRb_ = 0, depthRb_ = 0;
  int fbw_ = 0, fbh_ = 0;
  GLint uMVP_ = -1, uNormalM_ = -1, uLightMode_ = -1, uLight_ = -1, uTextured_ = -1, uAlphaTest_ = -1,
        uAdditive_ = -1, uColor_ = -1, uFogColor_ = -1, uOpacity_ = -1, uWeightScale_ = -1, uWeightSize_ = -1;
  R::M4 viewProj_;
  int frameNo_ = 0;
  int errorsLogged_ = 0;
  GLuint blank_ = 0;
  std::unordered_map<const R::Mesh*, MeshGpu> meshes_;
  std::unordered_map<const R::Texture*, TexGpu> textures_;
  std::vector<uint32_t> readBuf_;
};

}  // namespace

std::unique_ptr<SceneRenderer> make_gl_renderer(std::string& why) {
  std::unique_ptr<Context> ctx = Context::open(why);
  if (!ctx) return nullptr;
  auto r = std::make_unique<GlRenderer>(std::move(ctx));
  if (!r->init(why)) return nullptr;
  return r;
}

}  // namespace Frank
