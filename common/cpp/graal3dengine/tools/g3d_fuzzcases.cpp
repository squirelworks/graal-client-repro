// g3d-fuzzcases: malformed level content for a lab run against the real
// client, one change per case, with our own reader's verdict on each.
//
//   g3d-fuzzcases [options] seed.(3ds|dts|dif) outdir
//     --random N      also N cases of a few random byte changes (default 0)
//     --seed S        the random cases' seed (default 1)
//     --per-chunk N   structural cases for the first N chunks of each
//                     .3ds chunk id (default 2)
//     --prefix P      case file names: P0001.3ds, ... (default: fz)
//
// Writes outdir/<prefix>NNNN.<ext> and outdir/manifest.tsv (case, change,
// size, our reader's verdict, and an empty column for what the client
// did). Serve the cases from our own gserver only. The seed is game
// content, so the cases are too: keep them out of the repository.
#include "fuzzcases.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>

int main(int argc, char** argv) {
  int randomCases = 0, perChunk = 2;
  uint32_t seed = 1;
  std::string prefix = "fz";
  std::vector<std::string> args;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    auto value = [&]() -> const char* { return i + 1 < argc ? argv[++i] : ""; };
    if (a == "--random") randomCases = std::atoi(value());
    else if (a == "--seed") seed = uint32_t(std::strtoul(value(), nullptr, 10));
    else if (a == "--per-chunk") perChunk = std::atoi(value());
    else if (a == "--prefix") prefix = value();
    else args.push_back(a);
  }
  if (args.size() != 2) {
    std::fprintf(stderr, "usage: g3d-fuzzcases [--random N] [--seed S] [--per-chunk N] [--prefix P] seed.(3ds|dts|dif) outdir\n");
    return 2;
  }
  std::string ext = std::filesystem::path(args[0]).extension().string();
  for (char& c : ext) c = char(std::tolower(static_cast<unsigned char>(c)));
  if (ext != ".3ds" && ext != ".dts" && ext != ".dif") {
    std::fprintf(stderr, "g3d-fuzzcases: the seed must be a .3ds, .dts or .dif\n");
    return 2;
  }
  std::ifstream in(args[0], std::ios::binary);
  const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), {});
  if (!in && bytes.empty()) {
    std::fprintf(stderr, "g3d-fuzzcases: cannot read %s\n", args[0].c_str());
    return 1;
  }
  const std::string format = ext.substr(1);
  const auto cases = graal3d::tools::makeFuzzCases(format, bytes, randomCases, seed, perChunk);
  const std::filesystem::path dir = args[1];
  std::filesystem::create_directories(dir);
  std::ofstream manifest(dir / "manifest.tsv");
  manifest << "case\tchange\tbytes\trebuild reader\tclient\n";
  manifest << "seed\t" << std::filesystem::path(args[0]).filename().string() << "\t" << bytes.size() << "\t"
           << graal3d::tools::readerVerdict(format, bytes) << "\t\n";
  int n = 0;
  for (const auto& c : cases) {
    char name[64];
    std::snprintf(name, sizeof name, "%s%04d%s", prefix.c_str(), ++n, ext.c_str());
    std::ofstream o(dir / name, std::ios::binary);
    o.write(reinterpret_cast<const char*>(c.bytes.data()), std::streamsize(c.bytes.size()));
    manifest << name << "\t" << c.what << "\t" << c.bytes.size() << "\t" << graal3d::tools::readerVerdict(format, c.bytes)
             << "\t\n";
  }
  std::printf("%d cases in %s (manifest.tsv)\n", n, dir.string().c_str());
  return 0;
}
