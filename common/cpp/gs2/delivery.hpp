#pragma once

// Script bytes that arrive from the server, fed into the machine. The ids
// and their bodies are Graal_analysis `client-internals/gs2-vm-from-engines.md`,
// "How the bytes arrive" (4.2.0.8). The 5.x and 6.x envelopes around these
// (packet 140, the GRESCR01 cache) are the engine program's.

#include <cstdint>
#include <functional>
#include <string>

#include "gs2.hpp"

namespace gs2 {

struct Delivery {
  // Packet 131: the object a three-byte id names (below 1000 the level's
  // table, 1000 and above the second table). Null drops the script.
  std::function<VarPtr(int id)> objectById;
  // Packet 193: the cached weapon `.code` bytes for this name when their
  // CRC32 matches; empty when there is no match (the engine asks again).
  std::function<std::string(const std::string& name, std::uint32_t crc)> cachedWeapon;
};

// Feed one packet body (without its id byte). Returns false, with a reason,
// when the body is too short, the target is missing or the bytecode does not
// load.
bool deliverScript(Machine& m, int packetId, const std::string& body, const Delivery& d,
                   std::string* error = nullptr);

// The biased integer encodings these bodies use: each byte holds seven bits
// plus 32, most significant first.
long readGraalInt(const std::string& s, std::size_t at, int bytes);

}  // namespace gs2
