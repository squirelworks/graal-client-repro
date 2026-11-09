#include "../instructions.hpp"

#include <cstdlib>
#include <fstream>
#include <iostream>

using Words = std::vector<std::uint32_t>;
void require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}
void reject(const Words& code, Torque::InstructionErrorKind kind, std::size_t ip) {
  std::vector<Torque::DsoInstruction> output = {{999,13,{}}};
  Torque::InstructionError error;
  require(!Torque::decode_instructions(code, output, error) && error.kind == kind &&
          error.ip == ip && output.size() == 1 && output[0].ip == 999,
          "instruction failure changed output or reported wrong location/kind");
}
int main() {
  using Torque::InstructionErrorKind;
  std::vector<Torque::DsoInstruction> instructions;
  Torque::InstructionError error;
  const Words function = {0,0,0,0,1,13,2,0,0,65,42,63,13,13};
  require(Torque::decode_instructions(function, instructions, error) &&
          instructions.size() == 5 && instructions[0].ip == 0 &&
          instructions[0].operands == Words({0,0,0,1,13,2,0,0}) &&
          instructions[1].ip == 9 && instructions[1].opcode == 65 &&
          instructions[1].operands == Words({42}) && instructions[4].ip == 13,
          "function declaration/body boundaries differ");
  // Independent fixed-width fixture: operand payloads include reserved opcode
  // numbers. They must remain data, never become instructions.
  const Words fixed = {70,2,3,72,71,0,0,0,36,72,48,3,68,2,74,13,4,0,5,1,82};
  require(Torque::decode_instructions(fixed, instructions, error) &&
          instructions.size() == 9 && instructions[0].operands == Words({2,3,72}) &&
          instructions[2].ip == 8 && instructions.back().opcode == 82,
          "fixed operand widths differ");
  require(Torque::decode_instructions({1,0,0,4,13}, instructions, error), "object fail target rejected");
  require(Torque::decode_instructions({12,2}, instructions, error), "stream end boundary rejected");
  require(Torque::decode_instructions({0,0,0,0,0,0xffffffff,0,13}, instructions, error),
          "bodyless declaration used ignored end field");
  require(Torque::decode_instructions({}, instructions, error) && instructions.empty(),
          "empty decode did not replace previous output");
  for (std::uint32_t op : {2u,3u,72u,83u,0xffffffffu})
    reject({op}, InstructionErrorKind::unknown_opcode, 0);
  for (std::uint32_t op : {1u,4u,6u,36u,48u,65u,70u,71u,74u})
    reject({13,op}, InstructionErrorKind::truncated, 1);
  reject({0,0,0}, InstructionErrorKind::truncated, 0);
  reject({0,0,0,0,1,8,2,0}, InstructionErrorKind::truncated, 0);
  reject({0,0,0,0,1,7,0xffffffff}, InstructionErrorKind::truncated, 0);
  reject({12,1,13}, InstructionErrorKind::target, 0);
  reject({12,4,13}, InstructionErrorKind::target, 0);
  reject({1,0,0,1,13}, InstructionErrorKind::target, 0);
  reject({0,0,0,0,1,0,0,13}, InstructionErrorKind::target, 0);
  reject({0,0,0,0,1,8,0,65,42,13}, InstructionErrorKind::target, 0);
  reject(Words(1024*1024+1,13), InstructionErrorKind::code_limit, 0);
  error = {InstructionErrorKind::target, 88, "stale"};
  require(Torque::decode_instructions({13}, instructions, error) &&
          error.kind == InstructionErrorKind::none && error.message.empty(), "error not cleared");
  // Literal format fixture, independent of a DSO encoder: empty tables, four
  // code words (three instructions), no line or relocation groups.
  std::vector<unsigned char> fixture = {
    33,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0,
    4,0,0,0, 0,0,0,0, 65,42,63,13, 0,0,0,0
  };
  auto save = [&](const char* path) {
    std::ofstream stream(path, std::ios::binary);
    stream.write(reinterpret_cast<const char*>(fixture.data()), fixture.size());
    require(bool(stream), "could not write synthetic CLI fixture");
  };
  save("build/instruction-fixture.dso");
  fixture[28] = 2;
  save("build/unknown-instruction-fixture.dso");
  std::cout << "DSO instruction widths, declaration bounds and control-flow checks passed\n";
}
