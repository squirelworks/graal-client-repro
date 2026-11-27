// The 3D view's frame-rate bench: the conformance suite's worlds
// (Graal_analysis torque/conformance, the content of
// tools/conformance/gen_content.py), drawn offline by a renderer for a
// number of seconds, with no server. Lab runs compare the renderers on the
// same worlds the conformance cases play on the real clients; --compare
// draws each world with both renderers and reports how far apart the
// pixels are.
#pragma once

#include "graal3d5120/renderer.hpp"
#include "graal3d5120/view3d.hpp"

#include <map>
#include <string>
#include <vector>

namespace Frank {

// One world as the link would hold it after login step 6.
struct BenchWorld {
  std::string name, title;
  graal3d::GhostTable ghosts;
  int camera = -1, control = -1;
  std::map<int, std::string> chunks;  // streamed terrain chunks (zlib), by index
  int chunkCount = 0;
};

// The worlds by name: sky (C004), cube (C005), texture (C006), terrain
// (C018), water (C019), dense (C024: 1024 cubes), grass (C035) and mix
// (terrain, grass, water and the 1024 cubes together).
std::vector<std::string> bench_world_names();
bool make_bench_world(const std::string& name, BenchWorld& out);

// Writes the files the worlds name (gen_content.py's cubes and solid
// colour textures, heights.info) into `dir`. False when it cannot.
bool write_bench_content(const std::string& dir, std::string& error);

// The colours the conformance checks look for, and how much of a frame is
// each (within 24 a channel).
struct ColourShare {
  const char* name;
  uint8_t rgb[3];
  double share = 0;
};
std::vector<ColourShare> colour_shares(const Torque::Gui::Image& frame);

// How two frames of one world differ: the share of pixels more than 24
// apart in some channel, and the largest such difference.
struct FrameDiff {
  double mismatched = 0;
  int largest = 0;
};
FrameDiff diff_frames(const Torque::Gui::Image& a, const Torque::Gui::Image& b);

struct BenchOptions {
  std::string world = "all";
  RendererChoice renderer = RendererChoice::Auto;
  int seconds = 5;  // per world
  int width = 1024, height = 768;
  std::string shot_dir;  // a PNG of each world's last frame, when set
  bool compare = false;  // also draw with the software renderer and compare
};

// Prints one line per world (frames, fps, draw times) and returns the
// process exit code.
int run_bench(const BenchOptions& options);

}  // namespace Frank
