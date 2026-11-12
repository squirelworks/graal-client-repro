// The player's own files the world passes draw from: images and ganis,
// found by name in a list of folders and kept once loaded. Nothing here
// ships with the rebuild; with no folders every lookup misses and the
// passes draw their stand-ins.
#pragma once

#include "../../../torque/gui/image.hpp"
#include "../files/gani.hpp"

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace Quattro::Draw {

class Assets {
 public:
  Assets() = default;
  explicit Assets(std::vector<std::string> dirs) : dirs_(std::move(dirs)) {}

  // A PNG by file name (no paths: anything with a slash or ".." misses);
  // null when no folder has it.
  const Torque::Gui::Image* image(const std::string& name);
  // A gani by name, with or without ".gani".
  const Files::Gani* gani(const std::string& name);
  // Puts a gani or image in place without a file (tests).
  void put_gani(const std::string& name, Files::Gani g);
  void put_image(const std::string& name, Torque::Gui::Image img);

 private:
  bool read(const std::string& name, std::vector<std::uint8_t>& out) const;
  std::vector<std::string> dirs_;
  std::map<std::string, std::unique_ptr<Torque::Gui::Image>> images_;
  std::map<std::string, std::unique_ptr<Files::Gani>> ganis_;
};

// The folders a Graal install keeps these in, under `root`.
std::vector<std::string> asset_dirs(const std::string& root);

}  // namespace Quattro::Draw
