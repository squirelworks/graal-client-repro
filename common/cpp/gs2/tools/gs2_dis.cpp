// gs2-dis: print a GS2 bytecode file as the loader reads it.
//   gs2-dis FILE

#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>

#include "../gs2.hpp"

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: gs2-dis FILE\n");
    return 2;
  }
  std::ifstream f(argv[1], std::ios::binary);
  if (!f) {
    std::fprintf(stderr, "cannot open %s\n", argv[1]);
    return 2;
  }
  const std::string bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  auto r = gs2::load(bytes);
  if (!r.ok()) {
    std::fprintf(stderr, "%s: %s\n", argv[1], r.error.c_str());
    return 1;
  }
  std::fputs(gs2::disassemble(*r.script).c_str(), stdout);
  return 0;
}
