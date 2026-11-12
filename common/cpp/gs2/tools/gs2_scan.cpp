// gs2-scan: find the compiled GS2 scripts a program carries as zlib
// streams, and report what the machine can run of them.
//   gs2-scan [--profile 4.2|5.0|6.00] [--out DIR] [--run] FILE
// --run attaches every script to its own variable on one machine, runs
// `created` and reports the commands they called that nothing provides.
// The program is the player's own copy; nothing it contains is kept here.

#include <zlib.h>

#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <map>
#include <string>

#include "../gs2.hpp"

namespace {

// Inflate one zlib stream that starts at `p`; empty when it is not one.
std::string inflateAt(const unsigned char* p, std::size_t n) {
  z_stream z;
  std::memset(&z, 0, sizeof z);
  if (inflateInit(&z) != Z_OK) return {};
  z.next_in = const_cast<unsigned char*>(p);
  z.avail_in = static_cast<uInt>(n > 0x7fffffff ? 0x7fffffff : n);
  std::string out;
  unsigned char buf[65536];
  int rc = Z_OK;
  while (rc == Z_OK && out.size() < (16u << 20)) {
    z.next_out = buf;
    z.avail_out = sizeof buf;
    rc = inflate(&z, Z_NO_FLUSH);
    out.append(reinterpret_cast<char*>(buf), sizeof buf - z.avail_out);
  }
  inflateEnd(&z);
  return rc == Z_STREAM_END ? out : std::string();
}

}  // namespace

int main(int argc, char** argv) {
  gs2::Profile profile = gs2::Profile::Engine42;
  std::string outDir, file;
  bool runThem = false;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--profile" && i + 1 < argc) {
      const std::string p = argv[++i];
      profile = p == "5.0" ? gs2::Profile::Engine50 : p == "6.00" ? gs2::Profile::Engine600 : gs2::Profile::Engine42;
    } else if (a == "--run") {
      runThem = true;
    } else if (a == "--out" && i + 1 < argc) {
      outDir = argv[++i];
    } else {
      file = a;
    }
  }
  if (file.empty()) {
    std::fprintf(stderr, "usage: gs2-scan [--profile 4.2|5.0|6.00] [--out DIR] FILE\n");
    return 2;
  }
  std::ifstream f(file, std::ios::binary);
  if (!f) {
    std::fprintf(stderr, "cannot open %s\n", file.c_str());
    return 2;
  }
  const std::string data((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
  const auto* d = reinterpret_cast<const unsigned char*>(data.data());

  int scripts = 0, failed = 0;
  std::size_t functions = 0, instructions = 0;
  std::map<int, std::size_t> refused;
  gs2::Machine machine(profile);
  machine.logMissingFunctions = true;
  for (std::size_t i = 0; i + 2 < data.size(); ++i) {
    if (d[i] != 0x78 || (d[i + 1] != 0x01 && d[i + 1] != 0x5e && d[i + 1] != 0x9c && d[i + 1] != 0xda)) continue;
    const std::string s = inflateAt(d + i, data.size() - i);
    static const char head[8] = {0, 0, 0, 1, 0, 0, 0, 4};
    if (s.size() < 16 || std::memcmp(s.data(), head, 8) != 0) continue;
    auto r = gs2::load(s);
    if (!r.ok()) {
      std::printf("stream %d: %s\n", scripts, r.error.c_str());
      ++failed;
      ++scripts;
      continue;
    }
    functions += r.script->functions.size();
    instructions += r.script->code.size();
    for (const auto& in : r.script->code)
      if (!gs2::opcodeInProfile(in.op, profile) || !gs2::opcodeImplemented(in.op)) ++refused[in.op];
    if (runThem) {
      char name[32];
      std::snprintf(name, sizeof name, "script%02d", scripts);
      machine.setScript(machine.newVar(name), s);
    }
    if (!outDir.empty()) {
      char name[64];
      std::snprintf(name, sizeof name, "/script%02d.gs2", scripts);
      std::ofstream o(outDir + name, std::ios::binary);
      o << s;
    }
    ++scripts;
  }
  std::printf("scripts %d, unreadable %d, functions %zu, instructions %zu\n", scripts, failed, functions, instructions);
  if (!refused.empty()) {
    std::printf("opcodes not yet run on engine %s:", gs2::profileName(profile));
    for (const auto& [op, n] : refused) std::printf(" %s(%d)x%zu", gs2::opcodeName(op).c_str(), op, n);
    std::printf("\n");
  }
  if (runThem) {
    for (int pass = 0; pass < 3; ++pass) machine.runScripts();
    std::printf("ran %llu instructions, %zu objects made\n",
                static_cast<unsigned long long>(machine.instructionsRun()), machine.objects().size());
    for (const auto& e : machine.errors()) std::printf("  %s\n", e.c_str());
  }
  return failed ? 1 : 0;
}
