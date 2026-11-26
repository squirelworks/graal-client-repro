// Where the renderer finds the files a world names.
//
// A 5.x client files what the server sends it under `levels3d/` by
// extension (`shapes`, `interior`, `images`, `trees`, ...) and asks for
// files by lower-case name (Graal_analysis graal3d/torque-engine-4x.md,
// client-internals/mac-ppc-runtime-surface-2026-11-09.md). Sky textures
// are named without an extension (`sky_fr`), so a texture name with none
// is tried with the image extensions the Seihai gserver also tries
// (bin/docs/graal3d.md). The roots are searched recursively, so the
// subfolder a file landed in does not matter.
#pragma once

#include "mesh.hpp"
#include "texture.hpp"

#include <functional>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace graal3d::render {

class Resources {
 public:
  using Log = std::function<void(const std::string&)>;

  void setLog(Log log) { log_ = std::move(log); }
  void addRoot(const std::string& dir);
  // Scans the roots again and forgets every file that was missing, so
  // files that arrived since (TCP downloads) are picked up.
  void rescan();

  // The full path of a file by name (case-insensitive, any subfolder), or
  // "" when no root has it.
  std::string find(const std::string& name) const;

  // Loaded and cached by lower-case name; null when missing or unreadable.
  const Shape* shape(const std::string& name);
  const Texture* texture(const std::string& name);

  // Which image files load. The 5.12 client decodes a texture by its
  // content, whatever its name says, and draws only 8-bit PNG, JPEG and
  // GIF; BMP, TGA, DDS and 16-bit PNG stay undrawn (white), and GIF
  // transparency draws opaque white (lab, 2026-11-25: Graal_analysis
  // T3D-032). kAll loads everything stb_image reads (tools, older
  // clients not yet measured).
  enum class ImageFormats { kClient512, kAll };
  // The largest side the 5.12 draws (lab, Graal_analysis
  // torque/live-512-shapes-2026-11-25.md: 1024 draws, 2048 and 4096 do not;
  // the limit between them is the rebuild's guess).
  static constexpr int kClientMaxTextureSide = 1024;
  void setImageFormats(ImageFormats f) { formats_ = f; }

  // Shape and texture names (lower case) looked up since the last rescan
  // and not found in any root: what a host may ask the server for.
  const std::set<std::string>& missing() const { return missing_; }
  // Every shape name (lower case) looked up since the cache was made,
  // found or not. The 5.12 asks the server for each shape a world names on
  // every visit, even with a copy cached, and draws what comes back
  // (Graal_analysis conformance C028).
  const std::set<std::string>& shapesNamed() const { return shapesNamed_; }
  // Drops a loaded shape or texture, so the next lookup reads its file
  // again (a newer copy downloaded over it).
  void forget(const std::string& name);

  // For tests: put a shape or texture in the cache without a file.
  void putShape(const std::string& name, Shape shape);
  void putTexture(const std::string& name, Texture texture);

 private:
  std::string lookupTexturePath(const std::string& name) const;
  void note(const std::string& what);

  std::vector<std::string> roots_;
  std::map<std::string, std::string> index_;  // lower-case base name -> path
  std::map<std::string, std::unique_ptr<Shape>> shapes_;
  std::map<std::string, std::unique_ptr<Texture>> textures_;
  std::set<std::string> logged_;
  std::set<std::string> missing_;
  std::set<std::string> shapesNamed_;
  Log log_;
  ImageFormats formats_ = ImageFormats::kClient512;
};

std::string lowerName(const std::string& name);

}  // namespace graal3d::render
