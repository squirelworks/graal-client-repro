#include "resources.hpp"

#include "read_3ds.hpp"

#include <cctype>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <system_error>

namespace fs = std::filesystem;

namespace graal3d::render {

std::string lowerName(const std::string& name) {
  // The base name only: a server names files without folders, and a
  // shape may name its texture with one.
  std::string base = name;
  const size_t slash = base.find_last_of("/\\");
  if (slash != std::string::npos) base = base.substr(slash + 1);
  for (char& c : base) c = char(std::tolower(static_cast<unsigned char>(c)));
  return base;
}

namespace {

std::string extensionOf(const std::string& lower) {
  const size_t dot = lower.find_last_of('.');
  return dot == std::string::npos ? std::string() : lower.substr(dot);
}

bool readAll(const std::string& path, std::vector<uint8_t>& out) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  f.seekg(0, std::ios::end);
  const std::streamoff size = f.tellg();
  if (size < 0 || size > (64 << 20)) return false;  // rebuild policy: 64 MiB
  f.seekg(0);
  out.resize(size_t(size));
  return size == 0 || bool(f.read(reinterpret_cast<char*>(out.data()), size));
}

const char* const kImageExtensions[] = {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tga"};

}  // namespace

void Resources::addRoot(const std::string& dir) {
  roots_.push_back(dir);
  rescan();
}

void Resources::rescan() {
  index_.clear();
  for (const std::string& root : roots_) {
    std::error_code ec;
    fs::recursive_directory_iterator it(root, fs::directory_options::skip_permission_denied, ec), end;
    for (; !ec && it != end; it.increment(ec)) {
      if (!it->is_regular_file(ec)) continue;
      const std::string key = lowerName(it->path().filename().string());
      index_.emplace(key, it->path().string());  // the first root wins
    }
  }
  // Forget misses so new files load; keep what loaded.
  for (auto it = shapes_.begin(); it != shapes_.end();) it = it->second ? std::next(it) : shapes_.erase(it);
  for (auto it = textures_.begin(); it != textures_.end();) it = it->second ? std::next(it) : textures_.erase(it);
  logged_.clear();
}

std::string Resources::find(const std::string& name) const {
  auto it = index_.find(lowerName(name));
  return it == index_.end() ? std::string() : it->second;
}

void Resources::note(const std::string& what) {
  if (log_ && logged_.insert(what).second) log_(what);
}

const Shape* Resources::shape(const std::string& name) {
  const std::string key = lowerName(name);
  auto it = shapes_.find(key);
  if (it != shapes_.end()) return it->second.get();
  std::unique_ptr<Shape> loaded;
  const std::string path = find(key);
  const std::string ext = extensionOf(key);
  if (path.empty()) {
    note("Graal3D: shape " + name + " is not here");
  } else if (ext != ".3ds") {
    note("Graal3D: cannot draw " + ext + " shapes yet (" + name + ")");
  } else {
    std::vector<uint8_t> bytes;
    auto s = std::make_unique<Shape>();
    std::string error;
    if (!readAll(path, bytes)) {
      note("Graal3D: cannot read " + path);
    } else if (!read3ds(bytes, *s, error)) {
      note("Graal3D: " + name + ": " + error);
    } else {
      loaded = std::move(s);
    }
  }
  const Shape* result = loaded.get();
  shapes_[key] = std::move(loaded);
  return result;
}

std::string Resources::lookupTexturePath(const std::string& name) const {
  const std::string key = lowerName(name);
  std::string path = find(key);
  if (!path.empty()) return path;
  // No such file: try the image extensions on the name without its own.
  std::string stem = key;
  const std::string ext = extensionOf(key);
  if (!ext.empty()) stem = key.substr(0, key.size() - ext.size());
  // A 5.x client stores downloaded images under their name without an
  // extension (levels3d/images/<name>), while shapes and the Sky still
  // name them with one (the Sharp3D capture, 2026-11-24).
  if (!ext.empty()) {
    path = find(stem);
    if (!path.empty()) return path;
  }
  for (const char* e : kImageExtensions) {
    path = find(stem + e);
    if (!path.empty()) return path;
  }
  return {};
}

const Texture* Resources::texture(const std::string& name) {
  if (name.empty()) return nullptr;
  const std::string key = lowerName(name);
  auto it = textures_.find(key);
  if (it != textures_.end()) return it->second.get();
  std::unique_ptr<Texture> loaded;
  const std::string path = lookupTexturePath(key);
  if (path.empty()) {
    note("Graal3D: texture " + name + " is not here");
  } else {
    std::vector<uint8_t> bytes;
    auto t = std::make_unique<Texture>();
    std::string error;
    if (!readAll(path, bytes) || !decodeImage(bytes.data(), bytes.size(), *t, error)) {
      note("Graal3D: cannot read texture " + path + (error.empty() ? "" : ": " + error));
    } else {
      loaded = std::move(t);
    }
  }
  const Texture* result = loaded.get();
  textures_[key] = std::move(loaded);
  return result;
}

void Resources::putShape(const std::string& name, Shape shape) {
  shapes_[lowerName(name)] = std::make_unique<Shape>(std::move(shape));
}

void Resources::putTexture(const std::string& name, Texture texture) {
  textures_[lowerName(name)] = std::make_unique<Texture>(std::move(texture));
}

}  // namespace graal3d::render
