#include "dso.hpp"
#include "instructions.hpp"

#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
  if ((argc != 3 && argc != 4) || (argc == 4 && std::string(argv[3]) != "--instructions") ||
      (std::string(argv[1]) != "--little-floats" &&
                    std::string(argv[1]) != "--big-floats")) {
    std::cerr << "usage: dso-inspect --little-floats|--big-floats FILE [--instructions]\n";
    return 2;
  }
  std::ifstream input(argv[2], std::ios::binary | std::ios::ate);
  if (!input) { std::cerr << "could not open DSO\n"; return 2; }
  const auto size = input.tellg();
  if (size < 0 || size > static_cast<std::streamoff>(Torque::dso_max_bytes)) {
    std::cerr << "DSO size exceeds reader limit\n";
    return 2;
  }
  std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
  input.seekg(0);
  if (!input.read(reinterpret_cast<char*>(bytes.data()), size)) {
    std::cerr << "could not read DSO\n";
    return 2;
  }
  Torque::DsoBlock block;
  Torque::DsoError error;
  const auto order = std::string(argv[1]) == "--big-floats"
                         ? Torque::FloatOrder::big : Torque::FloatOrder::little;
  if (!Torque::load_dso(bytes, order, block, error)) {
    std::cerr << "DSO byte " << error.offset << ": " << error.message << '\n';
    return 1;
  }
  std::cout << "DSO33 format-only: " << block.code.size() << " code words, "
            << block.lines.size() << " line pairs, " << block.identifiers.size()
            << " identifier groups; not executed\n";
  if (argc == 4) {
    std::vector<Torque::DsoInstruction> instructions;
    Torque::InstructionError instruction_error;
    if (!Torque::decode_instructions(block.code, instructions, instruction_error)) {
      std::cerr << "DSO word " << instruction_error.ip << ": " << instruction_error.message << '\n';
      return 1;
    }
    std::cout << instructions.size() << " instructions; not executed\n";
  }
}
