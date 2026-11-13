#include "showimg.hpp"

#include "host.hpp"
#include "../../quattro/draw/assets.hpp"
#include "../../quattro/draw/world.hpp"

#include <algorithm>
#include <cmath>

namespace graalengine {

namespace QD = Quattro::Draw;

namespace {

void toArgb(const Torque::Gui::Image& img, std::vector<uint32_t>& out) {
  out.resize(img.pixels.size());
  for (std::size_t i = 0; i < img.pixels.size(); ++i) {
    const auto& c = img.pixels[i];
    out[i] = (uint32_t(c.a) << 24) | (uint32_t(c.r) << 16) | (uint32_t(c.g) << 8) | c.b;
  }
}

std::string firstField(const std::string& s) {
  const auto comma = s.find(',');
  std::string out = comma == std::string::npos ? s : s.substr(0, comma);
  while (!out.empty() && out.back() == ' ') out.pop_back();
  return out;
}

}  // namespace

ShowImgPainter::ShowImgPainter(const std::string& installDir) {
  auto dirs = QD::asset_dirs(installDir);
  // The 4.x installs keep particle pictures (g4_particle_smoke.png) here.
  if (!installDir.empty()) dirs.push_back(installDir + "/levels/particles");
  assets_ = std::make_unique<QD::Assets>(std::move(dirs));
  renderer_ = std::make_unique<QD::WorldRenderer>();
  renderer_->set_assets(assets_.get());
}

ShowImgPainter::~ShowImgPainter() = default;

bool ShowImgPainter::drawControl(const gs2::gui::Control& c, const gs2::gui::Rect& r) {
  const std::string ani = firstField(c.prop("ani"));
  if (ani.empty() || r.w <= 0 || r.h <= 0 || !assets_->gani(ani)) return false;
  Tex& t = controls_[&c];
  if (t.ani != ani) {  // a new gani plays from its first step
    t.ani = ani;
    t.start = frame_;
  }
  QD::Actor a;
  a.gani = ani;
  a.dir = static_cast<int>(c.numProp("dir", 2)) & 3;
  a.ani_tick = frame_ - t.start;
  if (c.actor) {
    if (auto v = c.actor->child("head")) a.head = v->string();
    if (auto v = c.actor->child("body")) a.body = v->string();
    if (auto v = c.actor->child("sword")) a.sword = v->string();
    if (auto v = c.actor->child("shield")) a.shield = v->string();
    if (auto v = c.actor->child("attr"))
      for (std::size_t i = 1; i < a.attr.size() && i < v->elements().size(); ++i) {
        const std::string s = v->elements()[i]->string();
        if (!s.empty() && s != "0") a.attr[i] = s;
      }
  }
  Torque::Gui::Canvas canvas(r.w, r.h, {0, 0, 0, 0});
  renderer_->draw_actor(canvas, a, static_cast<int>(c.numProp("offsetx")), static_cast<int>(c.numProp("offsety")),
                        {0, 0, 0, 0});
  toArgb(canvas.surface(), t.pixels);
  t.tex.name = "showimg";
  t.tex.width = r.w;
  t.tex.height = r.h;
  t.tex.pixels = t.pixels.data();
  host::DrawGraphics(&t.tex, r.x, r.y, 0, 0, r.w, r.h, 0xFFFFFFFFu);
  return true;
}

void ShowImgPainter::sprite(const std::string& file, double x, double y, double rotation, double sx, double sy,
                            const double* rgba, int /*mode*/) {
  const Torque::Gui::Image* img = assets_->image(file);
  if (!img || img->empty() || sx == 0 || sy == 0) return;
  double tint[4] = {1, 1, 1, 1};
  if (rgba)
    for (int i = 0; i < 4; ++i) tint[i] = std::max(0.0, std::min(1.0, rgba[i]));
  const double hw = img->width / 2.0, hh = img->height / 2.0;
  const double c = std::cos(rotation), s = std::sin(rotation);
  const double ex = std::abs(c * hw * sx) + std::abs(s * hh * sy), ey = std::abs(s * hw * sx) + std::abs(c * hh * sy);
  const int x0 = static_cast<int>(std::floor(x - ex)), y0 = static_cast<int>(std::floor(y - ey));
  const int w = static_cast<int>(std::ceil(x + ex)) - x0, h = static_cast<int>(std::ceil(y + ey)) - y0;
  if (w <= 0 || h <= 0 || w > 4096 || h > 4096) return;
  particle_.pixels.assign(std::size_t(w) * h, 0);
  for (int py = 0; py < h; ++py)
    for (int px = 0; px < w; ++px) {
      // Nearest pixel through the inverse of the turn and scale.
      const double dx = x0 + px + 0.5 - x, dy = y0 + py + 0.5 - y;
      const double u = (c * dx + s * dy) / sx + hw, v = (-s * dx + c * dy) / sy + hh;
      const int iu = static_cast<int>(std::floor(u)), iv = static_cast<int>(std::floor(v));
      if (iu < 0 || iv < 0 || iu >= img->width || iv >= img->height) continue;
      const auto& p = img->at(iu, iv);
      const double a = p.a * tint[3];
      if (a < 1) continue;
      auto ch = [](double v) { return static_cast<uint32_t>(std::max(0.0, std::min(255.0, v))); };
      particle_.pixels[std::size_t(py) * w + px] =
          (ch(a) << 24) | (ch(p.r * tint[0]) << 16) | (ch(p.g * tint[1]) << 8) | ch(p.b * tint[2]);
    }
  particle_.tex.name = "particle";
  particle_.tex.width = w;
  particle_.tex.height = h;
  particle_.tex.pixels = particle_.pixels.data();
  host::DrawGraphics(&particle_.tex, x0, y0, 0, 0, w, h, 0xFFFFFFFFu);
}

}  // namespace graalengine
