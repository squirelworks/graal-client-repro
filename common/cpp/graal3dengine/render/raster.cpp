#include "raster.hpp"

#include <algorithm>
#include <cmath>

namespace graal3d::render {

Rasterizer::Rasterizer(Frame frame) : frame_(frame), depth_(size_t(std::max(0, frame.width * frame.height)), 0.0f) {
  setView(View{});
}

void Rasterizer::setView(const View& view) {
  view_ = view;
  worldToCamera_ = view.cameraToWorld.rigidInverse();
  float fov = view.fovDegrees;
  if (!(fov > 1.0f)) fov = 1.0f;
  if (fov > 179.0f) fov = 179.0f;
  const float halfTan = std::tan(fov * 3.14159265358979f / 360.0f);
  focal_ = (frame_.width * 0.5f) / halfTan;
}

bool projectPoint(const View& view, int width, int height, const V3& world, float& sx, float& sy, float& depth) {
  float fov = view.fovDegrees;
  if (!(fov > 1.0f)) fov = 1.0f;
  if (fov > 179.0f) fov = 179.0f;
  const float focal = (width * 0.5f) / std::tan(fov * 3.14159265358979f / 360.0f);
  const V3 c = view.cameraToWorld.rigidInverse().point(world);  // x right, y forward, z up
  depth = c.y;
  if (!(c.y > view.nearPlane)) return false;
  sx = width * 0.5f + c.x / c.y * focal;
  sy = height * 0.5f - c.z / c.y * focal;
  return std::isfinite(sx) && std::isfinite(sy);
}

void Rasterizer::clear(uint32_t color) {
  for (int y = 0; y < frame_.height; ++y)
    for (int x = 0; x < frame_.width; ++x) frame_.at(x, y) = color;
  clearDepth();
  written_ = 0;
}

void Rasterizer::clearDepth() { std::fill(depth_.begin(), depth_.end(), 0.0f); }

void Rasterizer::drawTriangle(const RasterVertex& a, const RasterVertex& b, const RasterVertex& c,
                              const RasterState& s) {
  ClipVertex in[3];
  const RasterVertex* src[3] = {&a, &b, &c};
  for (int i = 0; i < 3; ++i) {
    const V3 p = worldToCamera_.point(src[i]->position);
    in[i] = {p.x, p.z, p.y, src[i]->u, src[i]->v, {src[i]->light[0], src[i]->light[1], src[i]->light[2]}, src[i]->fog};
  }
  // Clip (Sutherland-Hodgman) against the near and far planes and the four
  // sides of the view, widened by a guard band: a triangle that reaches
  // behind the camera (a sky-box face, a floor under the eye) is cut to
  // what can be seen, so no corner projects to a huge screen position.
  // Each plane keeps the points where `side` is >= 0.
  constexpr float kGuard = 2.0f;
  const float gx = kGuard * frame_.width * 0.5f / focal_;
  const float gy = kGuard * frame_.height * 0.5f / focal_;
  const float nearPlane = view_.nearPlane, farPlane = view_.farPlane;
  auto side = [&](const ClipVertex& p, int plane) {
    switch (plane) {
      case 0: return p.d - nearPlane;
      case 1: return farPlane - p.d;
      case 2: return gx * p.d - p.x;
      case 3: return gx * p.d + p.x;
      case 4: return gy * p.d - p.y;
      default: return gy * p.d + p.y;
    }
  };
  ClipVertex bufA[kMaxClipVertices], bufB[kMaxClipVertices];
  ClipVertex* cur = bufA;
  ClipVertex* next = bufB;
  for (int i = 0; i < 3; ++i) cur[i] = in[i];
  int n = 3;
  for (int plane = 0; plane < 6; ++plane) {
    int k = 0;
    for (int i = 0; i < n; ++i) {
      const ClipVertex& p = cur[i];
      const ClipVertex& q = cur[(i + 1) % n];
      const float sp = side(p, plane), sq = side(q, plane);
      const bool pin = sp >= 0, qin = sq >= 0;
      if (pin) next[k++] = p;
      if (pin != qin) {
        const float t = sp / (sp - sq);
        ClipVertex r;
        r.x = p.x + (q.x - p.x) * t;
        r.y = p.y + (q.y - p.y) * t;
        r.d = p.d + (q.d - p.d) * t;
        if (plane == 0) r.d = nearPlane;
        if (plane == 1) r.d = farPlane;
        r.u = p.u + (q.u - p.u) * t;
        r.v = p.v + (q.v - p.v) * t;
        for (int j = 0; j < 3; ++j) r.l[j] = p.l[j] + (q.l[j] - p.l[j]) * t;
        r.fog = p.fog + (q.fog - p.fog) * t;
        next[k++] = r;
      }
    }
    n = k;
    if (n < 3) return;
    std::swap(cur, next);
  }
  drawClipped(cur, n, s);
}

namespace {

struct ScreenVertex {
  float sx, sy, iw;  // screen position and 1 / depth
  float u, v, l[3], fog;  // each divided by depth
};

inline float edge(const ScreenVertex& a, const ScreenVertex& b, float x, float y) {
  // Worked from the edge's ends in one fixed order, so the triangle on the
  // other side of a shared edge gets exactly the negated value (the fill
  // rule below depends on it).
  if (a.sy < b.sy || (a.sy == b.sy && a.sx < b.sx)) return (b.sx - a.sx) * (y - a.sy) - (b.sy - a.sy) * (x - a.sx);
  return -((a.sx - b.sx) * (y - b.sy) - (a.sy - b.sy) * (x - b.sx));
}

inline uint8_t clamp8(float v) {
  if (v <= 0) return 0;
  if (v >= 255) return 255;
  return uint8_t(v + 0.5f);
}

}  // namespace

void Rasterizer::drawClipped(const ClipVertex* poly, int count, const RasterState& s) {
  ScreenVertex sv[kMaxClipVertices];
  const float cx = frame_.width * 0.5f, cy = frame_.height * 0.5f;
  for (int i = 0; i < count; ++i) {
    const ClipVertex& p = poly[i];
    const float iw = 1.0f / p.d;
    sv[i].sx = cx + p.x * iw * focal_;
    sv[i].sy = cy - p.y * iw * focal_;
    sv[i].iw = iw;
    sv[i].u = p.u * iw;
    sv[i].v = p.v * iw;
    for (int j = 0; j < 3; ++j) sv[i].l[j] = p.l[j] * iw;
    sv[i].fog = p.fog * iw;
  }
  const uint8_t fr = red(s.fogColor), fg = green(s.fogColor), fb = blue(s.fogColor);
  for (int t = 1; t + 1 < count; ++t) {
    const ScreenVertex& a = sv[0];
    const ScreenVertex& b = sv[t];
    const ScreenVertex& c = sv[t + 1];
    float area = edge(a, b, c.sx, c.sy);
    if (!(std::fabs(area) >= 1e-6f) || !std::isfinite(area)) continue;  // also NaN
    // The guard band keeps real geometry well inside this; only bad data
    // (huge or NaN coordinates) gets here, and is skipped rather than
    // overflow the pixel bounds.
    const float kLimit = 1e6f;
    if (!(std::fabs(a.sx) < kLimit && std::fabs(b.sx) < kLimit && std::fabs(c.sx) < kLimit &&
          std::fabs(a.sy) < kLimit && std::fabs(b.sy) < kLimit && std::fabs(c.sy) < kLimit))
      continue;
    // Both windings are drawn; the depth buffer sorts them out.
    const float inv = 1.0f / area;
    // A pixel centre exactly on an edge belongs to one of the two triangles
    // that share it (a fill rule), so an additive layer adds it once: the
    // edge's owner is the triangle that runs it, inside on one fixed side,
    // downward (or rightward when level).
    const float sgn = area > 0 ? 1.0f : -1.0f;
    auto owns = [sgn](const ScreenVertex& p, const ScreenVertex& q) {
      const float dx = (q.sx - p.sx) * sgn, dy = (q.sy - p.sy) * sgn;
      return dy > 0 || (dy == 0 && dx > 0);
    };
    const bool own0 = owns(b, c), own1 = owns(c, a), own2 = owns(a, b);
    const int x0 = std::max(0, int(std::floor(std::min({a.sx, b.sx, c.sx}))));
    const int x1 = std::min(frame_.width - 1, int(std::ceil(std::max({a.sx, b.sx, c.sx}))));
    const int y0 = std::max(0, int(std::floor(std::min({a.sy, b.sy, c.sy}))));
    const int y1 = std::min(frame_.height - 1, int(std::ceil(std::max({a.sy, b.sy, c.sy}))));
    for (int y = y0; y <= y1; ++y) {
      const float py = y + 0.5f;
      for (int x = x0; x <= x1; ++x) {
        const float px = x + 0.5f;
        float w0 = edge(b, c, px, py) * inv;
        float w1 = edge(c, a, px, py) * inv;
        float w2 = edge(a, b, px, py) * inv;
        if (w0 < 0 || w1 < 0 || w2 < 0) continue;
        if ((w0 == 0 && !own0) || (w1 == 0 && !own1) || (w2 == 0 && !own2)) continue;
        const float iw = w0 * a.iw + w1 * b.iw + w2 * c.iw;
        if (iw <= 0) continue;
        float& dz = depth_[size_t(y) * frame_.width + x];
        if (s.depthTest && (s.additive ? iw < dz : iw <= dz)) continue;
        const float z = 1.0f / iw;
        const float u = (w0 * a.u + w1 * b.u + w2 * c.u) * z;
        const float v = (w0 * a.v + w1 * b.v + w2 * c.v) * z;
        float l[3];
        for (int j = 0; j < 3; ++j) l[j] = (w0 * a.l[j] + w1 * b.l[j] + w2 * c.l[j]) * z;
        float fog = (w0 * a.fog + w1 * b.fog + w2 * c.fog) * z;
        fog = fog < 0 ? 0 : (fog > 1 ? 1 : fog);
        const uint32_t texel = !s.texture    ? packRgba(255, 255, 255)
                               : s.bilinear ? s.texture->sampleBilinear(u, v, s.clampTexture)
                                            : s.texture->sample(u, v);
        if (s.alphaTest && alpha(texel) < 128) continue;  // cut-out foliage
        float r = red(texel) * s.color[0] * l[0];
        float g = green(texel) * s.color[1] * l[1];
        float bch = blue(texel) * s.color[2] * l[2];
        r = r + (fr - r) * fog;
        g = g + (fg - g) * fog;
        bch = bch + (fb - bch) * fog;
        if (s.additive) {
          float wt = 1;
          if (s.weightMap && s.weightSize > 0) {
            const int n = s.weightSize;
            const float gx = u * s.weightScale, gy = v * s.weightScale;
            const float fx = std::floor(gx), fy = std::floor(gy);
            const float ax = gx - fx, ay = gy - fy;
            auto wrap = [n](float f) {
              if (!std::isfinite(f)) return 0;
              int i = int(std::fmod(f, float(n)));
              return i < 0 ? i + n : i;
            };
            const int x0 = wrap(fx), y0 = wrap(fy), x1 = (x0 + 1) % n, y1 = (y0 + 1) % n;
            const float* m = s.weightMap;
            const float top = m[size_t(y0) * n + x0] * (1 - ax) + m[size_t(y0) * n + x1] * ax;
            const float bot = m[size_t(y1) * n + x0] * (1 - ax) + m[size_t(y1) * n + x1] * ax;
            wt = top * (1 - ay) + bot * ay;
          }
          const uint32_t under = frame_.at(x, y);
          r = red(under) + r * wt;
          g = green(under) + g * wt;
          bch = blue(under) + bch * wt;
        } else if (s.opacity < 1) {
          const uint32_t under = frame_.at(x, y);
          const float o = s.opacity < 0 ? 0 : s.opacity;
          r = red(under) + (r - red(under)) * o;
          g = green(under) + (g - green(under)) * o;
          bch = blue(under) + (bch - blue(under)) * o;
        }
        frame_.at(x, y) = packRgba(clamp8(r), clamp8(g), clamp8(bch));
        if (s.depthWrite) dz = iw;
        ++written_;
      }
    }
  }
}

}  // namespace graal3d::render
