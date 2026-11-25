// The 5.12's .ft tree shapes (Graal_analysis torque/ft-trees-512.md): a
// text L-system grown at load time, not a mesh.
//
// The file format, the growing rules (weighted rewrite rules, the first
// rule's symbol as the start, symbols with no rule kept only when they
// have a term, the string cut at 512 characters) and the term types are
// the client's [bin]. The rebuild's own until a lab shot:
// - the random numbers (so a tree has the client's shape but not its
//   exact branches),
// - the turtle: the trunk grows up +z; `yaw` turns about the current
//   heading and `pitch` tilts away from it; `absrotate` sets yaw about z
//   and pitch from +z;
// - a branch is a six-sided tapered tube from width w0 to w1 (then
//   w0 = w1 and w1 *= widthRatio), its length times `size`;
// - a leaf is two crossed quads `size` wide, textured from its slot's
//   whole image; the billboard is not drawn.
#pragma once

#include "mesh.hpp"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace graal3d::render {

struct FtTerm {
  enum Type { kPush, kPop, kBranch, kMove, kLeaf, kRotate, kAbsRotate, kResize };
  Type type = kMove;
  bool noBranch = false;
  int texBranch = 0, texLeaf = 0, coordLeaf = 0;
  float size = 1;
  float widthRatio = 1;
  float lengthRatio[2] = {1, 1};
  float yaw[2] = {0, 0};
  float pitch[2] = {0, 0};
};

struct FtRule {
  float weight = 1;
  std::string replacement;
};

struct FtTree {
  float width[2] = {0.5f, 0.5f};
  float length = 1;
  int defaultLevels = 1;
  std::string billboard;
  float billboardSize[2] = {0, 0};
  char start = 0;  // the first rule's symbol
  std::map<char, std::vector<FtRule>> rules;
  std::map<char, FtTerm> terms;
  std::string textures[8];
};

constexpr size_t kFtMaxString = 512;
constexpr uint32_t kFtDefaultSeed = 1;  // the rebuild's own

bool parseFt(const std::string& text, FtTree& out, std::string& error);
// The grown string after `levels` rounds (clamped to 1..15; 0 is the
// file's defaultLevels).
std::string growFt(const FtTree& tree, uint32_t seed, int levels);
// The tree as a shape: material i is texture slot i.
Shape ftShape(const FtTree& tree, uint32_t seed, int levels);

bool readFt(const std::vector<uint8_t>& bytes, Shape& out, std::string& error);

}  // namespace graal3d::render
