// Malformed level content for lab runs against the real client: one
// change per case, made from a seed shape, each with what our own reader
// makes of it. A lab serves the cases from our own gserver and records
// what the client does, so each finding is a case number, its bytes and
// two verdicts side by side (CLIENT-CAPABILITY-MAPPING.md, strand 3).
//
// The seeds are game content: keep them, the cases and the manifest out
// of the repository.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace graal3d::tools {

struct FuzzCase {
  std::string what;   // the one change, in words
  std::vector<uint8_t> bytes;
};

// `format` is "3ds", "dts" or "dif". Structural cases first (chunk and
// field edges, versions, counts, names), then `randomCases` cases of a
// few random byte changes from `seed`. At most `perChunkId` occurrences
// of each .3ds chunk id get structural cases.
std::vector<FuzzCase> makeFuzzCases(const std::string& format, const std::vector<uint8_t>& seedFile, int randomCases,
                                    uint32_t seed, int perChunkId = 2);

// Our own reader's verdict: "ok meshes M triangles T materials K" or
// "refused: <error>".
std::string readerVerdict(const std::string& format, const std::vector<uint8_t>& bytes);

}  // namespace graal3d::tools
