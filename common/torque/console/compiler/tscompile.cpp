// ts-compile: compiles one TorqueScript source file to a DSO v33 file.
#include "compile.hpp"

#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

int main(int argc, char** argv) {
  const bool big = argc == 4 && std::string(argv[3]) == "--big-floats";
  if (argc != 3 && !big) {
    std::cerr << "usage: ts-compile IN.cs OUT.dso [--big-floats]\n";
    return 2;
  }
  std::ifstream in(argv[1], std::ios::binary);
  if (!in) { std::cerr << "could not open " << argv[1] << '\n'; return 2; }
  const std::string source((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  Torque::DsoBlock block;
  Torque::CompileError error;
  if (!Torque::compile_script(source, block, error)) {
    std::cerr << argv[1] << " line " << error.line << ": " << error.message << '\n';
    return 1;
  }
  const auto bytes = Torque::write_dso(block, big ? Torque::FloatOrder::big : Torque::FloatOrder::little);
  std::ofstream out(argv[2], std::ios::binary);
  out.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  if (!out) { std::cerr << "could not write " << argv[2] << '\n'; return 2; }
  return 0;
}
