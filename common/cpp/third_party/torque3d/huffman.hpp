// Torque's string Huffman coder (see huffman.cpp and LICENSE.txt).
//
// Copyright (c) 2012 GarageGames, LLC. MIT licence.
#pragma once

#include <cstdint>
#include <vector>

namespace torque3d {

class Huffman {
 public:
  static const Huffman& instance();

  // Bits of the code for byte `c`, first bit first.
  const std::vector<uint8_t>& code(uint8_t c) const { return codes_[c]; }

  // Walking the tree: start at root(), follow child(node, bit) until the
  // result is a leaf (negative); the byte is leafByte(result).
  static int root() { return 0; }
  int child(int node, int bit) const { return bit ? nodes_[node].child1 : nodes_[node].child0; }
  static bool isLeaf(int ref) { return ref < 0; }
  static uint8_t leafByte(int ref) { return static_cast<uint8_t>(-(ref + 1)); }

 private:
  Huffman();
  struct Node {
    unsigned pop = 0;
    int child0 = 0, child1 = 0;
  };
  void generate(int node, std::vector<uint8_t>& code);
  std::vector<Node> nodes_;
  std::vector<uint8_t> codes_[256];
};

}  // namespace torque3d
