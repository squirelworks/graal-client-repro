#include "gui_host.hpp"

#include "host.hpp"
#include "image.hpp"
#include "bitmap_array.hpp"

#include "stb_image.h"

#include <cctype>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>

namespace graalengine {

namespace fs = std::filesystem;

namespace {

std::string lower(std::string s) {
  for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

uint32_t argb(gs2::gui::Color c) {
  return (uint32_t(c.a) << 24) | (uint32_t(c.r) << 16) | (uint32_t(c.g) << 8) | uint32_t(c.b);
}

// The file in `dir` whose name matches `name` without regard to case.
std::string findNoCase(const fs::path& dir, const std::string& name) {
  std::error_code ec;
  const fs::path exact = dir / name;
  if (fs::is_regular_file(exact, ec)) return exact.string();
  if (!fs::is_directory(dir, ec)) return {};
  const std::string want = lower(name);
  for (const auto& e : fs::directory_iterator(dir, ec)) {
    if (lower(e.path().filename().string()) == want && e.is_regular_file(ec)) return e.path().string();
  }
  return {};
}

bool decode(const std::string& path, std::vector<uint32_t>& out, int& w, int& h) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return false;
  const std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(in)), {});
  if (bytes.size() >= 8 && bytes[0] == 0x89 && bytes[1] == 'P' && bytes[2] == 'N' && bytes[3] == 'G') {
    Torque::Gui::Image img;
    std::string err;
    if (!Torque::Gui::decode_png(bytes, img, err)) return false;
    w = img.width;
    h = img.height;
    out.resize(std::size_t(w) * h);
    for (std::size_t i = 0; i < out.size(); ++i) {
      const auto& p = img.pixels[i];
      out[i] = (uint32_t(p.a) << 24) | (uint32_t(p.r) << 16) | (uint32_t(p.g) << 8) | p.b;
    }
    return true;
  }
  int n = 0;
  stbi_uc* px = stbi_load_from_memory(bytes.data(), static_cast<int>(bytes.size()), &w, &h, &n, 4);
  if (!px) return false;
  out.resize(std::size_t(w) * h);
  for (std::size_t i = 0; i < out.size(); ++i) {
    const stbi_uc* p = px + i * 4;
    out[i] = (uint32_t(p[3]) << 24) | (uint32_t(p[0]) << 16) | (uint32_t(p[1]) << 8) | p[2];
  }
  stbi_image_free(px);
  return true;
}

}  // namespace

std::string TextureCache::pathOf(const std::string& name) const {
  if (name.empty()) return {};
  const fs::path base(dir_);
  const std::vector<fs::path> dirs = {base / "levels3d" / "gui", base / "levels" / "gui", base};
  const bool hasExt = fs::path(name).has_extension();
  for (const auto& d : dirs) {
    if (hasExt) {
      if (auto p = findNoCase(d, name); !p.empty()) return p;
    } else {
      for (const char* ext : {".png", ".jpg", ".gif", ".bmp"})
        if (auto p = findNoCase(d, name + ext); !p.empty()) return p;
    }
  }
  return {};
}

TextureCache::Entry* TextureCache::get(const std::string& name) {
  const std::string key = lower(name);
  auto it = byName_.find(key);
  if (it != byName_.end()) return it->second.get();
  std::unique_ptr<Entry> e;
  const std::string path = pathOf(name);
  int w = 0, h = 0;
  std::vector<uint32_t> px;
  if (!path.empty() && decode(path, px, w, h)) {
    e = std::make_unique<Entry>();
    e->name = name;
    e->pixels = std::move(px);
    e->tex.name = e->name.c_str();
    e->tex.width = w;
    e->tex.height = h;
    e->tex.pixels = e->pixels.data();
  }
  Entry* raw = e.get();
  byName_[key] = std::move(e);
  return raw;
}

void SlotPainter::setClip(const gs2::gui::Rect& r) { host::SetClippingRectangle(r.x, r.y, r.w, r.h); }

void SlotPainter::fill(const gs2::gui::Rect& r, gs2::gui::Color c) {
  if (c.a == 0 || r.w <= 0 || r.h <= 0) return;
  host::FillScreenRectangle(r.x, r.y, r.w, r.h, argb(c));
}

void SlotPainter::text(int x, int y, const std::string& s, const std::string& font, int size, gs2::gui::Color c) {
  host::DrawText(x, y, s.c_str(), font.c_str(), size, 0, argb(c));
}

int SlotPainter::textWidth(const std::string& s, const std::string& font, int size) {
  return host::GetTextWidth(s.c_str(), font.c_str(), size, 0);
}

int SlotPainter::fontHeight(const std::string& font, int size) {
  const int h = host::GetTextHeight(font.c_str(), size, 0);
  return h > 0 ? h : size;
}

bool SlotPainter::bitmapSize(const std::string& file, int& w, int& h) {
  auto* e = cache_.get(file);
  if (!e) return false;
  w = e->tex.width;
  h = e->tex.height;
  return true;
}

std::vector<gs2::gui::Rect> SlotPainter::cells(const std::string& file) {
  auto* e = cache_.get(file);
  if (!e) return {};
  if (!e->cellsRead) {
    e->cellsRead = true;
    Torque::Gui::Image img(e->tex.width, e->tex.height);
    for (std::size_t i = 0; i < e->pixels.size(); ++i) {
      const uint32_t p = e->pixels[i];
      img.pixels[i] = {uint8_t(p >> 16), uint8_t(p >> 8), uint8_t(p), uint8_t(p >> 24)};
    }
    for (const auto& c : Torque::Gui::split_bitmap_array(img).cells)
      e->cells.push_back({c.x, c.y, c.width, c.height});
  }
  return e->cells;
}

void SlotPainter::bitmap(const std::string& file, const gs2::gui::Rect& src, const gs2::gui::Rect& dst) {
  auto* e = cache_.get(file);
  if (!e || dst.w <= 0 || dst.h <= 0 || src.w <= 0 || src.h <= 0) return;
  if (src.w == dst.w && src.h == dst.h) {
    host::DrawGraphics(&e->tex, dst.x, dst.y, src.x, src.y, src.w, src.h, 0xFFFFFFFFu);
  } else if (host::hasDrawGraphicsStretched()) {
    host::DrawGraphicsStretched(&e->tex, dst.x, dst.y, dst.w, dst.h, src.x, src.y, src.w, src.h, 0xFFFFFFFFu);
  } else {
    // The 5.0 launcher has no stretched draw: tile the source instead.
    for (int y = 0; y < dst.h; y += src.h)
      for (int x = 0; x < dst.w; x += src.w)
        host::DrawGraphics(&e->tex, dst.x + x, dst.y + y, src.x, src.y, std::min(src.w, dst.w - x),
                           std::min(src.h, dst.h - y), 0xFFFFFFFFu);
  }
}

std::string torqueKeyName(int vk) {
  if (vk >= 'A' && vk <= 'Z') return std::string(1, char(vk - 'A' + 'a'));
  if (vk >= '0' && vk <= '9') return std::string(1, char(vk));
  if (vk >= 0x70 && vk <= 0x7B) return "F" + std::to_string(vk - 0x70 + 1);
  switch (vk) {
    case 0x08: return "backspace";
    case 0x09: return "tab";
    case 0x0D: return "return";
    case 0x1B: return "escape";
    case 0x20: return "space";
    case 0x21: return "pageup";
    case 0x22: return "pagedown";
    case 0x23: return "end";
    case 0x24: return "home";
    case 0x25: return "left";
    case 0x26: return "up";
    case 0x27: return "right";
    case 0x28: return "down";
    case 0x2D: return "insert";
    case 0x2E: return "delete";
    case 0x10: return "lshift";
    case 0x11: return "lcontrol";
    case 0x12: return "lalt";
    default: return {};
  }
}

namespace {
std::string modText(int mods) {
  std::string s;
  auto add = [&](const char* n) { s += s.empty() ? n : std::string(" ") + n; };
  if (mods & GRAAL_MOD_SHIFT) add("shift");
  if (mods & GRAAL_MOD_CTRL) add("ctrl");
  if (mods & GRAAL_MOD_ALT) add("alt");
  return s;
}
}  // namespace

void ScreenControl::resize(int w, int h) {
  Control::resize(w, h);
  screen_.setSize(w, h);
}

void ScreenControl::onRender(const graal_rect&) { gs2::gui::drawScreen(screen_, painter_); }

bool ScreenControl::onInput(const InputEvent& ev) {
  switch (ev.kind) {
    case InputEvent::MouseDown:
      if (ev.button == GRAAL_MOUSE_LEFT) return screen_.mouseDown(ev.x, ev.y, ev.clicks);
      return false;
    case InputEvent::KeyDown: {
      // A character-only event (vk 0) still reaches the text edit.
      std::string key = torqueKeyName(ev.vk);
      if (key.empty() && ev.ch >= 32 && ev.ch < 127) key = std::string(1, char(std::tolower(ev.ch)));
      if (key.empty() && ev.ch == 0) return false;
      return screen_.keyDown(key, ev.ch, modText(ev.mods));
    }
    case InputEvent::KeyUp: {
      const std::string key = torqueKeyName(ev.vk);
      if (key.empty()) return false;
      return screen_.keyUp(key, modText(ev.mods));
    }
    default:
      return false;
  }
}

}  // namespace graalengine
