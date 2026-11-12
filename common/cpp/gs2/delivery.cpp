#include "delivery.hpp"

namespace gs2 {

long readGraalInt(const std::string& s, std::size_t at, int bytes) {
  long v = 0;
  for (int i = 0; i < bytes; ++i) v = (v << 7) | ((static_cast<unsigned char>(s[at + static_cast<std::size_t>(i)]) - 32) & 0x7F);
  return v;
}

namespace {

// One length byte (count plus 32), the name, then the rest.
bool splitNamed(const std::string& body, std::string& name, std::string& rest) {
  if (body.empty()) return false;
  const int n = static_cast<unsigned char>(body[0]) - 32;
  if (n < 0 || static_cast<std::size_t>(n) + 1 > body.size()) return false;
  name = body.substr(1, static_cast<std::size_t>(n));
  rest = body.substr(1 + static_cast<std::size_t>(n));
  return true;
}

}  // namespace

bool deliverScript(Machine& m, int packetId, const std::string& body, const Delivery& d, std::string* error) {
  auto fail = [&](const std::string& why) {
    if (error) *error = why;
    return false;
  };
  std::string name, rest;
  switch (packetId) {
    case 131: {
      if (body.size() < 3) return fail("131: body shorter than its id");
      const int id = static_cast<int>(readGraalInt(body, 0, 3));
      VarPtr target = d.objectById ? d.objectById(id) : nullptr;
      if (!target) return fail("131: no object " + std::to_string(id));
      return m.setScript(target, body.substr(3), error);
    }
    case 132:
      if (!splitNamed(body, name, rest)) return fail("132: bad name length");
      return m.setScript(m.newVar(name), rest, error);
    case 133:
      if (!splitNamed(body, name, rest)) return fail("133: bad name length");
      return m.addClassScript(name, rest, error);
    case 134:
      if (!splitNamed(body, name, rest)) return fail("134: bad name length");
      return m.addClassScript("gani." + name, rest, error);
    case 193: {
      if (body.size() < 5) return fail("193: body shorter than its CRC");
      const auto crc = static_cast<std::uint32_t>(readGraalInt(body, 0, 5));
      name = body.substr(5);
      std::string bytes = d.cachedWeapon ? d.cachedWeapon(name, crc) : std::string();
      if (bytes.empty()) return fail("193: no cached weapon " + name + " with that CRC");
      return m.setScript(m.newVar(name), bytes, error);
    }
    default:
      return fail("packet " + std::to_string(packetId) + " carries no script");
  }
}

}  // namespace gs2
