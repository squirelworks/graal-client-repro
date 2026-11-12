#include "gui_host.hpp"

#include "../../gs2/startscripts.hpp"
#include "../draw/ui_font.hpp"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <fstream>
#include <iterator>

namespace Quattro::Shell {

namespace {

Torque::Gui::Rect to_tq(const gs2::gui::Rect& r) { return {r.x, r.y, r.w, r.h}; }
Torque::Gui::Color to_tq(gs2::gui::Color c) { return {c.r, c.g, c.b, c.a}; }

std::string lower(std::string s) {
  for (char& ch : s) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  return s;
}

bool bold_face(const std::string& font) {
  std::string f = lower(font);
  return f.find("bold") != std::string::npos || f.find("bd") != std::string::npos;
}

bool has_extension(const std::string& f) {
  size_t slash = f.find_last_of("/\\");
  size_t dot = f.find_last_of('.');
  return dot != std::string::npos && (slash == std::string::npos || dot > slash);
}

// Script file names may use either slash; keep them inside the folder.
std::string safe_name(const std::string& f) {
  std::string out;
  for (char ch : f) out += ch == '\\' ? '/' : ch;
  if (out.find("..") != std::string::npos) return {};
  while (!out.empty() && out[0] == '/') out.erase(0, 1);
  return out;
}

}  // namespace

CanvasPainter::CanvasPainter(Torque::Gui::Canvas& canvas, std::vector<std::string> dirs)
    : canvas_(canvas), dirs_(std::move(dirs)) {}

CanvasPainter::~CanvasPainter() { reset_clip(); }

void CanvasPainter::reset_clip() {
  if (clipped_) canvas_.pop_clip();
  clipped_ = false;
}

void CanvasPainter::setClip(const gs2::gui::Rect& r) {
  reset_clip();
  canvas_.push_clip(to_tq(r));
  clipped_ = true;
}

void CanvasPainter::fill(const gs2::gui::Rect& r, gs2::gui::Color c) { canvas_.fill_rect(to_tq(r), to_tq(c)); }

void CanvasPainter::text(int x, int y, const std::string& s, const std::string& font, int, gs2::gui::Color c) {
  Draw::ui_draw_text(canvas_, x, y, s, to_tq(c), bold_face(font));
}

int CanvasPainter::textWidth(const std::string& s, const std::string& font, int) {
  return Draw::ui_text_width(s, bold_face(font));
}

int CanvasPainter::fontHeight(const std::string&, int) { return Draw::kUiLineHeight; }

CanvasPainter::Entry& CanvasPainter::load(const std::string& file) {
  auto it = cache_.find(file);
  if (it != cache_.end()) return it->second;
  Entry& e = cache_[file];
  std::string name = safe_name(file);
  if (name.empty()) return e;
  std::vector<std::string> names = {name};
  if (!has_extension(name)) names.push_back(name + ".png");
  for (const auto& dir : dirs_) {
    for (const auto& n : names) {
      std::vector<std::uint8_t> bytes;
      std::string err;
      if (Torque::Gui::read_file(dir + "/" + n, bytes, err) && Torque::Gui::decode_png(bytes, e.image, err)) {
        e.ok = true;
        return e;
      }
    }
  }
  return e;
}

bool CanvasPainter::bitmapSize(const std::string& file, int& w, int& h) {
  Entry& e = load(file);
  if (!e.ok) return false;
  w = e.image.width;
  h = e.image.height;
  return true;
}

std::vector<gs2::gui::Rect> CanvasPainter::cells(const std::string& file) {
  Entry& e = load(file);
  if (!e.ok) return {};
  if (!e.split) {
    e.split = true;
    Torque::Gui::BitmapArray a = Torque::Gui::split_bitmap_array(e.image);
    // A plain picture splits into one cell covering it: no theme cells.
    if (a.cells.size() > 1)
      for (const auto& r : a.cells) e.cells.push_back({r.x, r.y, r.width, r.height});
  }
  return e.cells;
}

void CanvasPainter::bitmap(const std::string& file, const gs2::gui::Rect& src, const gs2::gui::Rect& dst) {
  Entry& e = load(file);
  if (!e.ok || dst.w <= 0 || dst.h <= 0) return;
  if (src.w == dst.w && src.h == dst.h)
    canvas_.blit(e.image, to_tq(src), dst.x, dst.y);
  else
    canvas_.stretch_blit(e.image, to_tq(src), to_tq(dst));
}

// One particle, sampled nearest-pixel through the inverse of its turn and
// scale. Blend modes as the emitter names them: 0 adds, 1 is ordinary
// transparency, 2 subtracts, 3 (day-night) darkens by multiplying.
void CanvasPainter::sprite(const std::string& file, double x, double y, double rotation, double sx, double sy,
                           const double* rgba, int mode) {
  Entry& e = load(file);
  if (!e.ok || sx == 0 || sy == 0) return;
  double tint[4] = {1, 1, 1, 1};
  if (rgba)
    for (int i = 0; i < 4; ++i) tint[i] = std::max(0.0, std::min(1.0, rgba[i]));
  const double hw = e.image.width / 2.0, hh = e.image.height / 2.0;
  const double c = std::cos(rotation), s = std::sin(rotation);
  // The bounding box of the turned, scaled image.
  double ex = std::abs(c * hw * sx) + std::abs(s * hh * sy), ey = std::abs(s * hw * sx) + std::abs(c * hh * sy);
  int x0 = static_cast<int>(std::floor(x - ex)), x1 = static_cast<int>(std::ceil(x + ex));
  int y0 = static_cast<int>(std::floor(y - ey)), y1 = static_cast<int>(std::ceil(y + ey));
  const auto& clip = canvas_.clip();
  x0 = std::max(x0, clip.x);
  y0 = std::max(y0, clip.y);
  x1 = std::min(x1, clip.x + clip.width);
  y1 = std::min(y1, clip.y + clip.height);
  const auto& surf = canvas_.surface();
  for (int py = y0; py < y1; ++py)
    for (int px = x0; px < x1; ++px) {
      double dx = px + 0.5 - x, dy = py + 0.5 - y;
      double u = (c * dx + s * dy) / sx + hw, v = (-s * dx + c * dy) / sy + hh;
      int iu = static_cast<int>(std::floor(u)), iv = static_cast<int>(std::floor(v));
      if (iu < 0 || iv < 0 || iu >= e.image.width || iv >= e.image.height) continue;
      const auto& src = e.image.at(iu, iv);
      double a = src.a / 255.0 * tint[3];
      if (a <= 0) continue;
      double r = src.r * tint[0], g = src.g * tint[1], b = src.b * tint[2];
      const auto& d = surf.at(px, py);
      auto clamp8 = [](double v) { return static_cast<std::uint8_t>(std::max(0.0, std::min(255.0, v))); };
      Torque::Gui::Color out = d;
      switch (mode) {
        case 0: out = {clamp8(d.r + r * a), clamp8(d.g + g * a), clamp8(d.b + b * a), d.a}; break;
        case 2: out = {clamp8(d.r - r * a), clamp8(d.g - g * a), clamp8(d.b - b * a), d.a}; break;
        case 3:
          out = {clamp8(d.r * (1 - a + a * r / 255)), clamp8(d.g * (1 - a + a * g / 255)),
                 clamp8(d.b * (1 - a + a * b / 255)), d.a};
          break;
        default:
          out = {clamp8(d.r + (r - d.r) * a), clamp8(d.g + (g - d.g) * a), clamp8(d.b + (b - d.b) * a), d.a};
      }
      out.a = 255;
      canvas_.blend_pixel(px, py, out);
    }
}

void CanvasPainter::engineControl(const gs2::gui::Control& c, const gs2::gui::Rect& r) {
  if (on_engine_control) on_engine_control(c, r);
}

bool is_engine_control(const gs2::gui::Control& c) {
  std::string t = lower(c.type());
  return t == "guishowimgctrl" || t == "guigraalctrl" || t == "guigraal3dctrl";
}

GuiHost::GuiHost(gs2::Machine& m) : screen_(m) { screen_.install(); }

int GuiHost::load_start_scripts(const std::string& program_path, std::string& error) {
  std::ifstream in(program_path, std::ios::binary);
  if (!in) {
    error = "cannot read " + program_path;
    return 0;
  }
  std::string image((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  std::vector<gs2::StartScript> all = gs2::loadStartScripts(image, gs2::Profile::Engine600);
  std::vector<gs2::StartScript> named;
  for (auto& s : all)
    if (!s.name.empty()) named.push_back(s);
  gs2::attachStartScripts(screen_.machine(), named);
  if (named.empty()) error = "no StartScript_* in " + program_path;
  return static_cast<int>(named.size());
}

void GuiHost::pick_content() {
  if (screen_.content()) return;
  if (auto c = screen_.find("MainMenuGui2D")) screen_.setContent(c);
}

namespace {
gs2::gui::ControlPtr find_type(const gs2::gui::ControlPtr& c, const std::string& type) {
  if (!c) return nullptr;
  if (lower(c->type()) == type) return c;
  for (const auto& k : c->controls())
    if (auto f = find_type(k, type)) return f;
  return nullptr;
}
}  // namespace

gs2::gui::ControlPtr GuiHost::playfield() const { return find_type(screen_.content(), "guigraalctrl"); }

bool GuiHost::input(const Draw::InputEvent& e) {
  switch (e.type) {
    case Draw::InputEvent::MouseDown: return screen_.mouseDown(e.x, e.y, e.clicks);
    case Draw::InputEvent::KeyDown: return screen_.keyDown(e.key, e.ch, e.mods);
    case Draw::InputEvent::KeyUp: return screen_.keyUp(e.key, e.mods);
  }
  return false;
}

}  // namespace Quattro::Shell
