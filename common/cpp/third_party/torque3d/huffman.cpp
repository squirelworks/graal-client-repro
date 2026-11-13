// Torque's string Huffman coder: the character frequency table and the
// tree it builds.
//
// Copyright (c) 2012 GarageGames, LLC. MIT licence: see LICENSE.txt in this
// folder. The table is Torque3D's (core/stream/bitStream.cpp); the tree is
// built the way that source builds it, so the codes match bit for bit.
#include "huffman.hpp"

namespace torque3d {

namespace {

const unsigned kFreqs[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 329, 21, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    2809, 68, 0, 27, 0, 58, 3, 62, 4, 7, 0, 0, 15, 65, 554, 3,
    394, 404, 189, 117, 30, 51, 27, 15, 34, 32, 80, 1, 142, 3, 142, 39,
    0, 144, 125, 44, 122, 275, 70, 135, 61, 127, 8, 12, 113, 246, 122, 36,
    185, 1, 149, 309, 335, 12, 11, 14, 54, 151, 0, 0, 2, 0, 0, 211,
    0, 2090, 344, 736, 993, 2872, 701, 605, 646, 1552, 328, 305, 1240, 735, 1533, 1713,
    562, 3, 1775, 1149, 1469, 979, 407, 553, 59, 279, 31, 0, 0, 0, 68, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
};

}  // namespace

const Huffman& Huffman::instance() {
  static const Huffman h;
  return h;
}

Huffman::Huffman() {
  // Leaves are -(c + 1); node 0 is the root (a copy of the last node made).
  struct Wrap {
    bool leaf;
    int index;
  };
  unsigned leafPop[256];
  for (int i = 0; i < 256; ++i) leafPop[i] = kFreqs[i] + 1;
  nodes_.push_back(Node{});
  std::vector<Wrap> wraps;
  for (int i = 0; i < 256; ++i) wraps.push_back({true, i});
  auto pop = [&](const Wrap& w) { return w.leaf ? leafPop[w.index] : nodes_[w.index].pop; };
  auto ref = [](const Wrap& w) { return w.leaf ? -(w.index + 1) : w.index; };
  while (wraps.size() != 1) {
    unsigned m1 = 0xfffffffeu, m2 = 0xffffffffu;
    int i1 = -1, i2 = -1;
    for (int i = 0; i < static_cast<int>(wraps.size()); ++i) {
      const unsigned p = pop(wraps[i]);
      if (p < m1) {
        m2 = m1;
        i2 = i1;
        m1 = p;
        i1 = i;
      } else if (p < m2) {
        m2 = p;
        i2 = i;
      }
    }
    Node n;
    n.pop = pop(wraps[i1]) + pop(wraps[i2]);
    n.child0 = ref(wraps[i1]);
    n.child1 = ref(wraps[i2]);
    nodes_.push_back(n);
    const int lo = i1 < i2 ? i1 : i2, hi = i1 < i2 ? i2 : i1;
    wraps[lo] = {false, static_cast<int>(nodes_.size()) - 1};
    if (i2 != static_cast<int>(wraps.size()) - 1) wraps[hi] = wraps.back();
    wraps.pop_back();
  }
  nodes_[0] = nodes_[wraps[0].index];
  std::vector<uint8_t> code;
  generate(0, code);
}

void Huffman::generate(int node, std::vector<uint8_t>& code) {
  if (node < 0) {
    codes_[-(node + 1)] = code;
    return;
  }
  code.push_back(0);
  generate(nodes_[node].child0, code);
  code.back() = 1;
  generate(nodes_[node].child1, code);
  code.pop_back();
}

}  // namespace torque3d
