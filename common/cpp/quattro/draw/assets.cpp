#include "assets.hpp"

#include "body_colors.hpp"

#include <cctype>

namespace Quattro::Draw {

namespace {
std::string lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}
bool safe(const std::string& n) {
  return !n.empty() && n.find('/') == std::string::npos && n.find('\\') == std::string::npos &&
         n.find("..") == std::string::npos;
}
}  // namespace

std::vector<std::string> asset_dirs(const std::string& root) {
  std::vector<std::string> out;
  if (root.empty()) return out;
  for (const char* sub : {"", "/levels", "/levels/ganis", "/levels/heads", "/levels/bodies", "/levels/swords",
                          "/levels/shields", "/levels/hats", "/levels/images", "/levels/tiles",
                          "/levels/images/downloads", "/ganis", "/heads", "/bodies",
                          "/swords", "/shields", "/hats", "/images"})
    out.push_back(root + sub);
  return out;
}

bool Assets::read(const std::string& name, std::vector<std::uint8_t>& out) const {
  if (!safe(name)) return false;
  std::string err;
  for (const auto& d : dirs_)
    if (Torque::Gui::read_file(d + "/" + name, out, err)) return true;
  return false;
}

const Torque::Gui::Image* Assets::image(const std::string& name) {
  std::string key = lower(name);
  auto it = images_.find(key);
  if (it != images_.end()) return it->second.get();
  std::unique_ptr<Torque::Gui::Image> img;
  std::vector<std::uint8_t> bytes;
  std::string err;
  if (read(name, bytes) || (key != name && read(key, bytes))) {
    img = std::make_unique<Torque::Gui::Image>();
    if (!Torque::Gui::decode_png(bytes, *img, err)) img.reset();
    else palettes_[key] = png_palette(bytes);
  }
  return (images_[key] = std::move(img)).get();
}

const Files::Gani* Assets::gani(const std::string& name) {
  std::string key = lower(name);
  if (key.size() > 5 && key.compare(key.size() - 5, 5, ".gani") == 0) key.resize(key.size() - 5);
  auto it = ganis_.find(key);
  if (it != ganis_.end()) return it->second.get();
  std::unique_ptr<Files::Gani> g;
  std::vector<std::uint8_t> bytes;
  if (read(key + ".gani", bytes)) {
    g = std::make_unique<Files::Gani>();
    if (!Files::read_gani(std::string_view(reinterpret_cast<const char*>(bytes.data()), bytes.size()), *g)) g.reset();
  }
  return (ganis_[key] = std::move(g)).get();
}

void Assets::forget(const std::string& name) {
  std::string key = lower(name);
  images_.erase(key);
  palettes_.erase(key);
  std::string g = key;
  if (g.size() > 5 && g.compare(g.size() - 5, 5, ".gani") == 0) g.resize(g.size() - 5);
  ganis_.erase(g);
  for (auto it = bodies_.begin(); it != bodies_.end();) {
    if (it->first.compare(0, key.size() + 1, key + ",") == 0) it = bodies_.erase(it);
    else ++it;
  }
}

void Assets::put_gani(const std::string& name, Files::Gani g) {
  ganis_[lower(name)] = std::make_unique<Files::Gani>(std::move(g));
}

void Assets::put_image(const std::string& name, Torque::Gui::Image img, std::vector<Torque::Gui::Color> palette) {
  images_[lower(name)] = std::make_unique<Torque::Gui::Image>(std::move(img));
  palettes_[lower(name)] = std::move(palette);
}

const Torque::Gui::Image* Assets::body(const std::string& name, const std::array<int, 5>& colors) {
  const Torque::Gui::Image* src = image(name);
  if (!src) return nullptr;
  const auto& pal = palettes_[lower(name)];
  if (pal.empty()) return src;
  std::string key = lower(name);
  for (int c : colors) key += "," + std::to_string(c);
  auto it = bodies_.find(key);
  if (it != bodies_.end()) return it->second.get();
  return (bodies_[key] = std::make_unique<Torque::Gui::Image>(recolour_body(*src, pal, colors))).get();
}

}  // namespace Quattro::Draw
